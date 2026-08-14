-- Weekly breakdown of a generated plan, with the previous version side by side.
-- The plan detail only listed individual lines, so there was no way to see how
-- the month's target was split across weeks — the whole point of the weekly
-- models — nor what Recalcular Rota changed. Closed weeks are flagged with the
-- same rule used by planner_recalculate_route (end_date < current_date).

-- Dropped first because a later migration changes the returned columns, and
-- create or replace cannot change a function's return type on replay.
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
  previous_version integer
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

  return query
  select
    w.week_number,
    w.start_date,
    w.end_date,
    w.end_date < current_date,
    coalesce(current_week.line_count, 0),
    current_week.quantity,
    current_week.gross_value,
    previous_week.quantity,
    previous_week.gross_value,
    v_previous_version
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
