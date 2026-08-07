-- Planner module, part 1: route plans (visit schedules) and generated plans.
-- Spec: docs/PLANNER_SPEC.md (sections 13 and 15).
--
-- The distributor imports a visit route file (ROUTE_PLAN file type, 3/4/5-week
-- layouts). Generated planners are persisted so they can be re-queried, exported
-- and evaluated against actuals. Writes happen only through security definer
-- functions; the portal role only reads.

create type planner_model as enum (
  'automatic',
  'battleship_volume',
  'battleship_positivation',
  'coverage',
  'profitability'
);

create type planner_plan_status as enum ('generated', 'replaced');

-- Route plan header. A new import creates a new header; the most recent one is
-- the active route for the distributor.
create table if not exists planner_route_plans (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references distributors(id),
  week_count smallint not null check (week_count between 3 and 5),
  import_id uuid references file_imports(id),
  created_at timestamptz not null default now()
);

create index if not exists planner_route_plans_distributor_idx
  on planner_route_plans (distributor_id, created_at desc);

-- Planned visits. Multiple marks for the same customer/week collapse into a
-- single visit (business rule: one controlled visit per week).
create table if not exists planner_route_visits (
  id bigint generated always as identity primary key,
  route_plan_id uuid not null references planner_route_plans(id) on delete cascade,
  customer_id uuid not null references customers(id),
  sales_rep_id uuid references sales_reps(id),
  week_number smallint not null check (week_number between 1 and 5),
  unique (route_plan_id, customer_id, week_number)
);

create index if not exists planner_route_visits_plan_week_idx
  on planner_route_visits (route_plan_id, week_number);

-- Generated planners. `code` is a per-distributor sequential identifier
-- (rendered as PLN-001 in the UI) so simultaneous planners can be told apart
-- when re-querying or evaluating them. Recalcular Rota creates a new version
-- of the same code and marks the previous one as replaced.
create table if not exists planner_plans (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references distributors(id),
  code integer not null,
  model planner_model not null,
  version integer not null default 1 check (version >= 1),
  status planner_plan_status not null default 'generated',
  params jsonb not null default '{}'::jsonb,
  route_plan_id uuid references planner_route_plans(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (distributor_id, code, version)
);

create index if not exists planner_plans_distributor_idx
  on planner_plans (distributor_id, code desc, version desc);

-- Week date ranges chosen by the user for a plan. Targets are stored per day,
-- so these ranges are what allows crossing target x plan x actuals per week.
create table if not exists planner_plan_weeks (
  id bigint generated always as identity primary key,
  plan_id uuid not null references planner_plans(id) on delete cascade,
  week_number smallint not null check (week_number between 1 and 5),
  start_date date not null,
  end_date date not null,
  unique (plan_id, week_number),
  check (start_date <= end_date)
);

-- Plan lines. Each line is one "plan" in the evaluation dashboard.
-- quantity is used by volume-based models, gross_value by money-based ones;
-- coverage uses one or the other depending on the chosen target kind.
create table if not exists planner_plan_lines (
  id bigint generated always as identity primary key,
  plan_id uuid not null references planner_plans(id) on delete cascade,
  product_id uuid not null references products(id),
  customer_id uuid not null references customers(id),
  sales_rep_id uuid references sales_reps(id),
  channel_id uuid references channels(id),
  week_number smallint check (week_number between 1 and 5),
  quantity numeric(14, 3) check (quantity >= 0),
  gross_value numeric(14, 2) check (gross_value >= 0),
  check (quantity is not null or gross_value is not null)
);

create index if not exists planner_plan_lines_plan_idx
  on planner_plan_lines (plan_id, week_number);

create index if not exists planner_plan_lines_customer_idx
  on planner_plan_lines (plan_id, customer_id);

-- Staging table for the ROUTE_PLAN import (same contract as the other
-- staging_* tables: all text, parsed by the process function).
create unlogged table if not exists staging_route_plans (
  import_id uuid not null,
  line_number integer not null,
  brand_name text,
  distributor_code text,
  customer_key text,
  sales_rep_code text,
  week_1 text,
  week_2 text,
  week_3 text,
  week_4 text,
  week_5 text
);

create index if not exists staging_route_plans_import_idx
  on staging_route_plans (import_id);

alter table planner_route_plans enable row level security;
alter table planner_route_visits enable row level security;
alter table planner_plans enable row level security;
alter table planner_plan_weeks enable row level security;
alter table planner_plan_lines enable row level security;
alter table staging_route_plans enable row level security;

revoke all on staging_route_plans from public, anon, authenticated;

drop policy if exists planner_route_plans_read_authorized on planner_route_plans;
create policy planner_route_plans_read_authorized on planner_route_plans
  for select to authenticated
  using (distributor_id in (select current_user_distributor_ids()));

drop policy if exists planner_route_visits_read_authorized on planner_route_visits;
create policy planner_route_visits_read_authorized on planner_route_visits
  for select to authenticated
  using (
    route_plan_id in (
      select rp.id
      from planner_route_plans rp
      where rp.distributor_id in (select current_user_distributor_ids())
    )
  );

drop policy if exists planner_plans_read_authorized on planner_plans;
create policy planner_plans_read_authorized on planner_plans
  for select to authenticated
  using (distributor_id in (select current_user_distributor_ids()));

drop policy if exists planner_plan_weeks_read_authorized on planner_plan_weeks;
create policy planner_plan_weeks_read_authorized on planner_plan_weeks
  for select to authenticated
  using (
    plan_id in (
      select p.id
      from planner_plans p
      where p.distributor_id in (select current_user_distributor_ids())
    )
  );

drop policy if exists planner_plan_lines_read_authorized on planner_plan_lines;
create policy planner_plan_lines_read_authorized on planner_plan_lines
  for select to authenticated
  using (
    plan_id in (
      select p.id
      from planner_plans p
      where p.distributor_id in (select current_user_distributor_ids())
    )
  );

grant select on planner_route_plans to authenticated;
grant select on planner_route_visits to authenticated;
grant select on planner_plans to authenticated;
grant select on planner_plan_weeks to authenticated;
grant select on planner_plan_lines to authenticated;

insert into file_type_configs (id, code, name, target_table, processing_routine, file_format, status)
values (
  'a3b8c4d2-7e15-4f96-9c21-5d84e7f0a316',
  'ROUTE_PLAN',
  'Roteiro de Visitas (Planner)',
  'planner_route_visits',
  'process_route_plans_staging',
  'xlsx',
  'active'
)
on conflict (code) do update set
  name = excluded.name,
  target_table = excluded.target_table,
  processing_routine = excluded.processing_routine,
  file_format = excluded.file_format,
  status = excluded.status,
  updated_at = now();

-- Parses staged route rows into a new route plan header plus its visits.
-- Customers are resolved by pdv_code or CNPJ digits ("CNPJ/CPF Cliente" in the
-- layout); sellers by code. Any non-empty week cell counts as a visit; repeated
-- marks in the same week collapse into one visit.
create or replace function process_route_plans_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_route_plan_id uuid;
  v_week_count smallint;
  v_visit_count bigint := 0;
  v_processed bigint := 0;
  v_rejected bigint := 0;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_route_plans_staging: import % has no distributor', p_import_id;
  end if;

  create temp table tmp_route_rows on commit drop as
  select
    s.line_number,
    c.id as customer_id,
    sr.id as sales_rep_id,
    s.week_1,
    s.week_2,
    s.week_3,
    s.week_4,
    s.week_5,
    case
      when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
        then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
      when nullif(btrim(coalesce(s.customer_key, '')), '') is null
        then 'missing customer cnpj/cpf'
      when c.id is null
        then 'unknown customer code/cnpj: ' || coalesce(s.customer_key, '<null>')
      when nullif(btrim(coalesce(s.sales_rep_code, '')), '') is null
        then 'missing seller code'
      when sr.id is null
        then 'unknown seller code: ' || coalesce(s.sales_rep_code, '<null>')
    end as rejection_reason
  from staging_route_plans s
  left join lateral (
    select c.id
    from customers c
    where c.distributor_id = v_distributor_id
      and (
        c.pdv_code = btrim(s.customer_key)
        or (
          regexp_replace(coalesce(s.customer_key, ''), '\D', '', 'g') <> ''
          and (
            regexp_replace(coalesce(c.pdv_code, ''), '\D', '', 'g') =
              regexp_replace(coalesce(s.customer_key, ''), '\D', '', 'g')
            or regexp_replace(coalesce(c.cnpj, ''), '\D', '', 'g') =
              regexp_replace(coalesce(s.customer_key, ''), '\D', '', 'g')
          )
        )
      )
    order by c.created_at, c.id
    limit 1
  ) c on true
  left join lateral (
    select sr.id
    from sales_reps sr
    where sr.distributor_id = v_distributor_id
      and sr.code = btrim(s.sales_rep_code)
    order by sr.created_at, sr.id
    limit 1
  ) sr on true
  where s.import_id = p_import_id;

  insert into file_import_logs (import_id, line_number, level, message)
  select p_import_id, line_number, 'error'::import_log_level, rejection_reason
  from tmp_route_rows
  where rejection_reason is not null;

  select count(*) into v_rejected from tmp_route_rows where rejection_reason is not null;
  select count(*) into v_processed from tmp_route_rows where rejection_reason is null;

  create temp table tmp_route_visits on commit drop as
  select r.customer_id, r.sales_rep_id, week_mark.week_number
  from tmp_route_rows r
  cross join lateral (
    values
      (1::smallint, r.week_1),
      (2::smallint, r.week_2),
      (3::smallint, r.week_3),
      (4::smallint, r.week_4),
      (5::smallint, r.week_5)
  ) as week_mark(week_number, mark)
  where r.rejection_reason is null
    and nullif(btrim(coalesce(week_mark.mark, '')), '') is not null;

  select coalesce(greatest(3, max(week_number)), 3), count(*)
  into v_week_count, v_visit_count
  from tmp_route_visits;

  -- Large files are split into parts and each part calls this function once
  -- (and SQS may redeliver a part): reuse this import's header instead of
  -- creating one per invocation, and never promote an empty header to be the
  -- distributor's active route.
  select rp.id
  into v_route_plan_id
  from planner_route_plans rp
  where rp.import_id = p_import_id
  order by rp.created_at, rp.id
  limit 1;

  if v_visit_count > 0 then
    if v_route_plan_id is null then
      insert into planner_route_plans (distributor_id, week_count, import_id)
      values (v_distributor_id, v_week_count, p_import_id)
      returning id into v_route_plan_id;
    else
      update planner_route_plans
      set week_count = greatest(week_count, v_week_count)
      where id = v_route_plan_id;
    end if;

    insert into planner_route_visits (route_plan_id, customer_id, sales_rep_id, week_number)
    select distinct on (customer_id, week_number)
      v_route_plan_id, customer_id, sales_rep_id, week_number
    from tmp_route_visits
    order by customer_id, week_number, sales_rep_id nulls last
    on conflict (route_plan_id, customer_id, week_number) do nothing;
  elsif v_route_plan_id is null and v_processed > 0 then
    insert into file_import_logs (import_id, level, message)
    values (p_import_id, 'warning', 'no visits marked in file');
  end if;

  drop table if exists tmp_route_rows;
  drop table if exists tmp_route_visits;

  delete from staging_route_plans where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
end;
$$;

revoke execute on function process_route_plans_staging(uuid) from public, anon, authenticated;
