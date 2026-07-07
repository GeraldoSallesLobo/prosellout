-- RLS hardening — closes three gaps left by 20260705000800_rls.sql.
--
-- 1. Report functions are SECURITY DEFINER (bypass RLS) and Postgres grants
--    EXECUTE to PUBLIC by default. The previous migration granted them to
--    authenticated but never revoked PUBLIC/anon, so an unauthenticated
--    caller holding only the anon key could read all business data via RPC.
--
-- 2. mv_sell_out_daily is a materialized view: RLS does not apply to it and
--    Supabase's default privileges expose it through the API to anon and
--    authenticated. Reports reach it through SECURITY DEFINER functions, so
--    no API role needs direct access.
--
-- 3. sell_out/sell_in partitions are created dynamically without RLS. Parent
--    policies do NOT apply when a partition is queried directly, so
--    PostgREST exposed each partition (sell_out_202607, ...) with default
--    grants, bypassing the parent's row security.

-- ---------------------------------------------------------------------------
-- 1. Functions: strip the default PUBLIC/anon EXECUTE.
--    Portal users keep the grants added in 20260705000800_rls.sql.
-- ---------------------------------------------------------------------------

revoke execute on function report_status_mtd from public, anon;
revoke execute on function report_status_analysis from public, anon;
revoke execute on function report_evolution_weekly from public, anon;
revoke execute on function report_three_month_history from public, anon;
revoke execute on function report_evolution_analysis from public, anon;
revoke execute on function report_fast_facts from public, anon;
revoke execute on function fn_sell_out_metrics from public, anon;
revoke execute on function fn_target_metrics from public, anon;
revoke execute on function fn_customer_count from public, anon;

-- Internal helpers: no API role ever needs to call these directly.
revoke execute on function fn_fast_facts_dimension from public, anon, authenticated;
revoke execute on function fn_safe_div from public, anon, authenticated;
revoke execute on function fn_ratio from public, anon, authenticated;
revoke execute on function fn_is_numeric from public, anon, authenticated;
revoke execute on function fn_is_iso_date from public, anon, authenticated;
revoke execute on function set_updated_at from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Materialized view: remove API access entirely.
-- ---------------------------------------------------------------------------

revoke all on mv_sell_out_daily from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Partitions: enable RLS on existing ones and on every future one.
--    With RLS enabled and no policies, direct access by anon/authenticated
--    is denied; reads through the parent keep working under the parent's
--    policies (partition policies are not consulted on that path).
-- ---------------------------------------------------------------------------

do $$
declare
  v_partition text;
begin
  for v_partition in
    select child.relname
    from pg_inherits
    join pg_class parent on parent.oid = pg_inherits.inhparent
    join pg_class child on child.oid = pg_inherits.inhrelid
    where parent.relname in ('sell_out', 'sell_in')
  loop
    execute format('alter table %I enable row level security', v_partition);
    execute format('revoke all on %I from public, anon, authenticated', v_partition);
  end loop;
end;
$$;

-- Recreate ensure_month_partition so new partitions are born locked down.
create or replace function ensure_month_partition(p_table text, p_month date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start date := date_trunc('month', p_month)::date;
  v_end date := (v_start + interval '1 month')::date;
  v_partition text := format('%s_%s', p_table, to_char(v_start, 'YYYYMM'));
begin
  if p_table not in ('sell_out', 'sell_in') then
    raise exception 'ensure_month_partition: unsupported table %', p_table;
  end if;

  if not exists (select 1 from pg_class where relname = v_partition) then
    execute format(
      'create table if not exists %I partition of %I for values from (%L) to (%L)',
      v_partition, p_table, v_start, v_end
    );
    execute format('alter table %I enable row level security', v_partition);
    execute format('revoke all on %I from public, anon, authenticated', v_partition);
  end if;
end;
$$;
