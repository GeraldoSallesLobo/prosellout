-- Add multi-value report filters for category, subcategory, SKU, channel and
-- cluster. Existing scalar RPC signatures are kept for backward compatibility.

create or replace function fn_report_uuid_filter_has_values(p_values uuid[])
returns boolean
language sql
immutable
as $$
  select coalesce(cardinality(p_values), 0) > 0
$$;

create or replace function fn_report_uuid_filter_matches(p_value uuid, p_values uuid[])
returns boolean
language sql
immutable
as $$
  select not fn_report_uuid_filter_has_values(p_values) or p_value = any(p_values)
$$;

create or replace function fn_sell_out_metrics_filtered(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
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
    count(distinct so.customer_id) filter (
      where fn_report_uuid_filter_has_values(p_product_ids)
        or date_trunc('month', so.invoice_date)::date = date_trunc('month', p_start)::date
    ),
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
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_target_metrics_filtered(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric,
  coverage bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(t.gross_value), 0)::numeric,
    coalesce(sum(t.quantity), 0)::numeric,
    count(distinct t.customer_id) filter (
      where fn_report_uuid_filter_has_values(p_product_ids)
        or date_trunc('month', t.target_date)::date = date_trunc('month', p_start)::date
    )
  from sales_targets t
  join products p on p.id = t.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = t.customer_id
  left join sales_reps sr on sr.id = t.sales_rep_id
  where t.target_date between p_start and p_end
    and t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(t.product_id, p_product_ids)
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
    and (p_sales_rep_id is null or t.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_sell_in_metrics_for_sell_out_filter_filtered(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
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
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
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

create or replace function fn_sell_out_last_invoice_date_filtered(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select max(so.invoice_date)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  left join sales_reps sr on sr.id = so.sales_rep_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_customer_count_filtered(
  p_distributor_id uuid default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
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
  has_customer_dimension_filter boolean :=
    fn_report_uuid_filter_has_values(p_channel_ids)
    or fn_report_uuid_filter_has_values(p_cluster_ids);
begin
  if p_sales_rep_id is not null and not has_customer_dimension_filter then
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

  if p_supervisor_id is not null and not has_customer_dimension_filter then
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
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
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
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
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
  v_cur_drop_size numeric;
  v_prev_drop_size numeric;
  v_tgt_drop_size numeric;
  v_cur_avg_price numeric;
  v_prev_avg_price numeric;
  v_tgt_avg_price numeric;
  v_cur_sell_in_price numeric;
  v_prev_sell_in_price numeric;
  v_pdv_count bigint;
  v_last_current_invoice_date date;
begin
  select * into v_cur from fn_sell_out_metrics_filtered(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev from fn_sell_out_metrics_filtered(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_cur_si from fn_sell_in_metrics_for_sell_out_filter_filtered(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev_si from fn_sell_in_metrics_for_sell_out_filter_filtered(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_tgt from fn_target_metrics_filtered(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_distributor_id, p_macro_category_id, p_category_ids, p_subcategory_ids,
    p_product_ids, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

  select fn_sell_out_last_invoice_date_filtered(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id)
  into v_last_current_invoice_date;

  v_total_days := p_current_end - p_current_start + 1;
  v_elapsed_days := greatest(
    1,
    least(coalesce(v_last_current_invoice_date, current_date), p_current_end) - p_current_start + 1
  );
  v_projected_value := fn_safe_div(v_cur.total_value, v_elapsed_days) * v_total_days;

  v_cur_ticket := fn_safe_div(v_cur.total_value, v_cur.coverage::numeric);
  v_prev_ticket := fn_safe_div(v_prev.total_value, v_prev.coverage::numeric);
  v_tgt_ticket := fn_safe_div(v_tgt.total_value, v_tgt.coverage::numeric);

  v_cur_drop_size := fn_safe_div(v_cur.total_quantity, v_cur.coverage::numeric);
  v_prev_drop_size := fn_safe_div(v_prev.total_quantity, v_prev.coverage::numeric);
  v_tgt_drop_size := fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric);

  v_cur_avg_price := fn_safe_div(v_cur.total_value, v_cur.total_quantity);
  v_prev_avg_price := fn_safe_div(v_prev.total_value, v_prev.total_quantity);
  v_tgt_avg_price := fn_safe_div(v_tgt.total_value, v_tgt.total_quantity);
  v_cur_sell_in_price := fn_safe_div(v_cur_si.total_value, v_cur_si.total_quantity);
  v_prev_sell_in_price := fn_safe_div(v_prev_si.total_value, v_prev_si.total_quantity);

  v_pdv_count := fn_customer_count_filtered(
    p_distributor_id, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

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
      'current', v_cur_drop_size,
      'target', v_tgt_drop_size,
      'previous', v_prev_drop_size,
      'current_vs_target', fn_ratio(v_cur_drop_size, v_tgt_drop_size),
      'previous_vs_target', fn_ratio(v_prev_drop_size, v_tgt_drop_size)
    ),
    'avg_price', jsonb_build_object(
      'current', v_cur_avg_price,
      'target', v_tgt_avg_price,
      'previous', v_prev_avg_price,
      'current_vs_target', fn_ratio(v_cur_avg_price, v_tgt_avg_price),
      'previous_vs_target', fn_ratio(v_prev_avg_price, v_tgt_avg_price)
    ),
    'markup_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur_avg_price, v_cur_sell_in_price) - 1,
      'previous', fn_safe_div(v_prev_avg_price, v_prev_sell_in_price) - 1
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
    'probability_value', fn_capped_probability(v_cur.total_value, v_tgt.total_value),
    'probability_coverage', fn_capped_probability(v_cur.coverage::numeric, v_tgt.coverage::numeric),
    'probability_ticket', fn_capped_probability(v_cur_ticket, v_tgt_ticket),
    'period', jsonb_build_object(
      'total_days', v_total_days,
      'elapsed_days', v_elapsed_days,
      'pdv_count', v_pdv_count
    )
  );
end;
$$;

create or replace function report_status_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null
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
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
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
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
    group by 1
  ),
  tgt as (
    select
      case p_group_by
        when 'seller' then t.sales_rep_id
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
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(t.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
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
      fn_safe_div(cur.v_quantity, cur.v_coverage::numeric) as drop_size,
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
    fn_safe_div(c.avg_price, c.sell_in_avg_price) - 1,
    fn_safe_div(c.avg_price - c.sell_in_avg_price, c.avg_price),
    c.avg_turnover,
    c.avg_coverage
  from calculated c
  order by 3 desc;
end;
$$;

create or replace function report_evolution_weekly(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null
)
returns table (
  bucket_start date,
  total_value numeric,
  total_quantity numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    date_trunc('week', so.invoice_date)::date,
    sum(so.gross_value)::numeric,
    sum(so.quantity)::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  group by 1
  order by 1
$$;

create or replace function report_three_month_history(
  p_reference_month date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null
)
returns table (
  month_start date,
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
    date_trunc('month', so.invoice_date)::date,
    sum(so.gross_value)::numeric,
    sum(so.quantity)::numeric,
    sum(so.quantity * coalesce(so.unit_cost, 0))::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  where so.invoice_date >= (date_trunc('month', p_reference_month) - interval '2 months')::date
    and so.invoice_date < (date_trunc('month', p_reference_month) + interval '1 month')::date
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
  group by 1
  order by 1
$$;

create or replace function report_evolution_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null
)
returns table (
  group_id uuid,
  group_name text,
  current_value numeric,
  previous_value numeric,
  value_change_pct numeric,
  current_quantity numeric,
  previous_quantity numeric,
  quantity_change_pct numeric,
  current_ticket numeric,
  previous_ticket numeric,
  ticket_change_pct numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_group_by not in ('category', 'channel', 'customer') then
    raise exception 'report_evolution_analysis: invalid p_group_by %', p_group_by;
  end if;

  perform assert_authorized_distributor_scope(p_distributor_id);

  return query
  with base as (
    select
      case p_group_by
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
        when 'customer' then so.customer_id
      end as gid,
      so.invoice_date between p_current_start and p_current_end as is_current,
      so.gross_value,
      so.quantity,
      so.customer_id,
      so.invoice_number
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where (
        so.invoice_date between p_current_start and p_current_end
        or so.invoice_date between p_previous_start and p_previous_end
      )
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
      and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  ),
  grouped as (
    select
      b.gid,
      sum(b.gross_value) filter (where b.is_current) as cur_value,
      sum(b.gross_value) filter (where not b.is_current) as prev_value,
      sum(b.quantity) filter (where b.is_current) as cur_quantity,
      sum(b.quantity) filter (where not b.is_current) as prev_quantity,
      count(distinct b.customer_id) filter (where b.is_current) as cur_coverage,
      count(distinct b.customer_id) filter (where not b.is_current) as prev_coverage,
      count(distinct b.invoice_number) filter (where b.is_current) as cur_invoices,
      count(distinct b.invoice_number) filter (where not b.is_current) as prev_invoices
    from base b
    where b.gid is not null
    group by b.gid
  )
  select
    g.gid,
    coalesce(ph.name, ch.name, cust.legal_name, '-'),
    coalesce(g.cur_value, 0),
    coalesce(g.prev_value, 0),
    fn_ratio(coalesce(g.cur_value, 0), g.prev_value),
    coalesce(g.cur_quantity, 0),
    coalesce(g.prev_quantity, 0),
    fn_ratio(coalesce(g.cur_quantity, 0), g.prev_quantity),
    case when p_group_by = 'customer'
      then fn_safe_div(g.cur_value, g.cur_invoices::numeric)
      else fn_safe_div(g.cur_value, g.cur_coverage::numeric)
    end,
    case when p_group_by = 'customer'
      then fn_safe_div(g.prev_value, g.prev_invoices::numeric)
      else fn_safe_div(g.prev_value, g.prev_coverage::numeric)
    end,
    case when p_group_by = 'customer'
      then fn_ratio(fn_safe_div(g.cur_value, g.cur_invoices::numeric), fn_safe_div(g.prev_value, g.prev_invoices::numeric))
      else fn_ratio(fn_safe_div(g.cur_value, g.cur_coverage::numeric), fn_safe_div(g.prev_value, g.prev_coverage::numeric))
    end
  from grouped g
  left join product_hierarchy ph on p_group_by = 'category' and ph.id = g.gid
  left join channels ch on p_group_by = 'channel' and ch.id = g.gid
  left join customers cust on p_group_by = 'customer' and cust.id = g.gid
  order by 3 desc;
end;
$$;

revoke execute on function fn_report_uuid_filter_has_values(uuid[]) from public, anon, authenticated;
revoke execute on function fn_report_uuid_filter_matches(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function fn_sell_out_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_target_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_sell_in_metrics_for_sell_out_filter_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_sell_out_last_invoice_date_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_customer_count_filtered(uuid, uuid[], uuid[], uuid, uuid) from public, anon, authenticated;

revoke execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid) from public, anon;
revoke execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[]) from public, anon;
revoke execute on function report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid) from public, anon;
revoke execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[]) from public, anon;
revoke execute on function report_evolution_analysis(text, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid) from public, anon;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid) to authenticated;
grant execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[]) to authenticated;
grant execute on function report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid) to authenticated;
grant execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[]) to authenticated;
grant execute on function report_evolution_analysis(text, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid) to authenticated;
