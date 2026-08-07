-- Traceability in the plan listing: expose which imported route file fed the
-- weekly models (planner_plans.route_plan_id -> planner_route_plans.import_id
-- -> file_imports.file_name). Coverage/Rentabilidade plans have no route and
-- show null.

drop function if exists planner_list_plans(uuid);

create or replace function planner_list_plans(p_distributor_id uuid default null)
returns table (
  id uuid,
  code integer,
  model text,
  version integer,
  status text,
  params jsonb,
  route_plan_id uuid,
  route_file_name text,
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
    fi.file_name,
    coalesce(totals.line_count, 0),
    totals.total_quantity,
    totals.total_value,
    p.created_at
  from planner_plans p
  left join planner_route_plans rp on rp.id = p.route_plan_id
  left join file_imports fi on fi.id = rp.import_id
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

revoke execute on function planner_list_plans(uuid) from public, anon;
grant execute on function planner_list_plans(uuid) to authenticated;
