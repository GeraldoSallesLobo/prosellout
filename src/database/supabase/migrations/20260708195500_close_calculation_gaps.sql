-- Close calculation gaps confirmed by the business team:
-- - Mark Up is displayed as a percentage: avg Sell Out price / avg Sell In price - 1.
-- - Margin, Mark Up, average turnover and average coverage are calculated in
--   the Sell Out view, using Sell In only as the product/distributor cost basis.
-- - Each Sell Out row counts as one invoice for Drop Size.
-- - Coverage probability uses the full customer base for "all" and seller
--   portfolio sizes when the commercial hierarchy is filtered.

alter table sell_out
  add column if not exists delivery_date date;

alter table staging_sell_out
  add column if not exists customer_pdv_code text,
  add column if not exists sales_rep_code text,
  add column if not exists delivery_date text;

create or replace function process_sell_out_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
  for v_month in
    select distinct date_trunc('month', s.invoice_date::date)::date
    from staging_sell_out s
    where s.import_id = p_import_id and fn_is_iso_date(s.invoice_date)
  loop
    perform ensure_month_partition('sell_out', v_month);
  end loop;

  with parsed as (
    select
      s.line_number,
      d.id as distributor_id,
      c.id as customer_id,
      coalesce(sr.id, c.sales_rep_id) as sales_rep_id,
      p.id as product_id,
      coalesce(nullif(s.invoice_number, ''), p_import_id::text || '-' || s.line_number::text) as invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case
        when nullif(s.delivery_date, '') is null then null
        when fn_is_iso_date(s.delivery_date) then s.delivery_date::date
      end as delivery_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when d.id is null then 'unknown distributor code: ' || coalesce(s.distributor_code, '<null>')
        when c.id is null then 'unknown customer code/cnpj: ' ||
          coalesce(nullif(s.customer_pdv_code, ''), nullif(s.customer_cnpj, ''), '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when nullif(s.delivery_date, '') is not null and not fn_is_iso_date(s.delivery_date)
          then 'invalid delivery_date: ' || coalesce(s.delivery_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_out s
    left join distributors d on d.code = s.distributor_code
    left join customers c
      on c.distributor_id = d.id
     and (
       (nullif(s.customer_pdv_code, '') is not null and c.pdv_code = s.customer_pdv_code)
       or (
         nullif(s.customer_pdv_code, '') is null
         and regexp_replace(coalesce(c.cnpj, ''), '\D', '', 'g') =
           regexp_replace(coalesce(s.customer_cnpj, ''), '\D', '', 'g')
       )
     )
    left join sales_reps sr
      on sr.distributor_id = d.id
     and sr.role = 'seller'
     and sr.code = s.sales_rep_code
    left join products p
      on fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
     and (p.distributor_id is null or p.distributor_id = d.id)
    where s.import_id = p_import_id
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  inserted as (
    insert into sell_out (
      distributor_id, customer_id, product_id, sales_rep_id,
      invoice_number, invoice_date, delivery_date, quantity, gross_value, unit_cost, import_id
    )
    select
      distributor_id, customer_id, product_id, sales_rep_id,
      invoice_number, invoice_date, delivery_date, quantity, gross_value, unit_cost, p_import_id
    from parsed
    where rejection_reason is null
    returning 1
  )
  select
    (select count(*) from inserted),
    (select count(*) from rejected)
  into v_inserted, v_rejected;

  delete from staging_sell_out where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_inserted, v_rejected;
end;
$$;

create or replace function fn_sell_out_metrics(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric,
  total_cost numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(so.gross_value), 0)::numeric,
    coalesce(sum(so.quantity), 0)::numeric,
    coalesce(sum(so.quantity * coalesce(so.unit_cost, 0)), 0)::numeric,
    count(distinct so.customer_id),
    count(*)::bigint
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  left join sales_reps sr on sr.id = so.sales_rep_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_sell_in_metrics_for_sell_out_filter(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with sell_out_scope as (
    select distinct so.distributor_id, so.product_id
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    left join sales_reps sr on sr.id = so.sales_rep_id
    where so.invoice_date between p_start and p_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
      and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
      and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
  )
  select
    coalesce(sum(si.gross_value), 0)::numeric,
    coalesce(sum(si.quantity), 0)::numeric
  from sell_in si
  join sell_out_scope scope
    on scope.distributor_id = si.distributor_id
   and scope.product_id = si.product_id
  where si.invoice_date between p_start and p_end
$$;

create or replace function fn_customer_count(
  p_distributor_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_portfolio_size bigint;
begin
  if p_sales_rep_id is not null then
    select sr.portfolio_size
    into v_portfolio_size
    from sales_reps sr
    where sr.id = p_sales_rep_id
      and sr.status = 'active'
      and sr.distributor_id in (select authorized_distributor_ids(p_distributor_id));

    if v_portfolio_size is not null then
      return v_portfolio_size;
    end if;
  end if;

  if p_supervisor_id is not null then
    select sum(sr.portfolio_size)::bigint
    into v_portfolio_size
    from sales_reps sr
    where sr.supervisor_id = p_supervisor_id
      and sr.status = 'active'
      and sr.distributor_id in (select authorized_distributor_ids(p_distributor_id));

    if v_portfolio_size is not null then
      return v_portfolio_size;
    end if;
  end if;

  return (
    select count(*)
    from customers c
    where c.status = 'active'
      and c.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
      and (p_sales_rep_id is null or c.sales_rep_id = p_sales_rep_id)
      and (
        p_supervisor_id is null
        or exists (
          select 1
          from sales_reps sr
          where sr.id = c.sales_rep_id and sr.supervisor_id = p_supervisor_id
        )
      )
  );
end;
$$;

create or replace function report_status_mtd(
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cur record;
  v_prev record;
  v_tgt record;
  v_cur_si record;
  v_prev_si record;
  v_total_days integer;
  v_elapsed_days integer;
  v_projected_value numeric;
  v_cur_ticket numeric;
  v_prev_ticket numeric;
  v_tgt_ticket numeric;
  v_cur_avg_price numeric;
  v_prev_avg_price numeric;
  v_tgt_avg_price numeric;
  v_cur_sell_in_price numeric;
  v_prev_sell_in_price numeric;
  v_pdv_count bigint;
begin
  select * into v_cur from fn_sell_out_metrics(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev from fn_sell_out_metrics(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_cur_si from fn_sell_in_metrics_for_sell_out_filter(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev_si from fn_sell_in_metrics_for_sell_out_filter(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_tgt from fn_target_metrics(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_distributor_id, p_macro_category_id, p_category_id, p_subcategory_id,
    p_product_id, p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  v_total_days := p_current_end - p_current_start + 1;
  v_elapsed_days := greatest(1, least(current_date, p_current_end) - p_current_start + 1);
  v_projected_value := fn_safe_div(v_cur.total_value, v_elapsed_days) * v_total_days;

  v_cur_ticket := fn_safe_div(v_cur.total_value, v_cur.coverage::numeric);
  v_prev_ticket := fn_safe_div(v_prev.total_value, v_prev.coverage::numeric);
  v_tgt_ticket := fn_safe_div(v_tgt.total_value, v_tgt.coverage::numeric);

  v_cur_avg_price := fn_safe_div(v_cur.total_value, v_cur.total_quantity);
  v_prev_avg_price := fn_safe_div(v_prev.total_value, v_prev.total_quantity);
  v_tgt_avg_price := fn_safe_div(v_tgt.total_value, v_tgt.total_quantity);
  v_cur_sell_in_price := fn_safe_div(v_cur_si.total_value, v_cur_si.total_quantity);
  v_prev_sell_in_price := fn_safe_div(v_prev_si.total_value, v_prev_si.total_quantity);

  v_pdv_count := fn_customer_count(
    p_distributor_id, p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  return jsonb_build_object(
    'sell_out_value', jsonb_build_object(
      'current', v_cur.total_value,
      'target', v_tgt.total_value,
      'previous', v_prev.total_value,
      'current_vs_target', fn_ratio(v_cur.total_value, v_tgt.total_value),
      'previous_vs_target', fn_ratio(v_prev.total_value, v_tgt.total_value)
    ),
    'sell_out_quantity', jsonb_build_object(
      'current', v_cur.total_quantity,
      'target', v_tgt.total_quantity,
      'previous', v_prev.total_quantity,
      'current_vs_target', fn_ratio(v_cur.total_quantity, v_tgt.total_quantity),
      'previous_vs_target', fn_ratio(v_prev.total_quantity, v_tgt.total_quantity)
    ),
    'coverage', jsonb_build_object(
      'current', v_cur.coverage,
      'target', v_tgt.coverage,
      'previous', v_prev.coverage,
      'current_vs_target', fn_ratio(v_cur.coverage::numeric, v_tgt.coverage::numeric),
      'previous_vs_target', fn_ratio(v_prev.coverage::numeric, v_tgt.coverage::numeric)
    ),
    'avg_ticket', jsonb_build_object(
      'current', v_cur_ticket,
      'target', v_tgt_ticket,
      'previous', v_prev_ticket,
      'current_vs_target', fn_ratio(v_cur_ticket, v_tgt_ticket),
      'previous_vs_target', fn_ratio(v_prev_ticket, v_tgt_ticket)
    ),
    'drop_size', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_quantity, v_cur.invoice_count::numeric),
      'target', fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric),
      'previous', fn_safe_div(v_prev.total_quantity, v_prev.invoice_count::numeric),
      'current_vs_target', fn_ratio(
        fn_safe_div(v_cur.total_quantity, v_cur.invoice_count::numeric),
        fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric)),
      'previous_vs_target', fn_ratio(
        fn_safe_div(v_prev.total_quantity, v_prev.invoice_count::numeric),
        fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric))
    ),
    'avg_price', jsonb_build_object(
      'current', v_cur_avg_price,
      'target', v_tgt_avg_price,
      'previous', v_prev_avg_price,
      'current_vs_target', fn_ratio(v_cur_avg_price, v_tgt_avg_price),
      'previous_vs_target', fn_ratio(v_prev_avg_price, v_tgt_avg_price)
    ),
    'markup_pct', jsonb_build_object(
      'current', fn_ratio(v_cur_avg_price, v_cur_sell_in_price),
      'previous', fn_ratio(v_prev_avg_price, v_prev_sell_in_price)
    ),
    'margin_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur_avg_price - v_cur_sell_in_price, v_cur_avg_price),
      'previous', fn_safe_div(v_prev_avg_price - v_prev_sell_in_price, v_prev_avg_price)
    ),
    'avg_turnover', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value, v_cur.total_value - v_cur_si.total_value),
      'previous', fn_safe_div(v_prev.total_value, v_prev.total_value - v_prev_si.total_value)
    ),
    'avg_coverage', jsonb_build_object(
      'current', fn_safe_div(v_cur_si.total_quantity - v_cur.total_quantity, v_cur.total_quantity),
      'previous', fn_safe_div(v_prev_si.total_quantity - v_prev.total_quantity, v_prev.total_quantity)
    ),
    'trend_value', jsonb_build_object(
      'projected', v_projected_value,
      'projected_vs_target', fn_ratio(v_projected_value, v_tgt.total_value)
    ),
    'probability_value', coalesce(fn_safe_div(v_cur.total_value, v_tgt.total_value), 0),
    'probability_coverage', coalesce(fn_safe_div(v_cur.coverage::numeric, v_pdv_count::numeric), 0),
    'probability_ticket', coalesce(fn_safe_div(v_cur_ticket, v_tgt_ticket), 0),
    'period', jsonb_build_object(
      'total_days', v_total_days,
      'elapsed_days', v_elapsed_days,
      'pdv_count', v_pdv_count
    )
  );
end;
$$;

drop function if exists report_status_analysis(
  text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid
);

create function report_status_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null
)
returns table (
  group_id uuid,
  group_name text,
  current_value numeric,
  target_value numeric,
  current_vs_target numeric,
  previous_value numeric,
  previous_vs_target numeric,
  coverage bigint,
  avg_ticket numeric,
  drop_size numeric,
  avg_price numeric,
  markup_pct numeric,
  margin_pct numeric,
  avg_turnover numeric,
  avg_coverage numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_group_by not in ('seller', 'category', 'channel') then
    raise exception 'report_status_analysis: invalid p_group_by %', p_group_by;
  end if;

  return query
  with cur_base as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      so.distributor_id,
      so.product_id,
      so.customer_id,
      so.gross_value,
      so.quantity
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_current_start and p_current_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
  ),
  cur as (
    select
      gid,
      sum(gross_value) as v_value,
      sum(quantity) as v_quantity,
      count(distinct customer_id) as v_coverage,
      count(*)::bigint as v_invoices
    from cur_base
    group by 1
  ),
  si as (
    select
      scope.gid,
      sum(si.gross_value) as v_value,
      sum(si.quantity) as v_quantity
    from (
      select distinct gid, distributor_id, product_id
      from cur_base
      where gid is not null
    ) scope
    join sell_in si
      on si.distributor_id = scope.distributor_id
     and si.product_id = scope.product_id
    where si.invoice_date between p_current_start and p_current_end
    group by 1
  ),
  prev as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(so.gross_value) as v_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_previous_start and p_previous_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  tgt as (
    select
      case p_group_by
        when 'seller' then c.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(t.gross_value) as v_value
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = t.customer_id
    where t.target_date between coalesce(p_target_start, p_current_start)
      and coalesce(p_target_end, p_current_end)
      and t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or t.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  keys as (
    select cur.gid from cur
    union
    select prev.gid from prev
    union
    select tgt.gid from tgt
  ),
  calculated as (
    select
      k.gid,
      coalesce(sr.name, ph.name, ch.name, '—') as group_name,
      coalesce(cur.v_value, 0) as current_value,
      tgt.v_value as target_value,
      fn_ratio(coalesce(cur.v_value, 0), tgt.v_value) as current_vs_target,
      coalesce(prev.v_value, 0) as previous_value,
      fn_ratio(coalesce(prev.v_value, 0), tgt.v_value) as previous_vs_target,
      coalesce(cur.v_coverage, 0) as coverage,
      fn_safe_div(cur.v_value, cur.v_coverage::numeric) as avg_ticket,
      fn_safe_div(cur.v_quantity, cur.v_invoices::numeric) as drop_size,
      fn_safe_div(cur.v_value, cur.v_quantity) as avg_price,
      fn_safe_div(si.v_value, si.v_quantity) as sell_in_avg_price,
      fn_safe_div(cur.v_value, cur.v_value - si.v_value) as avg_turnover,
      fn_safe_div(si.v_quantity - cur.v_quantity, cur.v_quantity) as avg_coverage
    from keys k
    left join cur on cur.gid = k.gid
    left join si on si.gid = k.gid
    left join prev on prev.gid = k.gid
    left join tgt on tgt.gid = k.gid
    left join sales_reps sr on p_group_by = 'seller' and sr.id = k.gid
    left join product_hierarchy ph on p_group_by = 'category' and ph.id = k.gid
    left join channels ch on p_group_by = 'channel' and ch.id = k.gid
    where k.gid is not null
  )
  select
    c.gid,
    c.group_name,
    c.current_value,
    c.target_value,
    c.current_vs_target,
    c.previous_value,
    c.previous_vs_target,
    c.coverage,
    c.avg_ticket,
    c.drop_size,
    c.avg_price,
    fn_ratio(c.avg_price, c.sell_in_avg_price),
    fn_safe_div(c.avg_price - c.sell_in_avg_price, c.avg_price),
    c.avg_turnover,
    c.avg_coverage
  from calculated c
  order by 3 desc;
end;
$$;

revoke execute on function fn_sell_out_metrics(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke execute on function fn_sell_in_metrics_for_sell_out_filter(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke execute on function fn_customer_count(uuid, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  from public, anon;
revoke execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  from public, anon;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  to authenticated;
grant execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  to authenticated;
