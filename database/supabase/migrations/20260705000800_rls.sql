-- Row Level Security.
--
-- Portal users (authenticated) can read everything and manage master data and
-- import records. High-volume tables are written only by the AWS ETL through
-- the service role, which bypasses RLS. Staging tables have no policies at
-- all: they are reachable exclusively by the service role.

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'distributors', 'channels', 'clusters', 'product_hierarchy', 'products',
    'sales_reps', 'customers', 'file_type_configs', 'file_imports',
    'file_import_logs', 'sell_out', 'sell_in', 'stock_snapshots',
    'sales_targets', 'staging_sell_out', 'staging_sell_in'
  ]
  loop
    execute format('alter table %I enable row level security', v_table);
  end loop;
end;
$$;

-- Master data: full management from the portal.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'distributors', 'channels', 'clusters', 'product_hierarchy', 'products',
    'sales_reps', 'customers', 'file_type_configs'
  ]
  loop
    execute format(
      'create policy %I on %I for select to authenticated using (true)',
      v_table || '_read', v_table
    );
    execute format(
      'create policy %I on %I for insert to authenticated with check (true)',
      v_table || '_insert', v_table
    );
    execute format(
      'create policy %I on %I for update to authenticated using (true) with check (true)',
      v_table || '_update', v_table
    );
    execute format(
      'create policy %I on %I for delete to authenticated using (true)',
      v_table || '_delete', v_table
    );
  end loop;
end;
$$;

-- Transactional data: read-only from the portal.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['sell_out', 'sell_in', 'stock_snapshots', 'sales_targets']
  loop
    execute format(
      'create policy %I on %I for select to authenticated using (true)',
      v_table || '_read', v_table
    );
  end loop;
end;
$$;

-- Imports: users register uploads and follow progress; status transitions are
-- performed by the ETL (service role).
create policy file_imports_read on file_imports
  for select to authenticated using (true);

create policy file_imports_insert on file_imports
  for insert to authenticated with check (imported_by = auth.uid());

create policy file_import_logs_read on file_import_logs
  for select to authenticated using (true);

-- Function execution: reports for portal users; ETL entry points restricted
-- to the service role (execute is granted to public by default — revoke it).
grant execute on function report_status_mtd to authenticated;
grant execute on function report_status_analysis to authenticated;
grant execute on function report_evolution_weekly to authenticated;
grant execute on function report_three_month_history to authenticated;
grant execute on function report_evolution_analysis to authenticated;
grant execute on function report_fast_facts to authenticated;
grant execute on function fn_sell_out_metrics to authenticated;
grant execute on function fn_target_metrics to authenticated;

revoke execute on function process_sell_out_staging from public, anon, authenticated;
revoke execute on function process_sell_in_staging from public, anon, authenticated;
revoke execute on function finish_file_import from public, anon, authenticated;
revoke execute on function ensure_month_partition from public, anon, authenticated;
revoke execute on function refresh_report_views from public, anon, authenticated;
