-- Planner module, part 2: planner_* RPCs.
-- Spec: docs/PLANNER_SPEC.md (section 14 has the algorithm details).
--
-- Reads follow the report_* conventions (security definer + stable + tenancy
-- via authorized_distributor_ids). Generation functions are volatile and are
-- the only write path into planner_plans/planner_plan_lines.
--
-- Error codes raised for the frontend: NO_ROUTE_PLAN, NO_TARGETS_FOR_MONTH,
-- INVALID_WEEKS, INVALID_MODE, INVALID_TARGET, INVALID_MARGIN, INVALID_PERIOD,
-- NO_REFERENCE_SALES, NO_UNCOVERED_CUSTOMERS, NO_COST_DATA,
-- NO_CUSTOMERS_BELOW_MARGIN, PLAN_NOT_FOUND, PLAN_ALREADY_REPLACED,
-- PLAN_NOT_WEEKLY, NO_CLOSED_WEEKS, NO_REMAINING_WEEKS.

-- Monday of the requested ISO week. Used to find "the same week of the
-- previous year": January 4th always belongs to ISO week 1.
create or replace function fn_planner_iso_week_start(p_iso_year integer, p_iso_week integer)
returns date
language sql
immutable
as $$
  select (date_trunc('week', make_date(p_iso_year, 1, 4)::timestamp)::date
          + (p_iso_week - 1) * 7)
$$;

-- Parses and validates the p_weeks jsonb contract:
-- [{"week_number": 1, "start_date": "2026-09-01", "end_date": "2026-09-05"}, ...]
create or replace function fn_planner_parse_weeks(p_weeks jsonb)
returns table (week_number smallint, start_date date, end_date date)
language plpgsql
immutable
as $$
declare
  v_count integer;
  v_distinct integer;
begin
  if p_weeks is null or jsonb_typeof(p_weeks) <> 'array' then
    raise exception 'INVALID_WEEKS';
  end if;

  select count(*), count(distinct (elem->>'week_number'))
  into v_count, v_distinct
  from jsonb_array_elements(p_weeks) elem;

  if v_count = 0 or v_count > 5 or v_distinct <> v_count then
    raise exception 'INVALID_WEEKS';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_weeks) elem
    where coalesce((elem->>'week_number')::integer, 0) not between 1 and 5
      or (elem->>'start_date')::date is null
      or (elem->>'end_date')::date is null
      or (elem->>'start_date')::date > (elem->>'end_date')::date
  ) then
    raise exception 'INVALID_WEEKS';
  end if;

  -- Overlapping ranges would count the same daily targets twice.
  if exists (
    select 1
    from jsonb_array_elements(p_weeks) a
    join jsonb_array_elements(p_weeks) b
      on (a->>'week_number') < (b->>'week_number')
    where (a->>'start_date')::date <= (b->>'end_date')::date
      and (b->>'start_date')::date <= (a->>'end_date')::date
  ) then
    raise exception 'INVALID_WEEKS';
  end if;

  return query
  select
    (elem->>'week_number')::smallint,
    (elem->>'start_date')::date,
    (elem->>'end_date')::date
  from jsonb_array_elements(p_weeks) elem
  order by 1;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'INVALID_WEEKS';
end;
$$;

-- Sequential plan code per distributor (rendered as PLN-001 in the UI).
-- The advisory lock serializes concurrent generations for the same distributor.
create or replace function fn_planner_next_code(p_distributor_id uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_code integer;
begin
  perform pg_advisory_xact_lock(hashtext('planner_plans_code_' || p_distributor_id::text));

  select coalesce(max(code), 0) + 1
  into v_code
  from planner_plans
  where distributor_id = p_distributor_id;

  return v_code;
end;
$$;

-- Latest imported route plan for the distributor (the active one).
create or replace function fn_planner_active_route_plan(p_distributor_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select rp.id
  from planner_route_plans rp
  where rp.distributor_id = p_distributor_id
  order by rp.created_at desc, rp.id desc
  limit 1
$$;

-- Core weekly allocator shared by Automático, Batalha Naval and Recalcular
-- Rota. Distributes each SKU's weekly target volume across the customers
-- visited in each week, using one of three weight modes:
--   history      -> customer share of the SKU in the same ISO week of the
--                   previous year; customers without sales in that week fall
--                   back to their average monthly share over the 3 closed
--                   months before the target month (simple average, never the
--                   quarter sum). Mixed sources are re-normalized together.
--   volume_share -> customer share of the reference SKU's volume in the
--                   reference month (Batalha Naval Volume).
--   linear       -> equal weight across customers that bought the reference
--                   SKU in the reference month (Batalha Naval Positivação).
-- With p_use_remaining_balance the weekly targets are replaced by the month's
-- remaining balance (target minus realized so far) split across the given
-- weeks proportionally to their original targets (Recalcular Rota).
create or replace function fn_planner_weekly_allocations(
  p_distributor_id uuid,
  p_route_plan_id uuid,
  p_target_month date,
  p_weeks jsonb,
  p_weight_mode text,
  p_reference_month date default null,
  p_reference_product_id uuid default null,
  p_channel_ids uuid[] default null,
  p_use_remaining_balance boolean default false
)
returns table (
  week_number smallint,
  product_id uuid,
  customer_id uuid,
  sales_rep_id uuid,
  channel_id uuid,
  quantity numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with weeks as (
    select * from fn_planner_parse_weeks(p_weeks)
  ),
  month_bounds as (
    select
      date_trunc('month', p_target_month)::date as month_start,
      (date_trunc('month', p_target_month) + interval '1 month - 1 day')::date as month_end
  ),
  week_targets as (
    select w.week_number, t.product_id, sum(t.quantity) as target_quantity
    from weeks w
    join sales_targets t on t.target_date between w.start_date and w.end_date
    where t.distributor_id = p_distributor_id
    group by w.week_number, t.product_id
  ),
  product_balances as (
    select
      totals.product_id,
      greatest(totals.total_quantity - coalesce(realized.realized_quantity, 0), 0) as balance_quantity
    from (
      select t.product_id, sum(t.quantity) as total_quantity
      from sales_targets t
      cross join month_bounds mb
      where t.distributor_id = p_distributor_id
        and t.target_date between mb.month_start and mb.month_end
      group by t.product_id
    ) totals
    left join (
      select so.product_id, sum(so.quantity) as realized_quantity
      from sell_out so
      cross join month_bounds mb
      where so.distributor_id = p_distributor_id
        and so.invoice_date between mb.month_start and least(mb.month_end, current_date)
      group by so.product_id
    ) realized on realized.product_id = totals.product_id
    where p_use_remaining_balance
  ),
  remaining_totals as (
    select wt.product_id, sum(wt.target_quantity) as remaining_target
    from week_targets wt
    group by wt.product_id
  ),
  allocation_targets as (
    select wt.week_number, wt.product_id, wt.target_quantity
    from week_targets wt
    where not p_use_remaining_balance

    union all

    select
      w.week_number,
      pb.product_id,
      pb.balance_quantity * case
        when coalesce(rt.remaining_target, 0) > 0
          then coalesce(wt.target_quantity, 0) / rt.remaining_target
        else 1.0 / (select count(*)::numeric from weeks)
      end as target_quantity
    from product_balances pb
    cross join weeks w
    left join week_targets wt
      on wt.product_id = pb.product_id and wt.week_number = w.week_number
    left join remaining_totals rt on rt.product_id = pb.product_id
    where pb.balance_quantity > 0
  ),
  visits as (
    select v.week_number, v.customer_id, v.sales_rep_id
    from planner_route_visits v
    where v.route_plan_id = p_route_plan_id
      and v.week_number in (select w.week_number from weeks w)
  ),
  reference_weeks as (
    select
      w.week_number,
      fn_planner_iso_week_start(
        extract(isoyear from w.start_date)::integer - 1,
        extract(week from w.start_date)::integer
      ) as ref_start
    from weeks w
    where p_weight_mode = 'history'
  ),
  history_shares as (
    select
      rw.week_number,
      so.product_id,
      so.customer_id,
      sum(so.quantity) as customer_quantity,
      sum(sum(so.quantity)) over (partition by rw.week_number, so.product_id) as total_quantity
    from reference_weeks rw
    join sell_out so on so.invoice_date between rw.ref_start and rw.ref_start + 6
    where so.distributor_id = p_distributor_id
    group by rw.week_number, so.product_id, so.customer_id
  ),
  fallback_product_months as (
    select
      so.product_id,
      date_trunc('month', so.invoice_date)::date as month_start,
      sum(so.quantity) as total_quantity
    from sell_out so
    cross join month_bounds mb
    where p_weight_mode = 'history'
      and so.distributor_id = p_distributor_id
      and so.invoice_date >= (mb.month_start - interval '3 months')::date
      and so.invoice_date < mb.month_start
    group by so.product_id, date_trunc('month', so.invoice_date)
    having sum(so.quantity) > 0
  ),
  fallback_shares as (
    select
      customer_months.product_id,
      customer_months.customer_id,
      sum(customer_months.customer_quantity / product_months.total_quantity)
        / max(month_counts.month_count) as fallback_share
    from (
      select
        so.product_id,
        so.customer_id,
        date_trunc('month', so.invoice_date)::date as month_start,
        sum(so.quantity) as customer_quantity
      from sell_out so
      cross join month_bounds mb
      where p_weight_mode = 'history'
        and so.distributor_id = p_distributor_id
        and so.invoice_date >= (mb.month_start - interval '3 months')::date
        and so.invoice_date < mb.month_start
      group by so.product_id, so.customer_id, date_trunc('month', so.invoice_date)
    ) customer_months
    join fallback_product_months product_months
      on product_months.product_id = customer_months.product_id
     and product_months.month_start = customer_months.month_start
    join (
      select product_id, count(*)::numeric as month_count
      from fallback_product_months
      group by product_id
    ) month_counts on month_counts.product_id = customer_months.product_id
    group by customer_months.product_id, customer_months.customer_id
  ),
  reference_shares as (
    select
      so.customer_id,
      sum(so.quantity) as customer_quantity,
      sum(so.quantity) / nullif(sum(sum(so.quantity)) over (), 0) as volume_share
    from sell_out so
    join customers c on c.id = so.customer_id
    where p_weight_mode in ('volume_share', 'linear')
      and so.distributor_id = p_distributor_id
      and so.product_id = p_reference_product_id
      and so.invoice_date between date_trunc('month', p_reference_month)::date
        and (date_trunc('month', p_reference_month) + interval '1 month - 1 day')::date
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    group by so.customer_id
  ),
  candidate_weights as (
    select
      v.week_number,
      alloc.product_id,
      v.customer_id,
      v.sales_rep_id,
      alloc.target_quantity,
      case p_weight_mode
        when 'history' then coalesce(
          nullif(hs.customer_quantity / nullif(hs.total_quantity, 0), 0),
          fs.fallback_share,
          0
        )
        when 'volume_share' then coalesce(rs.volume_share, 0)
        when 'linear' then case when rs.customer_id is not null then 1 else 0 end
      end as raw_weight
    from visits v
    join allocation_targets alloc on alloc.week_number = v.week_number
    left join history_shares hs
      on hs.week_number = v.week_number
     and hs.product_id = alloc.product_id
     and hs.customer_id = v.customer_id
    left join fallback_shares fs
      on fs.product_id = alloc.product_id
     and fs.customer_id = v.customer_id
    left join reference_shares rs on rs.customer_id = v.customer_id
  ),
  normalized as (
    select
      cw.*,
      cw.raw_weight / nullif(
        sum(cw.raw_weight) over (partition by cw.week_number, cw.product_id), 0
      ) as weight
    from candidate_weights cw
  )
  select
    n.week_number,
    n.product_id,
    n.customer_id,
    n.sales_rep_id,
    c.channel_id,
    round(n.target_quantity * n.weight, 3) as quantity
  from normalized n
  join customers c on c.id = n.customer_id
  where n.weight is not null
    and round(n.target_quantity * n.weight, 3) > 0
$$;

-- Months that have Sell Out targets, current month onward (Automático step 1).
create or replace function planner_list_target_months(p_distributor_id uuid default null)
returns table (month_start date, total_quantity numeric, total_value numeric)
language sql
stable
security definer
set search_path = public
as $$
  select
    date_trunc('month', t.target_date)::date as month_start,
    sum(t.quantity) as total_quantity,
    sum(t.gross_value) as total_value
  from sales_targets t
  where t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and t.target_date >= date_trunc('month', current_date)::date
  group by date_trunc('month', t.target_date)
  order by month_start
$$;

-- Active route plan summary for the Parametrização screen.
create or replace function planner_route_plan_summary(p_distributor_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_route_plan_id uuid;
  v_result jsonb;
begin
  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);
  v_route_plan_id := fn_planner_active_route_plan(v_distributor_id);

  if v_route_plan_id is null then
    return null;
  end if;

  select jsonb_build_object(
    'route_plan_id', rp.id,
    'week_count', rp.week_count,
    'imported_at', rp.created_at,
    'file_name', fi.file_name,
    'total_visits', stats.total_visits,
    'total_customers', stats.total_customers,
    'total_sellers', stats.total_sellers,
    'weeks', stats.weeks
  )
  into v_result
  from planner_route_plans rp
  left join file_imports fi on fi.id = rp.import_id
  cross join lateral (
    select
      count(*) as total_visits,
      count(distinct v.customer_id) as total_customers,
      count(distinct v.sales_rep_id) as total_sellers,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object('week_number', g.week_number, 'visit_count', g.visit_count)
            order by g.week_number
          )
          from (
            select v2.week_number, count(*) as visit_count
            from planner_route_visits v2
            where v2.route_plan_id = rp.id
            group by v2.week_number
          ) g
        ),
        '[]'::jsonb
      ) as weeks
    from planner_route_visits v
    where v.route_plan_id = rp.id
  ) stats
  where rp.id = v_route_plan_id;

  return v_result;
end;
$$;

-- Top SKUs chart for the Batalha Naval models. Always returns the 5 best by
-- the chosen metric plus any explicitly added SKUs (Marcelo's optional extra).
create or replace function planner_top_skus(
  p_reference_month date,
  p_metric text,
  p_channel_ids uuid[] default null,
  p_extra_product_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns table (
  product_id uuid,
  product_name text,
  ean text,
  positivation bigint,
  total_quantity numeric,
  is_extra boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  top_sku_limit constant integer := 5;
begin
  if p_metric not in ('volume', 'positivation') then
    raise exception 'INVALID_MODE';
  end if;

  return query
  with sales as (
    select
      so.product_id as sales_product_id,
      count(distinct so.customer_id)::bigint as sales_positivation,
      sum(so.quantity) as sales_quantity
    from sell_out so
    join customers c on c.id = so.customer_id
    where so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and so.invoice_date between date_trunc('month', p_reference_month)::date
        and (date_trunc('month', p_reference_month) + interval '1 month - 1 day')::date
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    group by so.product_id
  ),
  ranked as (
    select
      s.*,
      row_number() over (
        order by
          case when p_metric = 'volume' then s.sales_quantity else s.sales_positivation::numeric end desc,
          s.sales_product_id
      ) as metric_rank
    from sales s
  )
  select
    p.id,
    p.name,
    p.ean,
    coalesce(r.sales_positivation, 0),
    coalesce(r.sales_quantity, 0),
    (r.metric_rank is null or r.metric_rank > top_sku_limit) as is_extra
  from products p
  left join ranked r on r.sales_product_id = p.id
  where p.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (
      (r.metric_rank is not null and r.metric_rank <= top_sku_limit)
      or (
        fn_report_uuid_filter_has_values(p_extra_product_ids)
        and p.id = any (p_extra_product_ids)
      )
    )
  order by coalesce(r.metric_rank, top_sku_limit + 1), p.name;
end;
$$;

-- % volume participation of each PDV for the reference SKU/month (Batalha
-- Naval Volume step 4 preview).
create or replace function planner_sku_participation(
  p_reference_month date,
  p_reference_product_id uuid,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns table (
  customer_id uuid,
  pdv_code text,
  customer_name text,
  channel_id uuid,
  channel_name text,
  total_quantity numeric,
  volume_share numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    coalesce(so.channel_id, c.channel_id),
    ch.name,
    sum(so.quantity),
    sum(so.quantity) / nullif(sum(sum(so.quantity)) over (), 0)
  from sell_out so
  join customers c on c.id = so.customer_id
  left join channels ch on ch.id = coalesce(so.channel_id, c.channel_id)
  where so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and so.product_id = p_reference_product_id
    and so.invoice_date between date_trunc('month', p_reference_month)::date
      and (date_trunc('month', p_reference_month) + interval '1 month - 1 day')::date
    and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
  group by c.id, c.pdv_code, c.trade_name, c.legal_name, coalesce(so.channel_id, c.channel_id), ch.name
  order by 6 desc
$$;

-- Active PDVs without sales of the SKU in the (past) period — Cobertura step 4.
create or replace function planner_uncovered_customers(
  p_product_id uuid,
  p_start_date date,
  p_end_date date,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns table (
  customer_id uuid,
  pdv_code text,
  customer_name text,
  channel_id uuid,
  channel_name text,
  sales_rep_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    c.channel_id,
    ch.name,
    c.sales_rep_id
  from customers c
  left join channels ch on ch.id = c.channel_id
  where c.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and c.status = 'active'
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and not exists (
      select 1
      from sell_out so
      where so.customer_id = c.id
        and so.product_id = p_product_id
        and so.invoice_date between p_start_date and p_end_date
        and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    )
  order by 3
$$;

-- PDVs whose practised margin for the SKU stayed below the target margin in
-- the period, with the revenue that the margin gap left on the table
-- (Rentabilidade steps 4-5). The cost basis is the Sell In average price of
-- the SKU — same margin rule as Status MTD (docs/PENDENCIAS_CALCULO.md); when
-- there are no purchases inside the analysed period, the 3 previous months
-- are used (Eduardo, 06/08/2026).
create or replace function planner_low_margin_customers(
  p_product_id uuid,
  p_start_date date,
  p_end_date date,
  p_target_margin numeric,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns table (
  customer_id uuid,
  pdv_code text,
  customer_name text,
  channel_id uuid,
  channel_name text,
  realized_value numeric,
  realized_quantity numeric,
  realized_margin numeric,
  margin_gap numeric,
  revenue_gap numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fallback_cost_months constant interval := interval '3 months';
  v_cost_price numeric;
begin
  if p_target_margin is null or p_target_margin <= 0 or p_target_margin >= 1 then
    raise exception 'INVALID_MARGIN';
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'INVALID_PERIOD';
  end if;

  select sum(si.gross_value) / nullif(sum(si.quantity), 0)
  into v_cost_price
  from sell_in si
  where si.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and si.product_id = p_product_id
    and si.invoice_date between p_start_date and p_end_date;

  if v_cost_price is null then
    select sum(si.gross_value) / nullif(sum(si.quantity), 0)
    into v_cost_price
    from sell_in si
    where si.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and si.product_id = p_product_id
      and si.invoice_date >= (p_start_date - fallback_cost_months)::date
      and si.invoice_date < p_start_date;
  end if;

  if v_cost_price is null then
    raise exception 'NO_COST_DATA';
  end if;

  return query
  with sold as (
    select
      so.customer_id as sold_customer_id,
      sum(so.gross_value) as total_value,
      sum(so.quantity) as total_quantity
    from sell_out so
    join customers c on c.id = so.customer_id
    where so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and so.product_id = p_product_id
      and so.invoice_date between p_start_date and p_end_date
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    group by so.customer_id
  ),
  margins as (
    select
      sold.*,
      (sold.total_value / nullif(sold.total_quantity, 0) - v_cost_price)
        / nullif(sold.total_value / nullif(sold.total_quantity, 0), 0) as margin
    from sold
  )
  select
    c.id,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    c.channel_id,
    ch.name,
    m.total_value,
    m.total_quantity,
    m.margin,
    p_target_margin - m.margin,
    (p_target_margin - m.margin) * m.total_value
  from margins m
  join customers c on c.id = m.sold_customer_id
  left join channels ch on ch.id = c.channel_id
  where m.margin is not null
    and m.margin < p_target_margin
  order by (p_target_margin - m.margin) * m.total_value desc;
end;
$$;

-- Automático: distributes the month's Sell Out volume target across the
-- visited PDVs of each configured week using historic weights.
create or replace function planner_generate_automatic(
  p_target_month date,
  p_weeks jsonb,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_route_plan_id uuid;
  v_month_start date;
  v_target_total numeric;
  v_plan_id uuid;
  v_code integer;
  v_line_count bigint;
  v_allocated numeric;
  v_week_target numeric;
begin
  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);
  v_month_start := date_trunc('month', p_target_month)::date;
  v_route_plan_id := fn_planner_active_route_plan(v_distributor_id);

  if v_route_plan_id is null then
    raise exception 'NO_ROUTE_PLAN';
  end if;

  -- Week dates never leave the target month (Eduardo, 06/08/2026), so a
  -- boundary week cannot pull another month's daily targets in.
  if exists (
    select 1
    from fn_planner_parse_weeks(p_weeks) w
    where w.start_date < v_month_start
       or w.end_date > (v_month_start + interval '1 month - 1 day')::date
  ) then
    raise exception 'INVALID_WEEKS';
  end if;

  select coalesce(sum(t.quantity), 0)
  into v_target_total
  from sales_targets t
  where t.distributor_id = v_distributor_id
    and t.target_date between v_month_start
      and (v_month_start + interval '1 month - 1 day')::date;

  if v_target_total <= 0 then
    raise exception 'NO_TARGETS_FOR_MONTH';
  end if;

  v_code := fn_planner_next_code(v_distributor_id);

  insert into planner_plans (distributor_id, code, model, params, route_plan_id, created_by)
  values (
    v_distributor_id,
    v_code,
    'automatic',
    jsonb_build_object(
      'target_month', to_char(v_month_start, 'YYYY-MM-DD'),
      'weeks', p_weeks,
      'weight_mode', 'history'
    ),
    v_route_plan_id,
    auth.uid()
  )
  returning id into v_plan_id;

  insert into planner_plan_weeks (plan_id, week_number, start_date, end_date)
  select v_plan_id, w.week_number, w.start_date, w.end_date
  from fn_planner_parse_weeks(p_weeks) w;

  insert into planner_plan_lines (
    plan_id, product_id, customer_id, sales_rep_id, channel_id, week_number, quantity
  )
  select v_plan_id, a.product_id, a.customer_id, a.sales_rep_id, a.channel_id, a.week_number, a.quantity
  from fn_planner_weekly_allocations(
    v_distributor_id, v_route_plan_id, v_month_start, p_weeks, 'history'
  ) a;

  select count(*), coalesce(sum(l.quantity), 0)
  into v_line_count, v_allocated
  from planner_plan_lines l
  where l.plan_id = v_plan_id;

  select coalesce(sum(t.quantity), 0)
  into v_week_target
  from fn_planner_parse_weeks(p_weeks) w
  join sales_targets t on t.target_date between w.start_date and w.end_date
  where t.distributor_id = v_distributor_id;

  return jsonb_build_object(
    'plan_id', v_plan_id,
    'code', v_code,
    'version', 1,
    'line_count', v_line_count,
    'allocated_quantity', v_allocated,
    'week_target_quantity', v_week_target
  );
end;
$$;

-- Batalha Naval (volume | positivation): same flow as Automático but the
-- weights come from the reference SKU's behaviour in the reference month.
create or replace function planner_generate_battleship(
  p_mode text,
  p_reference_month date,
  p_reference_product_id uuid,
  p_target_month date,
  p_weeks jsonb,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_route_plan_id uuid;
  v_month_start date;
  v_reference_start date;
  v_target_total numeric;
  v_reference_sales numeric;
  v_weight_mode text;
  v_model planner_model;
  v_plan_id uuid;
  v_code integer;
  v_line_count bigint;
  v_allocated numeric;
  v_week_target numeric;
begin
  if p_mode not in ('volume', 'positivation') then
    raise exception 'INVALID_MODE';
  end if;

  v_weight_mode := case p_mode when 'volume' then 'volume_share' else 'linear' end;
  v_model := case p_mode
    when 'volume' then 'battleship_volume'::planner_model
    else 'battleship_positivation'::planner_model
  end;

  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);
  v_month_start := date_trunc('month', p_target_month)::date;
  v_reference_start := date_trunc('month', p_reference_month)::date;
  v_route_plan_id := fn_planner_active_route_plan(v_distributor_id);

  if v_route_plan_id is null then
    raise exception 'NO_ROUTE_PLAN';
  end if;

  -- Week dates never leave the target month (Eduardo, 06/08/2026).
  if exists (
    select 1
    from fn_planner_parse_weeks(p_weeks) w
    where w.start_date < v_month_start
       or w.end_date > (v_month_start + interval '1 month - 1 day')::date
  ) then
    raise exception 'INVALID_WEEKS';
  end if;

  select coalesce(sum(t.quantity), 0)
  into v_target_total
  from sales_targets t
  where t.distributor_id = v_distributor_id
    and t.target_date between v_month_start
      and (v_month_start + interval '1 month - 1 day')::date;

  if v_target_total <= 0 then
    raise exception 'NO_TARGETS_FOR_MONTH';
  end if;

  select coalesce(sum(so.quantity), 0)
  into v_reference_sales
  from sell_out so
  join customers c on c.id = so.customer_id
  where so.distributor_id = v_distributor_id
    and so.product_id = p_reference_product_id
    and so.invoice_date between v_reference_start
      and (v_reference_start + interval '1 month - 1 day')::date
    and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids);

  if v_reference_sales <= 0 then
    raise exception 'NO_REFERENCE_SALES';
  end if;

  v_code := fn_planner_next_code(v_distributor_id);

  insert into planner_plans (distributor_id, code, model, params, route_plan_id, created_by)
  values (
    v_distributor_id,
    v_code,
    v_model,
    jsonb_build_object(
      'target_month', to_char(v_month_start, 'YYYY-MM-DD'),
      'weeks', p_weeks,
      'weight_mode', v_weight_mode,
      'reference_month', to_char(v_reference_start, 'YYYY-MM-DD'),
      'reference_product_id', p_reference_product_id,
      'channel_ids', coalesce(to_jsonb(p_channel_ids), 'null'::jsonb)
    ),
    v_route_plan_id,
    auth.uid()
  )
  returning id into v_plan_id;

  insert into planner_plan_weeks (plan_id, week_number, start_date, end_date)
  select v_plan_id, w.week_number, w.start_date, w.end_date
  from fn_planner_parse_weeks(p_weeks) w;

  insert into planner_plan_lines (
    plan_id, product_id, customer_id, sales_rep_id, channel_id, week_number, quantity
  )
  select v_plan_id, a.product_id, a.customer_id, a.sales_rep_id, a.channel_id, a.week_number, a.quantity
  from fn_planner_weekly_allocations(
    v_distributor_id, v_route_plan_id, v_month_start, p_weeks,
    v_weight_mode, v_reference_start, p_reference_product_id, p_channel_ids
  ) a;

  select count(*), coalesce(sum(l.quantity), 0)
  into v_line_count, v_allocated
  from planner_plan_lines l
  where l.plan_id = v_plan_id;

  select coalesce(sum(t.quantity), 0)
  into v_week_target
  from fn_planner_parse_weeks(p_weeks) w
  join sales_targets t on t.target_date between w.start_date and w.end_date
  where t.distributor_id = v_distributor_id;

  return jsonb_build_object(
    'plan_id', v_plan_id,
    'code', v_code,
    'version', 1,
    'line_count', v_line_count,
    'allocated_quantity', v_allocated,
    'week_target_quantity', v_week_target
  );
end;
$$;

-- Recalcular Rota: redistributes the month's remaining balance (target minus
-- realized) across the not-yet-closed weeks, creating a new version of the
-- plan. Closed weeks keep their original lines; visits never change.
create or replace function planner_recalculate_route(p_plan_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_plan planner_plans%rowtype;
  v_new_plan_id uuid;
  v_remaining_weeks jsonb;
  v_min_remaining smallint;
  v_closed_count integer;
  v_remaining_count integer;
  v_reference_month date;
  v_reference_product_id uuid;
  v_channel_ids uuid[];
  v_line_count bigint;
  v_allocated numeric;
begin
  select * into v_plan from planner_plans where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'PLAN_NOT_FOUND';
  end if;

  perform assert_authorized_distributor_scope(v_plan.distributor_id);

  -- Same lock used by fn_planner_next_code: serializes concurrent recalcs
  -- (and generations) for the distributor, then re-checks the status that may
  -- have changed while waiting.
  perform pg_advisory_xact_lock(
    hashtext('planner_plans_code_' || v_plan.distributor_id::text)
  );
  select * into v_plan from planner_plans where id = p_plan_id;

  if v_plan.status <> 'generated' then
    raise exception 'PLAN_ALREADY_REPLACED';
  end if;

  if v_plan.model not in ('automatic', 'battleship_volume', 'battleship_positivation') then
    raise exception 'PLAN_NOT_WEEKLY';
  end if;

  select count(*) filter (where w.end_date < current_date),
         count(*) filter (where w.end_date >= current_date)
  into v_closed_count, v_remaining_count
  from planner_plan_weeks w
  where w.plan_id = p_plan_id;

  if v_closed_count = 0 then
    raise exception 'NO_CLOSED_WEEKS';
  end if;

  if v_remaining_count = 0 then
    raise exception 'NO_REMAINING_WEEKS';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'week_number', w.week_number,
      'start_date', to_char(w.start_date, 'YYYY-MM-DD'),
      'end_date', to_char(w.end_date, 'YYYY-MM-DD')
    )
    order by w.week_number
  ), min(w.week_number)
  into v_remaining_weeks, v_min_remaining
  from planner_plan_weeks w
  where w.plan_id = p_plan_id
    and w.end_date >= current_date;

  v_reference_month := nullif(v_plan.params->>'reference_month', '')::date;
  v_reference_product_id := nullif(v_plan.params->>'reference_product_id', '')::uuid;

  select array_agg(value::uuid)
  into v_channel_ids
  from jsonb_array_elements_text(
    case
      when jsonb_typeof(v_plan.params->'channel_ids') = 'array' then v_plan.params->'channel_ids'
      else '[]'::jsonb
    end
  );

  insert into planner_plans (
    distributor_id, code, model, version, params, route_plan_id, created_by
  )
  values (
    v_plan.distributor_id,
    v_plan.code,
    v_plan.model,
    v_plan.version + 1,
    v_plan.params || jsonb_build_object(
      'recalculated_at', to_char(current_date, 'YYYY-MM-DD'),
      'recalculated_from_week', v_min_remaining
    ),
    v_plan.route_plan_id,
    auth.uid()
  )
  returning id into v_new_plan_id;

  insert into planner_plan_weeks (plan_id, week_number, start_date, end_date)
  select v_new_plan_id, w.week_number, w.start_date, w.end_date
  from planner_plan_weeks w
  where w.plan_id = p_plan_id;

  insert into planner_plan_lines (
    plan_id, product_id, customer_id, sales_rep_id, channel_id, week_number, quantity, gross_value
  )
  select v_new_plan_id, l.product_id, l.customer_id, l.sales_rep_id, l.channel_id,
         l.week_number, l.quantity, l.gross_value
  from planner_plan_lines l
  join planner_plan_weeks w on w.plan_id = l.plan_id and w.week_number = l.week_number
  where l.plan_id = p_plan_id
    and w.end_date < current_date;

  insert into planner_plan_lines (
    plan_id, product_id, customer_id, sales_rep_id, channel_id, week_number, quantity
  )
  select v_new_plan_id, a.product_id, a.customer_id, a.sales_rep_id, a.channel_id, a.week_number, a.quantity
  from fn_planner_weekly_allocations(
    v_plan.distributor_id,
    v_plan.route_plan_id,
    (v_plan.params->>'target_month')::date,
    v_remaining_weeks,
    coalesce(v_plan.params->>'weight_mode', 'history'),
    v_reference_month,
    v_reference_product_id,
    v_channel_ids,
    true
  ) a;

  update planner_plans set status = 'replaced' where id = p_plan_id;

  select count(*), coalesce(sum(l.quantity), 0)
  into v_line_count, v_allocated
  from planner_plan_lines l
  where l.plan_id = v_new_plan_id;

  return jsonb_build_object(
    'plan_id', v_new_plan_id,
    'code', v_plan.code,
    'version', v_plan.version + 1,
    'line_count', v_line_count,
    'allocated_quantity', v_allocated,
    'recalculated_from_week', v_min_remaining
  );
end;
$$;

-- Cobertura: distributes a financial or volume target linearly across the
-- PDVs not covered in the chosen (past) period. The execution period is the
-- deadline the distributor picks to pursue the target (Eduardo, 06/08/2026);
-- the dashboard evaluates the plan inside it.
create or replace function planner_generate_coverage(
  p_product_id uuid,
  p_start_date date,
  p_end_date date,
  p_target_kind text,
  p_target_amount numeric,
  p_execution_start date,
  p_execution_end date,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_customer_count bigint;
  v_amount_per_customer numeric;
  v_plan_id uuid;
  v_code integer;
begin
  if p_product_id is null then
    raise exception 'MISSING_PRODUCT';
  end if;

  if p_target_kind not in ('value', 'quantity') then
    raise exception 'INVALID_TARGET';
  end if;

  if p_target_amount is null or p_target_amount <= 0 then
    raise exception 'INVALID_TARGET';
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'INVALID_PERIOD';
  end if;

  if p_execution_start is null or p_execution_end is null
    or p_execution_start > p_execution_end then
    raise exception 'INVALID_PERIOD';
  end if;

  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);

  select count(*)
  into v_customer_count
  from planner_uncovered_customers(
    p_product_id, p_start_date, p_end_date, p_channel_ids, v_distributor_id
  );

  if v_customer_count = 0 then
    raise exception 'NO_UNCOVERED_CUSTOMERS';
  end if;

  v_amount_per_customer := p_target_amount / v_customer_count;
  v_code := fn_planner_next_code(v_distributor_id);

  insert into planner_plans (distributor_id, code, model, params, created_by)
  values (
    v_distributor_id,
    v_code,
    'coverage',
    jsonb_build_object(
      'product_id', p_product_id,
      'channel_ids', coalesce(to_jsonb(p_channel_ids), 'null'::jsonb),
      'start_date', to_char(p_start_date, 'YYYY-MM-DD'),
      'end_date', to_char(p_end_date, 'YYYY-MM-DD'),
      'target_kind', p_target_kind,
      'target_amount', p_target_amount,
      'execution_start', to_char(p_execution_start, 'YYYY-MM-DD'),
      'execution_end', to_char(p_execution_end, 'YYYY-MM-DD')
    ),
    auth.uid()
  )
  returning id into v_plan_id;

  insert into planner_plan_lines (
    plan_id, product_id, customer_id, sales_rep_id, channel_id, quantity, gross_value
  )
  select
    v_plan_id,
    p_product_id,
    u.customer_id,
    u.sales_rep_id,
    u.channel_id,
    case when p_target_kind = 'quantity' then round(v_amount_per_customer, 3) end,
    case when p_target_kind = 'value' then round(v_amount_per_customer, 2) end
  from planner_uncovered_customers(
    p_product_id, p_start_date, p_end_date, p_channel_ids, v_distributor_id
  ) u;

  return jsonb_build_object(
    'plan_id', v_plan_id,
    'code', v_code,
    'version', 1,
    'line_count', v_customer_count,
    'amount_per_customer', v_amount_per_customer
  );
end;
$$;

-- Rentabilidade: one line per PDV below the target margin, valued at the
-- revenue the margin gap left on the table. The execution period is the
-- deadline the distributor picks to recover that revenue (Eduardo,
-- 06/08/2026); the dashboard evaluates the plan inside it.
create or replace function planner_generate_profitability(
  p_product_id uuid,
  p_start_date date,
  p_end_date date,
  p_target_margin numeric,
  p_execution_start date,
  p_execution_end date,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_plan_id uuid;
  v_code integer;
  v_line_count bigint;
  v_total_gap numeric;
begin
  if p_product_id is null then
    raise exception 'MISSING_PRODUCT';
  end if;

  if p_execution_start is null or p_execution_end is null
    or p_execution_start > p_execution_end then
    raise exception 'INVALID_PERIOD';
  end if;

  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);
  v_code := fn_planner_next_code(v_distributor_id);

  insert into planner_plans (distributor_id, code, model, params, created_by)
  values (
    v_distributor_id,
    v_code,
    'profitability',
    jsonb_build_object(
      'product_id', p_product_id,
      'channel_ids', coalesce(to_jsonb(p_channel_ids), 'null'::jsonb),
      'start_date', to_char(p_start_date, 'YYYY-MM-DD'),
      'end_date', to_char(p_end_date, 'YYYY-MM-DD'),
      'target_margin', p_target_margin,
      'execution_start', to_char(p_execution_start, 'YYYY-MM-DD'),
      'execution_end', to_char(p_execution_end, 'YYYY-MM-DD')
    ),
    auth.uid()
  )
  returning id into v_plan_id;

  insert into planner_plan_lines (
    plan_id, product_id, customer_id, sales_rep_id, channel_id, gross_value
  )
  select
    v_plan_id,
    p_product_id,
    m.customer_id,
    c.sales_rep_id,
    m.channel_id,
    round(m.revenue_gap, 2)
  from planner_low_margin_customers(
    p_product_id, p_start_date, p_end_date, p_target_margin, p_channel_ids, v_distributor_id
  ) m
  join customers c on c.id = m.customer_id
  where m.revenue_gap > 0;

  select count(*), coalesce(sum(l.gross_value), 0)
  into v_line_count, v_total_gap
  from planner_plan_lines l
  where l.plan_id = v_plan_id;

  if v_line_count = 0 then
    raise exception 'NO_CUSTOMERS_BELOW_MARGIN';
  end if;

  return jsonb_build_object(
    'plan_id', v_plan_id,
    'code', v_code,
    'version', 1,
    'line_count', v_line_count,
    'total_revenue_gap', v_total_gap
  );
end;
$$;

-- Generated planners, newest first, with per-plan totals.
create or replace function planner_list_plans(p_distributor_id uuid default null)
returns table (
  id uuid,
  code integer,
  model text,
  version integer,
  status text,
  params jsonb,
  route_plan_id uuid,
  line_count bigint,
  total_quantity numeric,
  total_value numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.code,
    p.model::text,
    p.version,
    p.status::text,
    p.params,
    p.route_plan_id,
    coalesce(totals.line_count, 0),
    totals.total_quantity,
    totals.total_value,
    p.created_at
  from planner_plans p
  left join lateral (
    select
      count(*) as line_count,
      sum(l.quantity) as total_quantity,
      sum(l.gross_value) as total_value
    from planner_plan_lines l
    where l.plan_id = p.id
  ) totals on true
  where p.distributor_id in (select authorized_distributor_ids(p_distributor_id))
  order by p.code desc, p.version desc
$$;

-- Paginated plan lines for the detail screen and exports.
create or replace function planner_plan_lines_page(
  p_plan_id uuid,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  line_id bigint,
  week_number smallint,
  ean text,
  product_name text,
  pdv_code text,
  customer_name text,
  sales_rep_name text,
  channel_name text,
  quantity numeric,
  gross_value numeric,
  distributor_cnpj text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  max_page_size constant integer := 500;
  v_distributor_id uuid;
  v_distributor_cnpj text;
begin
  select p.distributor_id, d.cnpj
  into v_distributor_id, v_distributor_cnpj
  from planner_plans p
  join distributors d on d.id = p.distributor_id
  where p.id = p_plan_id;

  if v_distributor_id is null then
    raise exception 'PLAN_NOT_FOUND';
  end if;

  perform assert_authorized_distributor_scope(v_distributor_id);

  return query
  select
    l.id,
    l.week_number,
    pr.ean,
    pr.name,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    sr.name,
    ch.name,
    l.quantity,
    l.gross_value,
    v_distributor_cnpj,
    count(*) over ()
  from planner_plan_lines l
  join products pr on pr.id = l.product_id
  join customers c on c.id = l.customer_id
  left join sales_reps sr on sr.id = l.sales_rep_id
  left join channels ch on ch.id = l.channel_id
  where l.plan_id = p_plan_id
  order by l.week_number nulls last, pr.name, coalesce(c.trade_name, c.legal_name), l.id
  limit least(greatest(coalesce(p_limit, 50), 1), max_page_size)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- Serializes one evaluated dashboard group (seller/customer/channel/product)
-- into the jsonb row shape shared by every by_* array.
create or replace function fn_planner_dashboard_group_row(
  p_group_id uuid,
  p_group_name text,
  p_total_lines bigint,
  p_achieved_lines bigint,
  p_planned_quantity numeric,
  p_realized_quantity numeric,
  p_planned_value numeric,
  p_realized_value numeric
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'group_id', p_group_id,
    'group_name', p_group_name,
    'total_lines', p_total_lines,
    'achieved_lines', p_achieved_lines,
    'achievement_rate', p_achieved_lines::numeric / nullif(p_total_lines, 0)::numeric,
    'planned_quantity', p_planned_quantity,
    'realized_quantity', p_realized_quantity,
    'planned_value', p_planned_value,
    'realized_value', p_realized_value,
    'quantity_variation',
      (p_realized_quantity - p_planned_quantity) / nullif(p_planned_quantity, 0),
    'value_variation',
      (p_realized_value - p_planned_value) / nullif(p_planned_value, 0)
  )
$$;

-- Planned x realized evaluation of a generated planner (Dashboard screen).
-- Weekly plans compare each line inside its week date range; Cobertura and
-- Rentabilidade use the evaluation period (defaults to the current month).
create or replace function planner_dashboard(
  p_plan_id uuid,
  p_eval_start date default null,
  p_eval_end date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  customer_group_limit constant integer := 50;
  v_plan planner_plans%rowtype;
  v_eval_start date;
  v_eval_end date;
  v_result jsonb;
begin
  select * into v_plan from planner_plans where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'PLAN_NOT_FOUND';
  end if;

  perform assert_authorized_distributor_scope(v_plan.distributor_id);

  -- Non-weekly plans carry the execution period picked at generation; the
  -- caller can still override it, and the current month is the last resort
  -- for plans generated before this field existed.
  v_eval_start := coalesce(
    p_eval_start,
    nullif(v_plan.params->>'execution_start', '')::date,
    date_trunc('month', current_date)::date
  );
  v_eval_end := coalesce(
    p_eval_end,
    nullif(v_plan.params->>'execution_end', '')::date,
    (date_trunc('month', current_date) + interval '1 month - 1 day')::date
  );

  with lines as (
    select
      l.id,
      l.product_id,
      l.customer_id,
      l.sales_rep_id,
      l.channel_id,
      l.week_number,
      l.quantity,
      l.gross_value,
      coalesce(w.start_date, v_eval_start) as eval_start,
      coalesce(w.end_date, v_eval_end) as eval_end
    from planner_plan_lines l
    left join planner_plan_weeks w
      on w.plan_id = l.plan_id and w.week_number = l.week_number
    where l.plan_id = p_plan_id
  ),
  evaluated as (
    select
      l.*,
      coalesce(r.realized_quantity, 0) as realized_quantity,
      coalesce(r.realized_value, 0) as realized_value,
      case
        when l.quantity is not null then coalesce(r.realized_quantity, 0) >= l.quantity
        else coalesce(r.realized_value, 0) >= l.gross_value
      end as is_achieved,
      case
        when l.quantity is not null
          then greatest(l.quantity - coalesce(r.realized_quantity, 0), 0)
      end as missed_quantity,
      case
        when l.gross_value is not null
          then greatest(l.gross_value - coalesce(r.realized_value, 0), 0)
      end as missed_value
    from lines l
    left join lateral (
      select
        sum(so.quantity) as realized_quantity,
        sum(so.gross_value) as realized_value
      from sell_out so
      where so.distributor_id = v_plan.distributor_id
        and so.customer_id = l.customer_id
        and so.product_id = l.product_id
        and so.invoice_date between l.eval_start and l.eval_end
    ) r on true
  ),
  seller_groups as (
    select
      e.sales_rep_id as group_id,
      sr.name as group_name,
      count(*) as total_lines,
      count(*) filter (where e.is_achieved) as achieved_lines,
      sum(e.quantity) as planned_quantity,
      sum(e.realized_quantity) as realized_quantity,
      sum(e.gross_value) as planned_value,
      sum(e.realized_value) as realized_value
    from evaluated e
    left join sales_reps sr on sr.id = e.sales_rep_id
    group by e.sales_rep_id, sr.name
  ),
  seller_rows as (
    select jsonb_agg(fn_planner_dashboard_group_row(
      g.group_id, g.group_name, g.total_lines, g.achieved_lines,
      g.planned_quantity, g.realized_quantity, g.planned_value, g.realized_value
    ) order by g.group_name nulls last) as rows
    from seller_groups g
  ),
  customer_rows as (
    select jsonb_agg(fn_planner_dashboard_group_row(
      g.group_id, g.group_name, g.total_lines, g.achieved_lines,
      g.planned_quantity, g.realized_quantity, g.planned_value, g.realized_value
    ) order by g.planned_rank) as rows
    from (
      select
        e.customer_id as group_id,
        coalesce(c.trade_name, c.legal_name) as group_name,
        count(*) as total_lines,
        count(*) filter (where e.is_achieved) as achieved_lines,
        sum(e.quantity) as planned_quantity,
        sum(e.realized_quantity) as realized_quantity,
        sum(e.gross_value) as planned_value,
        sum(e.realized_value) as realized_value,
        row_number() over (
          order by coalesce(sum(e.gross_value), sum(e.quantity)) desc nulls last
        ) as planned_rank
      from evaluated e
      join customers c on c.id = e.customer_id
      group by e.customer_id, coalesce(c.trade_name, c.legal_name)
    ) g
    where g.planned_rank <= customer_group_limit
  ),
  channel_rows as (
    select jsonb_agg(fn_planner_dashboard_group_row(
      g.group_id, g.group_name, g.total_lines, g.achieved_lines,
      g.planned_quantity, g.realized_quantity, g.planned_value, g.realized_value
    ) order by g.group_name nulls last) as rows
    from (
      select
        e.channel_id as group_id,
        ch.name as group_name,
        count(*) as total_lines,
        count(*) filter (where e.is_achieved) as achieved_lines,
        sum(e.quantity) as planned_quantity,
        sum(e.realized_quantity) as realized_quantity,
        sum(e.gross_value) as planned_value,
        sum(e.realized_value) as realized_value
      from evaluated e
      left join channels ch on ch.id = e.channel_id
      group by e.channel_id, ch.name
    ) g
  ),
  product_rows as (
    select jsonb_agg(fn_planner_dashboard_group_row(
      g.group_id, g.group_name, g.total_lines, g.achieved_lines,
      g.planned_quantity, g.realized_quantity, g.planned_value, g.realized_value
    ) order by g.group_name) as rows
    from (
      select
        e.product_id as group_id,
        pr.name as group_name,
        count(*) as total_lines,
        count(*) filter (where e.is_achieved) as achieved_lines,
        sum(e.quantity) as planned_quantity,
        sum(e.realized_quantity) as realized_quantity,
        sum(e.gross_value) as planned_value,
        sum(e.realized_value) as realized_value
      from evaluated e
      join products pr on pr.id = e.product_id
      group by e.product_id, pr.name
    ) g
  ),
  summary as (
    select
      count(*) as total_lines,
      count(*) filter (where e.is_achieved) as achieved_lines,
      sum(e.quantity) as planned_quantity,
      sum(e.realized_quantity) as realized_quantity,
      sum(e.gross_value) as planned_value,
      sum(e.realized_value) as realized_value,
      sum(e.missed_quantity) as missed_quantity,
      sum(e.missed_value) as missed_value
    from evaluated e
  ),
  best_seller as (
    select fn_planner_dashboard_group_row(
      g.group_id, g.group_name, g.total_lines, g.achieved_lines,
      g.planned_quantity, g.realized_quantity, g.planned_value, g.realized_value
    ) as row
    from seller_groups g
    where g.group_id is not null and g.total_lines > 0
    order by g.achieved_lines::numeric / g.total_lines desc, g.group_name
    limit 1
  ),
  worst_seller as (
    select fn_planner_dashboard_group_row(
      g.group_id, g.group_name, g.total_lines, g.achieved_lines,
      g.planned_quantity, g.realized_quantity, g.planned_value, g.realized_value
    ) as row
    from seller_groups g
    where g.group_id is not null and g.total_lines > 0
    order by g.achieved_lines::numeric / g.total_lines asc, g.group_name
    limit 1
  )
  select jsonb_build_object(
    'plan', jsonb_build_object(
      'id', v_plan.id,
      'code', v_plan.code,
      'model', v_plan.model,
      'version', v_plan.version,
      'status', v_plan.status,
      'params', v_plan.params,
      'created_at', v_plan.created_at
    ),
    'eval_period', jsonb_build_object('start_date', v_eval_start, 'end_date', v_eval_end),
    'summary', jsonb_build_object(
      'total_lines', s.total_lines,
      'achieved_lines', s.achieved_lines,
      'achievement_rate', fn_safe_div(s.achieved_lines::numeric, s.total_lines::numeric),
      'planned_quantity', s.planned_quantity,
      'realized_quantity', s.realized_quantity,
      'planned_value', s.planned_value,
      'realized_value', s.realized_value,
      'missed_quantity', s.missed_quantity,
      'missed_value', s.missed_value
    ),
    'best_seller', (select row from best_seller),
    'worst_seller', (select row from worst_seller),
    'by_seller', coalesce((select rows from seller_rows), '[]'::jsonb),
    'by_customer', coalesce((select rows from customer_rows), '[]'::jsonb),
    'by_channel', coalesce((select rows from channel_rows), '[]'::jsonb),
    'by_product', coalesce((select rows from product_rows), '[]'::jsonb)
  )
  into v_result
  from summary s;

  return v_result;
end;
$$;

revoke execute on function fn_planner_iso_week_start(integer, integer) from public, anon, authenticated;
revoke execute on function fn_planner_parse_weeks(jsonb) from public, anon, authenticated;
revoke execute on function fn_planner_next_code(uuid) from public, anon, authenticated;
revoke execute on function fn_planner_active_route_plan(uuid) from public, anon, authenticated;
revoke execute on function fn_planner_weekly_allocations(uuid, uuid, date, jsonb, text, date, uuid, uuid[], boolean)
  from public, anon, authenticated;
revoke execute on function fn_planner_dashboard_group_row(uuid, text, bigint, bigint, numeric, numeric, numeric, numeric)
  from public, anon, authenticated;

revoke execute on function planner_list_target_months(uuid) from public, anon;
revoke execute on function planner_route_plan_summary(uuid) from public, anon;
revoke execute on function planner_top_skus(date, text, uuid[], uuid[], uuid) from public, anon;
revoke execute on function planner_sku_participation(date, uuid, uuid[], uuid) from public, anon;
revoke execute on function planner_uncovered_customers(uuid, date, date, uuid[], uuid) from public, anon;
revoke execute on function planner_low_margin_customers(uuid, date, date, numeric, uuid[], uuid) from public, anon;
revoke execute on function planner_generate_automatic(date, jsonb, uuid) from public, anon;
revoke execute on function planner_generate_battleship(text, date, uuid, date, jsonb, uuid[], uuid) from public, anon;
revoke execute on function planner_recalculate_route(uuid) from public, anon;
revoke execute on function planner_generate_coverage(uuid, date, date, text, numeric, date, date, uuid[], uuid) from public, anon;
revoke execute on function planner_generate_profitability(uuid, date, date, numeric, date, date, uuid[], uuid) from public, anon;
revoke execute on function planner_list_plans(uuid) from public, anon;
revoke execute on function planner_plan_lines_page(uuid, integer, integer) from public, anon;
revoke execute on function planner_dashboard(uuid, date, date) from public, anon;

grant execute on function planner_list_target_months(uuid) to authenticated;
grant execute on function planner_route_plan_summary(uuid) to authenticated;
grant execute on function planner_top_skus(date, text, uuid[], uuid[], uuid) to authenticated;
grant execute on function planner_sku_participation(date, uuid, uuid[], uuid) to authenticated;
grant execute on function planner_uncovered_customers(uuid, date, date, uuid[], uuid) to authenticated;
grant execute on function planner_low_margin_customers(uuid, date, date, numeric, uuid[], uuid) to authenticated;
grant execute on function planner_generate_automatic(date, jsonb, uuid) to authenticated;
grant execute on function planner_generate_battleship(text, date, uuid, date, jsonb, uuid[], uuid) to authenticated;
grant execute on function planner_recalculate_route(uuid) to authenticated;
grant execute on function planner_generate_coverage(uuid, date, date, text, numeric, date, date, uuid[], uuid) to authenticated;
grant execute on function planner_generate_profitability(uuid, date, date, numeric, date, date, uuid[], uuid) to authenticated;
grant execute on function planner_list_plans(uuid) to authenticated;
grant execute on function planner_plan_lines_page(uuid, integer, integer) to authenticated;
grant execute on function planner_dashboard(uuid, date, date) to authenticated;
