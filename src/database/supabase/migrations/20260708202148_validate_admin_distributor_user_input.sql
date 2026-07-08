create or replace function create_distributor_user(
  p_email text,
  p_password text,
  p_distributor_code text,
  p_distributor_name text,
  p_distributor_cnpj text default null,
  p_city text default null,
  p_state text default null
)
returns table (
  user_id uuid,
  distributor_id uuid
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid := gen_random_uuid();
  v_identity_id uuid := gen_random_uuid();
  v_distributor_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_distributor_code text := upper(trim(p_distributor_code));
  v_cnpj text := nullif(regexp_replace(coalesce(p_distributor_cnpj, ''), '\D', '', 'g'), '');
  v_state text := nullif(upper(trim(coalesce(p_state, ''))), '');
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

  if nullif(v_distributor_code, '') is null then
    raise exception 'Distributor code is required';
  end if;

  if v_distributor_code !~ '^[A-Z0-9_-]{3,32}$' then
    raise exception 'Distributor code must have 3 to 32 uppercase letters, numbers, underscores, or hyphens';
  end if;

  if nullif(trim(p_distributor_name), '') is null then
    raise exception 'Distributor name is required';
  end if;

  if v_cnpj is not null and length(v_cnpj) <> 14 then
    raise exception 'Distributor CNPJ must have 14 digits';
  end if;

  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    raise exception 'Email already exists';
  end if;

  if exists (select 1 from distributors d where d.code = v_distributor_code) then
    raise exception 'Distributor code already exists';
  end if;

  if v_cnpj is not null and exists (select 1 from distributors d where d.cnpj = v_cnpj) then
    raise exception 'Distributor CNPJ already exists';
  end if;

  insert into distributors (id, code, name, cnpj, city, state, status)
  values (
    v_distributor_id,
    v_distributor_code,
    trim(p_distributor_name),
    v_cnpj,
    nullif(trim(coalesce(p_city, '')), ''),
    v_state,
    'active'
  );

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
  values (v_user_id, v_distributor_id, 'owner', 'active');

  return query select v_user_id, v_distributor_id;
end;
$$;

revoke execute on function create_distributor_user(text, text, text, text, text, text, text) from public, anon;
grant execute on function create_distributor_user(text, text, text, text, text, text, text) to authenticated;
