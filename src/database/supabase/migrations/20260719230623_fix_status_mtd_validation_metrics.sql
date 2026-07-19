-- Align Status MTD with the 2026-07-19 validation document:
-- - Drop Size = Sell Out volume / Coverage.
-- - Product-level coverage uses distinct PDVs across the selected range.
-- - Coverage probability compares realized coverage against target coverage and
--   all probability gauges are capped at 100%.

create or replace function fn_capped_probability(p_actual numeric, p_target numeric)
returns numeric
language sql
immutable
as $$
  select case
    when fn_safe_div(p_actual, p_target) is null then 0
    else least(1, greatest(0, fn_safe_div(p_actual, p_target)))
  end
$$;

revoke execute on function fn_capped_probability(numeric, numeric) from public, anon, authenticated;

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
    count(distinct so.customer_id) filter (
      where p_product_id is not null
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
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_target_metrics(
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
      where p_product_id is not null
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
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or t.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or t.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
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

  select fn_sell_out_last_invoice_date(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
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
    fn_ratio(c.avg_price, c.sell_in_avg_price),
    fn_safe_div(c.avg_price - c.sell_in_avg_price, c.avg_price),
    c.avg_turnover,
    c.avg_coverage
  from calculated c
  order by 3 desc;
end;
$$;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  to authenticated;
grant execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  to authenticated;
