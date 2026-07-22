create or replace function ensure_platform_deletion_log_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sequence_name text := pg_get_serial_sequence('platform_data_deletion_logs', 'id');
  v_next_id bigint;
begin
  perform pg_advisory_xact_lock(hashtext('platform_data_deletion_logs_identity'));

  if v_sequence_name is null then
    return new;
  end if;

  if new.id is null or exists (
    select 1
    from platform_data_deletion_logs log
    where log.id = new.id
  ) then
    select coalesce(max(log.id), 0) + 1
    into v_next_id
    from platform_data_deletion_logs log;

    perform setval(v_sequence_name::regclass, v_next_id, false);
    new.id := nextval(v_sequence_name::regclass);
  end if;

  return new;
end;
$$;

drop trigger if exists platform_data_deletion_logs_identity_guard
  on platform_data_deletion_logs;

create trigger platform_data_deletion_logs_identity_guard
  before insert on platform_data_deletion_logs
  for each row execute function ensure_platform_deletion_log_identity();

do $$
declare
  v_sequence_name text := pg_get_serial_sequence('platform_data_deletion_logs', 'id');
  v_next_id bigint;
begin
  if v_sequence_name is not null then
    select coalesce(max(log.id), 0) + 1
    into v_next_id
    from platform_data_deletion_logs log;

    perform setval(v_sequence_name::regclass, v_next_id, false);
  end if;
end;
$$;

revoke execute on function ensure_platform_deletion_log_identity()
  from public, anon, authenticated;
