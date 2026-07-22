create or replace function set_distributor_status(
  p_distributor_id uuid,
  p_status entity_status
)
returns table (
  affected_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_affected_count bigint := 0;
  v_admin_user_id uuid := auth.uid();
  v_admin_email text;
  v_distributor_refs jsonb := '[]'::jsonb;
begin
  if not current_user_is_admin() then
    raise exception 'Admin access required';
  end if;

  if p_status not in ('active'::entity_status, 'inactive'::entity_status) then
    raise exception 'Unsupported distributor status: %', p_status;
  end if;

  select u.email::text
  into v_admin_email
  from auth.users u
  where u.id = v_admin_user_id;

  select coalesce(
    jsonb_agg(jsonb_build_object(
      'id', d.id,
      'code', d.code,
      'name', d.name,
      'cnpj', d.cnpj
    )),
    '[]'::jsonb
  )
  into v_distributor_refs
  from distributors d
  where d.id = p_distributor_id;

  if jsonb_array_length(v_distributor_refs) = 0 then
    raise exception 'Distributor not found';
  end if;

  update distributors d
  set status = p_status
  where d.id = p_distributor_id
    and d.status <> p_status;

  get diagnostics v_affected_count = row_count;

  update distributor_users du
  set status = p_status
  where du.distributor_id = p_distributor_id
    and du.status <> p_status;

  insert into platform_data_deletion_logs (
    admin_user_id,
    admin_email,
    dataset,
    filters,
    deleted_count
  ) values (
    v_admin_user_id,
    v_admin_email,
    'distributors',
    jsonb_strip_nulls(
      jsonb_build_object(
        'action', case
          when p_status = 'active'::entity_status then 'activate'
          else 'inactivate'
        end,
        'distributor_id', p_distributor_id,
        'status', p_status,
        'distributors', v_distributor_refs
      )
    ),
    v_affected_count
  );

  return query select v_affected_count;
end;
$$;

create or replace function inactivate_distributor(
  p_distributor_id uuid
)
returns table (
  affected_count bigint
)
language sql
security definer
set search_path = public
as $$
  select affected_count
  from set_distributor_status(p_distributor_id, 'inactive'::entity_status)
$$;

revoke execute on function set_distributor_status(uuid, entity_status)
  from public, anon;

revoke execute on function inactivate_distributor(uuid)
  from public, anon;

grant execute on function set_distributor_status(uuid, entity_status)
  to authenticated;

grant execute on function inactivate_distributor(uuid)
  to authenticated;
