-- Align Giro Médio, Cobertura Média and Drop Size with the 13/08/2026 calculation memo:
--   avg_turnover = stock volume / sell out volume (the formula formerly used by avg_coverage)
--   avg_coverage = stock volume / inclusive day count of each period
--   drop_size    = sell out value / order count, attributed by invoice_date only
-- Stock volume keeps the existing concept: sell in volume - sell out volume of the period.
-- The row-count column is renamed from invoice_count to order_count because each eligible
-- row counts as one order/delivery — the ETL synthesizes invoice numbers per row, so the
-- denominator must never deduplicate by invoice_number.

-- Changing a function's OUT columns requires drop + recreate (create or replace fails).
drop function if exists fn_sell_out_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid);
drop function if exists fn_target_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid);
drop function if exists report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid);
drop function if exists report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[]);

-- Stale single-value-filter overloads left behind when multi-select filters
-- (uuid[] params, migration 20260720161320) replaced them. They still carry the
-- superseded formulas and make positional calls ambiguous; no client uses them
-- (the frontend calls by named uuid[] params).
drop function if exists report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid);
drop function if exists report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid);
drop function if exists report_evolution_weekly(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid);
drop function if exists report_three_month_history(date, uuid, uuid, uuid, uuid, uuid, uuid, uuid);

create function fn_sell_out_metrics_filtered(
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
  order_count bigint
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
    and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create function fn_target_metrics_filtered(
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
  coverage bigint,
  order_count bigint
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
    ),
    count(*)::bigint
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
    and fn_report_uuid_filter_matches(coalesce(t.channel_id, c.channel_id), p_channel_ids)
    and fn_report_uuid_filter_matches(coalesce(t.cluster_id, c.cluster_id), p_cluster_ids)
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
  v_tgt_si record;
  v_trend_tgt_to_date record;
  v_trend_tgt_full_month record;
  v_total_days integer;
  v_elapsed_days integer;
  v_previous_days integer;
  v_target_days integer;
  v_projected_value numeric;
  v_projected_reference_value numeric;
  v_target_month_start date;
  v_target_month_end date;
  v_target_elapsed_end date;
  v_is_current_end_month_end boolean;
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
  v_tgt_sell_in_price numeric;
  v_cur_markup numeric;
  v_prev_markup numeric;
  v_tgt_markup numeric;
  v_cur_margin numeric;
  v_prev_margin numeric;
  v_tgt_margin numeric;
  v_cur_stock_volume numeric;
  v_prev_stock_volume numeric;
  v_tgt_stock_volume numeric;
  v_cur_turnover numeric;
  v_prev_turnover numeric;
  v_tgt_turnover numeric;
  v_cur_avg_coverage numeric;
  v_prev_avg_coverage numeric;
  v_tgt_avg_coverage numeric;
  v_pdv_count bigint;
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

  select * into v_tgt_si from fn_sell_in_target_metrics_filtered(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_distributor_id, p_macro_category_id, p_category_ids, p_subcategory_ids,
    p_product_ids, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

  v_total_days := p_current_end - p_current_start + 1;
  v_elapsed_days := greatest(1, v_total_days);
  v_previous_days := p_previous_end - p_previous_start + 1;
  v_target_days := coalesce(p_target_end, p_current_end) - coalesce(p_target_start, p_current_start) + 1;
  v_is_current_end_month_end :=
    p_current_end = (date_trunc('month', p_current_end) + interval '1 month - 1 day')::date;

  if v_is_current_end_month_end then
    v_projected_value := v_cur.total_value;
    v_projected_reference_value := v_tgt.total_value;
  else
    v_target_month_start := date_trunc('month', coalesce(p_target_start, p_current_start))::date;
    v_target_month_end := (v_target_month_start + interval '1 month - 1 day')::date;
    v_target_elapsed_end := least(
      v_target_month_start + (p_current_end - date_trunc('month', p_current_end)::date),
      v_target_month_end
    );

    select * into v_trend_tgt_to_date from fn_target_metrics_filtered(
      v_target_month_start, v_target_elapsed_end,
      p_distributor_id, p_macro_category_id, p_category_ids, p_subcategory_ids,
      p_product_ids, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

    select * into v_trend_tgt_full_month from fn_target_metrics_filtered(
      v_target_month_start, v_target_month_end,
      p_distributor_id, p_macro_category_id, p_category_ids, p_subcategory_ids,
      p_product_ids, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

    v_projected_value :=
      fn_safe_div(v_cur.total_value, v_trend_tgt_to_date.total_value)
      * v_trend_tgt_full_month.total_value;
    v_projected_reference_value := v_trend_tgt_full_month.total_value;
  end if;

  v_cur_ticket := fn_safe_div(v_cur.total_value, v_cur.coverage::numeric);
  v_prev_ticket := fn_safe_div(v_prev.total_value, v_prev.coverage::numeric);
  v_tgt_ticket := fn_safe_div(v_tgt.total_value, v_tgt.coverage::numeric);

  v_cur_drop_size := fn_safe_div(v_cur.total_value, v_cur.order_count::numeric);
  v_prev_drop_size := fn_safe_div(v_prev.total_value, v_prev.order_count::numeric);
  v_tgt_drop_size := fn_safe_div(v_tgt.total_value, v_tgt.order_count::numeric);

  v_cur_avg_price := fn_safe_div(v_cur.total_value, v_cur.total_quantity);
  v_prev_avg_price := fn_safe_div(v_prev.total_value, v_prev.total_quantity);
  v_tgt_avg_price := fn_safe_div(v_tgt.total_value, v_tgt.total_quantity);
  v_cur_sell_in_price := fn_safe_div(v_cur_si.total_value, v_cur_si.total_quantity);
  v_prev_sell_in_price := fn_safe_div(v_prev_si.total_value, v_prev_si.total_quantity);
  v_tgt_sell_in_price := fn_safe_div(v_tgt_si.total_value, v_tgt_si.total_quantity);

  v_cur_markup := fn_safe_div(v_cur_avg_price, v_cur_sell_in_price) - 1;
  v_prev_markup := fn_safe_div(v_prev_avg_price, v_prev_sell_in_price) - 1;
  v_tgt_markup := fn_safe_div(v_tgt_avg_price, v_tgt_sell_in_price) - 1;
  v_cur_margin := fn_safe_div(v_cur_avg_price - v_cur_sell_in_price, v_cur_avg_price);
  v_prev_margin := fn_safe_div(v_prev_avg_price - v_prev_sell_in_price, v_prev_avg_price);
  v_tgt_margin := fn_safe_div(v_tgt_avg_price - v_tgt_sell_in_price, v_tgt_avg_price);

  v_cur_stock_volume := v_cur_si.total_quantity - v_cur.total_quantity;
  v_prev_stock_volume := v_prev_si.total_quantity - v_prev.total_quantity;
  v_tgt_stock_volume := v_tgt_si.total_quantity - v_tgt.total_quantity;

  v_cur_turnover := fn_safe_div(v_cur_stock_volume, v_cur.total_quantity);
  v_prev_turnover := fn_safe_div(v_prev_stock_volume, v_prev.total_quantity);
  v_tgt_turnover := fn_safe_div(v_tgt_stock_volume, v_tgt.total_quantity);

  v_cur_avg_coverage := fn_safe_div(v_cur_stock_volume, v_total_days::numeric);
  v_prev_avg_coverage := fn_safe_div(v_prev_stock_volume, v_previous_days::numeric);
  v_tgt_avg_coverage := fn_safe_div(v_tgt_stock_volume, v_target_days::numeric);

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
      'current', v_cur_markup,
      'target', v_tgt_markup,
      'previous', v_prev_markup,
      'current_vs_target', fn_ratio(v_cur_markup, v_tgt_markup),
      'previous_vs_target', fn_ratio(v_prev_markup, v_tgt_markup)
    ),
    'margin_pct', jsonb_build_object(
      'current', v_cur_margin,
      'target', v_tgt_margin,
      'previous', v_prev_margin,
      'current_vs_target', fn_ratio(v_cur_margin, v_tgt_margin),
      'previous_vs_target', fn_ratio(v_prev_margin, v_tgt_margin)
    ),
    'avg_turnover', jsonb_build_object(
      'current', v_cur_turnover,
      'target', v_tgt_turnover,
      'previous', v_prev_turnover,
      'current_vs_target', fn_ratio(v_cur_turnover, v_tgt_turnover),
      'previous_vs_target', fn_ratio(v_prev_turnover, v_tgt_turnover)
    ),
    'avg_coverage', jsonb_build_object(
      'current', v_cur_avg_coverage,
      'target', v_tgt_avg_coverage,
      'previous', v_prev_avg_coverage,
      'current_vs_target', fn_ratio(v_cur_avg_coverage, v_tgt_avg_coverage),
      'previous_vs_target', fn_ratio(v_prev_avg_coverage, v_tgt_avg_coverage)
    ),
    'trend_value', jsonb_build_object(
      'projected', v_projected_value,
      'projected_vs_target', fn_ratio(v_projected_value, v_projected_reference_value)
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
declare
  v_current_days numeric;
begin
  if p_group_by not in ('seller', 'category', 'channel') then
    raise exception 'report_status_analysis: invalid p_group_by %', p_group_by;
  end if;

  v_current_days := (p_current_end - p_current_start + 1)::numeric;

  return query
  with cur_base as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then coalesce(so.channel_id, c.channel_id)
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
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
      and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
  ),
  cur as (
    select
      gid,
      sum(gross_value) as v_value,
      sum(quantity) as v_quantity,
      count(distinct customer_id) as v_coverage,
      count(*)::bigint as v_order_count
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
        when 'channel' then coalesce(so.channel_id, c.channel_id)
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
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
      and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
    group by 1
  ),
  tgt as (
    select
      case p_group_by
        when 'seller' then t.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then coalesce(t.channel_id, c.channel_id)
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
      and fn_report_uuid_filter_matches(coalesce(t.channel_id, c.channel_id), p_channel_ids)
      and fn_report_uuid_filter_matches(coalesce(t.cluster_id, c.cluster_id), p_cluster_ids)
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
      fn_safe_div(cur.v_value, cur.v_order_count::numeric) as drop_size,
      fn_safe_div(cur.v_value, cur.v_quantity) as avg_price,
      fn_safe_div(si.v_value, si.v_quantity) as sell_in_avg_price,
      fn_safe_div(si.v_quantity - cur.v_quantity, cur.v_quantity) as avg_turnover,
      fn_safe_div(si.v_quantity - cur.v_quantity, v_current_days) as avg_coverage
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

create function report_evolution_weekly(
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
  order_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (date_trunc('week', so.invoice_date + interval '1 day') - interval '1 day')::date,
    sum(so.gross_value)::numeric,
    sum(so.quantity)::numeric,
    count(distinct so.customer_id),
    count(*)::bigint
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
    and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  group by 1
  order by 1
$$;

create function report_three_month_history(
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
  order_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with months as (
    select generate_series(
      (date_trunc('month', p_reference_month) - interval '2 months')::date,
      date_trunc('month', p_reference_month)::date,
      interval '1 month'
    )::date as month_start
  ),
  filtered_sell_out as (
    select so.*
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
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
      and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
  ),
  sell_out_months as (
    select
      date_trunc('month', so.invoice_date)::date as month_start,
      sum(so.gross_value)::numeric as total_value,
      sum(so.quantity)::numeric as total_quantity,
      count(distinct so.customer_id)::bigint as coverage,
      count(*)::bigint as order_count
    from filtered_sell_out so
    group by 1
  ),
  sell_in_months as (
    select
      m.month_start,
      si.total_value,
      si.total_quantity
    from months m
    cross join lateral fn_sell_in_metrics_for_sell_out_filter_filtered(
      m.month_start,
      (m.month_start + interval '1 month - 1 day')::date,
      p_distributor_id,
      p_macro_category_id,
      p_category_ids,
      p_subcategory_ids,
      p_product_ids,
      p_channel_ids,
      p_cluster_ids,
      null,
      null
    ) si
  )
  select
    m.month_start,
    coalesce(so.total_value, 0)::numeric,
    coalesce(so.total_quantity, 0)::numeric,
    case
      when coalesce(si.total_quantity, 0) = 0 then null
      else coalesce(so.total_quantity, 0) * (si.total_value / nullif(si.total_quantity, 0))
    end::numeric,
    coalesce(so.coverage, 0)::bigint,
    coalesce(so.order_count, 0)::bigint
  from months m
  left join sell_out_months so using (month_start)
  left join sell_in_months si using (month_start)
  order by m.month_start
$$;

revoke execute on function fn_sell_out_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  from public, anon, authenticated;
revoke execute on function fn_target_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  from public, anon, authenticated;

revoke execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  from public, anon;
revoke execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  from public, anon;
revoke execute on function report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid)
  from public, anon;
revoke execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  from public, anon;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  to authenticated;
grant execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  to authenticated;
grant execute on function report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid)
  to authenticated;
grant execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  to authenticated;
