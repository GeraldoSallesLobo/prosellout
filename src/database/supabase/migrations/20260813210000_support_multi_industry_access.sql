-- Multi-industry access: one portal login can now be linked to several
-- distributor records (each one representing a distributor × industry pair).
-- Admins manage users and their links separately: create_portal_user replaces
-- create_distributor_user (which created distributor + user as an atomic 1:1),
-- and grant/revoke functions manage links to already registered distributors.

alter table distributor_users drop constraint distributor_users_user_id_key;

-- Registering distributors becomes an admin action on Cadastros › Distribuidor
-- (create_distributor_user was the only insert path before and is dropped
-- below; the table had no insert policy, so the screen only worked in demo).
create policy distributors_insert_admin on distributors
  for insert to authenticated
  with check (current_user_is_admin());

create or replace function create_portal_user(
  p_email text,
  p_password text,
  p_distributor_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid := gen_random_uuid();
  v_identity_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_distributor_ids uuid[];
begin
  if not current_user_is_admin() then
    raise exception 'Admin access required';
  end if;

  if v_email = '' or v_email !~ '^[^@]+@[^@]+\.[^@]+$' then
    raise exception 'Invalid email';
  end if;

  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must have at least 6 characters';
  end if;

  select array_agg(distinct requested.id)
  into v_distributor_ids
  from unnest(coalesce(p_distributor_ids, '{}'::uuid[])) as requested(id);

  if v_distributor_ids is null then
    raise exception 'At least one distributor is required';
  end if;

  if exists (
    select 1
    from unnest(v_distributor_ids) as requested(id)
    left join distributors d on d.id = requested.id and d.status = 'active'
    where d.id is null
  ) then
    raise exception 'All distributors must exist and be active';
  end if;

  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    raise exception 'Email already exists';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin
  ) values (
    v_user_id, '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', v_email,
    crypt(p_password, gen_salt('bf')),
    now(), '', '', '', '', now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('email_verified', true),
    false
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    v_identity_id, v_user_id, v_user_id::text,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email', now(), now(), now()
  );

  insert into distributor_users (user_id, distributor_id, role, status)
  select v_user_id, linked.id, 'owner', 'active'
  from unnest(v_distributor_ids) as linked(id);

  return v_user_id;
end;
$$;

create or replace function grant_distributor_access(
  p_user_id uuid,
  p_distributor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not current_user_is_admin() then
    raise exception 'Admin access required';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'User not found';
  end if;

  if exists (
    select 1 from admin_users au
    where au.user_id = p_user_id and au.status = 'active'
  ) then
    raise exception 'Admins already have access to every distributor';
  end if;

  if not exists (
    select 1 from distributors d
    where d.id = p_distributor_id and d.status = 'active'
  ) then
    raise exception 'Distributor must exist and be active';
  end if;

  insert into distributor_users (user_id, distributor_id, role, status)
  values (p_user_id, p_distributor_id, 'owner', 'active')
  on conflict (user_id, distributor_id)
  do update set status = 'active';
end;
$$;

create or replace function revoke_distributor_access(
  p_user_id uuid,
  p_distributor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not current_user_is_admin() then
    raise exception 'Admin access required';
  end if;

  update distributor_users
  set status = 'inactive'
  where user_id = p_user_id
    and distributor_id = p_distributor_id;

  if not found then
    raise exception 'Distributor access not found';
  end if;
end;
$$;

-- Rows come one per link; order by email first so the frontend can group the
-- links of each user.
create or replace function list_distributor_users()
returns table (
  user_id uuid,
  email text,
  distributor_id uuid,
  distributor_code text,
  distributor_name text,
  status entity_status,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not current_user_is_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select
    du.user_id,
    u.email::text,
    d.id,
    d.code,
    d.name,
    du.status,
    du.created_at
  from distributor_users du
  join distributors d on d.id = du.distributor_id
  join auth.users u on u.id = du.user_id
  order by u.email, d.name;
end;
$$;

drop function create_distributor_user(text, text, text, text, text, text, text);

revoke execute on function create_portal_user(text, text, uuid[]) from public, anon;
revoke execute on function grant_distributor_access(uuid, uuid) from public, anon;
revoke execute on function revoke_distributor_access(uuid, uuid) from public, anon;

grant execute on function create_portal_user(text, text, uuid[]) to authenticated;
grant execute on function grant_distributor_access(uuid, uuid) to authenticated;
grant execute on function revoke_distributor_access(uuid, uuid) to authenticated;
