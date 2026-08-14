-- Planner: business "today" in America/Sao_Paulo + week semantics in the summary.
--
-- 1) The database runs in UTC, so current_date flipped at 21:00 BRT: a week
--    ending today was already treated as closed (freezing it for Recalcular
--    Rota and showing it as "Fechada") three hours before the day ended in
--    Brazil. fn_planner_today() centralises the business date so every planner
--    function agrees on when a week closes.
-- 2) planner_plan_week_summary now also returns recalculated_from_week, so the
--    UI can label each week by what the version actually did (preserved vs
--    recalculated) instead of re-deriving "closed" at read time — a plan opened
--    days later kept showing weeks as closed while displaying a delta, which
--    contradicted the reading.

create or replace function fn_planner_today()
returns date
language sql
stable
as $$
  select (current_timestamp at time zone 'America/Sao_Paulo')::date
$$;

revoke execute on function fn_planner_today() from public, anon, authenticated;

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
        and so.invoice_date between mb.month_start and least(mb.month_end, fn_planner_today())
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
    and t.target_date >= date_trunc('month', fn_planner_today())::date
  group by date_trunc('month', t.target_date)
  order by month_start
$$;

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

  select count(*) filter (where w.end_date < fn_planner_today()),
         count(*) filter (where w.end_date >= fn_planner_today())
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
    and w.end_date >= fn_planner_today();

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
      'recalculated_at', to_char(fn_planner_today(), 'YYYY-MM-DD'),
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
    and w.end_date < fn_planner_today();

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
    date_trunc('month', fn_planner_today())::date
  );
  v_eval_end := coalesce(
    p_eval_end,
    nullif(v_plan.params->>'execution_end', '')::date,
    (date_trunc('month', fn_planner_today()) + interval '1 month - 1 day')::date
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

drop function if exists planner_plan_week_summary(uuid);

create or replace function planner_plan_week_summary(p_plan_id uuid)
returns table (
  week_number smallint,
  start_date date,
  end_date date,
  is_closed boolean,
  line_count bigint,
  quantity numeric,
  gross_value numeric,
  previous_quantity numeric,
  previous_gross_value numeric,
  previous_version integer,
  recalculated_from_week smallint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan planner_plans%rowtype;
  v_previous_plan_id uuid;
  v_previous_version integer;
  v_recalculated_from_week smallint;
begin
  select * into v_plan from planner_plans where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'PLAN_NOT_FOUND';
  end if;

  perform assert_authorized_distributor_scope(v_plan.distributor_id);

  select p.id, p.version
  into v_previous_plan_id, v_previous_version
  from planner_plans p
  where p.distributor_id = v_plan.distributor_id
    and p.code = v_plan.code
    and p.version < v_plan.version
  order by p.version desc
  limit 1;

  v_recalculated_from_week := nullif(v_plan.params->>'recalculated_from_week', '')::smallint;

  return query
  -- The previous version is matched by week_number because Recalcular Rota
  -- copies the week ranges verbatim (planner_recalculate_route); if that ever
  -- changes, this comparison has to match on dates too.
  select
    w.week_number,
    w.start_date,
    w.end_date,
    w.end_date < fn_planner_today(),
    coalesce(current_week.line_count, 0),
    current_week.quantity,
    current_week.gross_value,
    previous_week.quantity,
    previous_week.gross_value,
    v_previous_version,
    v_recalculated_from_week
  from planner_plan_weeks w
  left join lateral (
    select
      count(*) as line_count,
      sum(l.quantity) as quantity,
      sum(l.gross_value) as gross_value
    from planner_plan_lines l
    where l.plan_id = p_plan_id
      and l.week_number = w.week_number
  ) current_week on true
  left join lateral (
    select
      sum(l.quantity) as quantity,
      sum(l.gross_value) as gross_value
    from planner_plan_lines l
    where v_previous_plan_id is not null
      and l.plan_id = v_previous_plan_id
      and l.week_number = w.week_number
  ) previous_week on true
  where w.plan_id = p_plan_id
  order by w.week_number;
end;
$$;

revoke execute on function planner_plan_week_summary(uuid) from public, anon;
grant execute on function planner_plan_week_summary(uuid) to authenticated;
