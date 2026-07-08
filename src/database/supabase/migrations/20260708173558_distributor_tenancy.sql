create type distributor_user_role as enum ('owner', 'admin', 'member');

create table distributor_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  distributor_id uuid not null references distributors(id) on delete cascade,
  role distributor_user_role not null default 'owner',
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id),
  unique (user_id, distributor_id)
);

create index distributor_users_distributor_idx on distributor_users (distributor_id);

create trigger distributor_users_set_updated_at
  before update on distributor_users
  for each row execute function set_updated_at();

alter table distributor_users enable row level security;

create policy distributor_users_read_own on distributor_users
  for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function current_user_distributor_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select du.distributor_id
  from distributor_users du
  where du.user_id = auth.uid()
    and du.status = 'active'
$$;

create or replace function resolve_authorized_distributor_id(p_distributor_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_distributor_id is not null then
    select du.distributor_id
    into v_distributor_id
    from distributor_users du
    where du.user_id = auth.uid()
      and du.distributor_id = p_distributor_id
      and du.status = 'active';

    if v_distributor_id is null then
      raise exception 'Unauthorized distributor';
    end if;

    return v_distributor_id;
  end if;

  select du.distributor_id
  into v_distributor_id
  from distributor_users du
  where du.user_id = auth.uid()
    and du.status = 'active'
  order by du.created_at
  limit 1;

  if v_distributor_id is null then
    raise exception 'No distributor linked to current user';
  end if;

  return v_distributor_id;
end;
$$;

create or replace function get_current_distributor()
returns table (
  id uuid,
  code text,
  name text,
  cnpj text
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.code, d.name, d.cnpj
  from distributors d
  where d.id = resolve_authorized_distributor_id(null)
$$;

grant select on distributor_users to authenticated;

revoke execute on function current_user_distributor_ids from public, anon;
revoke execute on function resolve_authorized_distributor_id(uuid) from public, anon;
revoke execute on function get_current_distributor from public, anon;

grant execute on function current_user_distributor_ids to authenticated;
grant execute on function resolve_authorized_distributor_id(uuid) to authenticated;
grant execute on function get_current_distributor to authenticated;
