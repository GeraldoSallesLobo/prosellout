-- Report RPCs consumed by the frontend (PostgREST /rpc/*).
--
-- KPI definitions (mirroring the Excel workbook):
--   sell_out_value   = sum(gross_value)
--   sell_out_quantity= sum(quantity)
--   coverage         = count(distinct customer_id)         -- "Cobertura"
--   avg_ticket       = sell_out_value / coverage           -- "Ticket Médio"
--   drop_size        = sell_out_quantity / invoice_count
--   avg_price        = sell_out_value / sell_out_quantity  -- "Preço Médio"
--   markup_pct       = (value - cost) / cost
--   margin_pct       = (value - cost) / value
--   trend            = linear run-rate projection to the end of the period
--   probability_*    = min(1, projected / target)

create or replace function fn_safe_div(p_numerator numeric, p_denominator numeric)
returns numeric
language sql
immutable
as $$
  select case when p_denominator is null or p_denominator = 0
    then null
    else p_numerator / p_denominator
  end
$$;

-- Relative variation: actual vs reference (0.05 = +5%).
create or replace function fn_ratio(p_actual numeric, p_reference numeric)
returns numeric
language sql
immutable
as $$
  select fn_safe_div(p_actual, p_reference) - 1
$$;

-- ---------------------------------------------------------------------------
-- Core period metrics (single row) for a filter combination.
-- ---------------------------------------------------------------------------
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
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  left join sales_reps sr on sr.id = so.sales_rep_id
  where so.invoice_date between p_start and p_end
    and (p_distributor_id is null or so.distributor_id = p_distributor_id)
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
    count(distinct t.customer_id)
  from sales_targets t
  join products p on p.id = t.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = t.customer_id
  left join sales_reps sr on sr.id = c.sales_rep_id
  where t.target_date between p_start and p_end
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or t.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or c.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

-- ---------------------------------------------------------------------------
-- Status MTD: the 12 KPI cards.
-- ---------------------------------------------------------------------------
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
  v_total_days integer;
  v_elapsed_days integer;
  v_projected_value numeric;
  v_projected_quantity numeric;
  v_projected_coverage numeric;
  v_cur_ticket numeric;
  v_prev_ticket numeric;
  v_tgt_ticket numeric;
begin
  select * into v_cur from fn_sell_out_metrics(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev from fn_sell_out_metrics(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_tgt from fn_target_metrics(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_macro_category_id, p_category_id, p_subcategory_id, p_product_id,
    p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  v_total_days := p_current_end - p_current_start + 1;
  v_elapsed_days := greatest(1, least(current_date, p_current_end) - p_current_start + 1);

  v_projected_value := fn_safe_div(v_cur.total_value, v_elapsed_days) * v_total_days;
  v_projected_quantity := fn_safe_div(v_cur.total_quantity, v_elapsed_days) * v_total_days;
  v_projected_coverage := fn_safe_div(v_cur.coverage::numeric, v_elapsed_days) * v_total_days;

  v_cur_ticket := fn_safe_div(v_cur.total_value, v_cur.coverage::numeric);
  v_prev_ticket := fn_safe_div(v_prev.total_value, v_prev.coverage::numeric);
  v_tgt_ticket := fn_safe_div(v_tgt.total_value, v_tgt.coverage::numeric);

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
      'current', fn_safe_div(v_cur.total_value, v_cur.total_quantity),
      'target', fn_safe_div(v_tgt.total_value, v_tgt.total_quantity),
      'previous', fn_safe_div(v_prev.total_value, v_prev.total_quantity),
      'current_vs_target', fn_ratio(
        fn_safe_div(v_cur.total_value, v_cur.total_quantity),
        fn_safe_div(v_tgt.total_value, v_tgt.total_quantity)),
      'previous_vs_target', fn_ratio(
        fn_safe_div(v_prev.total_value, v_prev.total_quantity),
        fn_safe_div(v_tgt.total_value, v_tgt.total_quantity))
    ),
    'markup_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value - v_cur.total_cost, v_cur.total_cost),
      'previous', fn_safe_div(v_prev.total_value - v_prev.total_cost, v_prev.total_cost)
    ),
    'margin_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value - v_cur.total_cost, v_cur.total_value),
      'previous', fn_safe_div(v_prev.total_value - v_prev.total_cost, v_prev.total_value)
    ),
    'trend_value', jsonb_build_object(
      'projected', v_projected_value,
      'projected_vs_target', fn_ratio(v_projected_value, v_tgt.total_value)
    ),
    'probability_value', least(1, coalesce(fn_safe_div(v_projected_value, v_tgt.total_value), 0)),
    'probability_coverage', least(1, coalesce(fn_safe_div(v_projected_coverage, v_tgt.coverage::numeric), 0)),
    'probability_ticket', least(1, coalesce(fn_safe_div(v_cur_ticket, v_tgt_ticket), 0)),
    'period', jsonb_build_object(
      'total_days', v_total_days,
      'elapsed_days', v_elapsed_days
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Status analysis table with toggle: seller | category | channel.
-- ---------------------------------------------------------------------------
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
  margin_pct numeric
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
  with cur as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(so.gross_value) as v_value,
      sum(so.quantity) as v_quantity,
      sum(so.quantity * coalesce(so.unit_cost, 0)) as v_cost,
      count(distinct so.customer_id) as v_coverage,
      count(distinct so.invoice_number) as v_invoices
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_current_start and p_current_end
      and (p_distributor_id is null or so.distributor_id = p_distributor_id)
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
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
      and (p_distributor_id is null or so.distributor_id = p_distributor_id)
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
  )
  select
    k.gid,
    coalesce(sr.name, ph.name, ch.name, '—'),
    coalesce(cur.v_value, 0),
    tgt.v_value,
    fn_ratio(coalesce(cur.v_value, 0), tgt.v_value),
    coalesce(prev.v_value, 0),
    fn_ratio(coalesce(prev.v_value, 0), tgt.v_value),
    coalesce(cur.v_coverage, 0),
    fn_safe_div(cur.v_value, cur.v_coverage::numeric),
    fn_safe_div(cur.v_quantity, cur.v_invoices::numeric),
    fn_safe_div(cur.v_value, cur.v_quantity),
    fn_safe_div(cur.v_value - cur.v_cost, cur.v_cost),
    fn_safe_div(cur.v_value - cur.v_cost, cur.v_value)
  from keys k
  left join cur on cur.gid = k.gid
  left join prev on prev.gid = k.gid
  left join tgt on tgt.gid = k.gid
  left join sales_reps sr on p_group_by = 'seller' and sr.id = k.gid
  left join product_hierarchy ph on p_group_by = 'category' and ph.id = k.gid
  left join channels ch on p_group_by = 'channel' and ch.id = k.gid
  where k.gid is not null
  order by 3 desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Weekly evolution buckets (monthly analysis charts).
-- ---------------------------------------------------------------------------
create or replace function report_evolution_weekly(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
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
    and (p_distributor_id is null or so.distributor_id = p_distributor_id)
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  group by 1
  order by 1
$$;

-- ---------------------------------------------------------------------------
-- Three-month history cards (M-2, M-1, current month).
-- ---------------------------------------------------------------------------
create or replace function report_three_month_history(
  p_reference_month date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null
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
    and (p_distributor_id is null or so.distributor_id = p_distributor_id)
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
  group by 1
  order by 1
$$;

-- ---------------------------------------------------------------------------
-- Evolution analysis with toggle: category | channel | customer.
-- Compares current vs previous period per group.
-- ---------------------------------------------------------------------------
create or replace function report_evolution_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
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
      and (p_distributor_id is null or so.distributor_id = p_distributor_id)
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
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
    coalesce(ph.name, ch.name, cust.legal_name, '—'),
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

-- ---------------------------------------------------------------------------
-- Fast facts: per dimension, how many groups achieved the target, best and
-- worst performers and average probability of hitting the target.
-- ---------------------------------------------------------------------------
create or replace function fn_fast_facts_dimension(
  p_dimension text,
  p_current_start date,
  p_current_end date,
  p_target_start date,
  p_target_end date,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total_days integer := p_current_end - p_current_start + 1;
  v_elapsed_days integer := greatest(1, least(current_date, p_current_end) - p_current_start + 1);
  v_result jsonb;
begin
  with cur as (
    select
      case p_dimension
        when 'seller' then so.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then so.product_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
        when 'customer' then so.customer_id
      end as gid,
      sum(so.gross_value) as v_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = so.customer_id
    left join sales_reps sr on sr.id = so.sales_rep_id
    where so.invoice_date between p_current_start and p_current_end
      and (p_distributor_id is null or so.distributor_id = p_distributor_id)
    group by 1
  ),
  tgt as (
    select
      case p_dimension
        when 'seller' then c.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then t.product_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
        when 'customer' then t.customer_id
      end as gid,
      sum(t.gross_value) as v_value
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = t.customer_id
    left join sales_reps sr on sr.id = c.sales_rep_id
    where t.target_date between p_target_start and p_target_end
    group by 1
  ),
  joined as (
    select
      tgt.gid,
      coalesce(cur.v_value, 0) as cur_value,
      tgt.v_value as tgt_value,
      fn_safe_div(coalesce(cur.v_value, 0), tgt.v_value) as achievement,
      least(1, coalesce(
        fn_safe_div(fn_safe_div(coalesce(cur.v_value, 0), v_elapsed_days) * v_total_days, tgt.v_value), 0
      )) as probability
    from tgt
    left join cur on cur.gid = tgt.gid
    where tgt.gid is not null and tgt.v_value > 0
  ),
  named as (
    select
      j.*,
      coalesce(sr.name, pr.name, ph.name, ch.name, cust.legal_name, '—') as group_name
    from joined j
    left join sales_reps sr on p_dimension in ('seller', 'supervisor') and sr.id = j.gid
    left join products pr on p_dimension = 'product' and pr.id = j.gid
    left join product_hierarchy ph on p_dimension = 'category' and ph.id = j.gid
    left join channels ch on p_dimension = 'channel' and ch.id = j.gid
    left join customers cust on p_dimension = 'customer' and cust.id = j.gid
  )
  select jsonb_build_object(
    'dimension', p_dimension,
    'eligible_count', count(*),
    'achieved_count', count(*) filter (where achievement >= 1),
    'achieved_pct', fn_safe_div(count(*) filter (where achievement >= 1), count(*)::numeric),
    'avg_probability', avg(probability),
    'best', (
      select jsonb_build_object('name', n.group_name, 'achievement', n.achievement)
      from named n order by n.achievement desc nulls last limit 1
    ),
    'worst', (
      select jsonb_build_object('name', n.group_name, 'achievement', n.achievement)
      from named n order by n.achievement asc nulls last limit 1
    )
  )
  into v_result
  from named;

  return coalesce(v_result, jsonb_build_object('dimension', p_dimension, 'eligible_count', 0));
end;
$$;

create or replace function report_fast_facts(
  p_current_start date,
  p_current_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_dimension text;
  v_result jsonb := '{}'::jsonb;
begin
  foreach v_dimension in array array['seller', 'supervisor', 'product', 'category', 'channel', 'customer']
  loop
    v_result := v_result || jsonb_build_object(
      v_dimension,
      fn_fast_facts_dimension(
        v_dimension, p_current_start, p_current_end,
        coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
        p_distributor_id
      )
    );
  end loop;

  return v_result;
end;
$$;
