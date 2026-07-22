create or replace function current_user_distributor_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select d.id
  from distributors d
  where current_user_is_admin()
  union
  select du.distributor_id
  from distributor_users du
  join distributors d on d.id = du.distributor_id
  where du.user_id = auth.uid()
    and du.status = 'active'
    and d.status = 'active'
$$;

revoke execute on function current_user_distributor_ids()
  from public, anon;

grant execute on function current_user_distributor_ids()
  to authenticated;
