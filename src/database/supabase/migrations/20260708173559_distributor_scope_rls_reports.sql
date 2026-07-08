-- Scope the remaining business data by distributor and replace permissive RLS
-- with tenant-aware policies. Existing global rows can only be backfilled
-- automatically when the database has exactly one distributor.

alter table channels add column if not exists distributor_id uuid references distributors(id);
alter table clusters add column if not exists distributor_id uuid references distributors(id);
alter table product_hierarchy add column if not exists distributor_id uuid references distributors(id);
alter table sales_targets add column if not exists distributor_id uuid references distributors(id);
alter table file_imports add column if not exists distributor_id uuid references distributors(id);

do $$
declare
  v_distributor_id uuid;
  v_distributor_count integer;
begin
  select count(*) into v_distributor_count from distributors;

  if v_distributor_count = 1 then
    select id
    into v_distributor_id
    from distributors
    order by created_at, id::text
    limit 1;

    update channels set distributor_id = v_distributor_id where distributor_id is null;
    update clusters set distributor_id = v_distributor_id where distributor_id is null;
    update product_hierarchy set distributor_id = v_distributor_id where distributor_id is null;
    update file_imports set distributor_id = v_distributor_id where distributor_id is null;
  elsif exists (select 1 from channels)
    or exists (select 1 from clusters)
    or exists (select 1 from product_hierarchy)
    or exists (select 1 from file_imports)
  then
    raise exception 'Cannot backfill distributor-scoped tables when multiple distributors already exist';
  end if;
end;
$$;

update sales_targets st
set distributor_id = c.distributor_id
from customers c
where st.customer_id = c.id
  and st.distributor_id is null;

alter table channels alter column distributor_id set not null;
alter table clusters alter column distributor_id set not null;
alter table product_hierarchy alter column distributor_id set not null;
alter table products alter column distributor_id set not null;
alter table sales_reps alter column distributor_id set not null;
alter table customers alter column distributor_id set not null;
alter table sales_targets alter column distributor_id set not null;
alter table file_imports alter column distributor_id set not null;

alter table channels drop constraint channels_name_key;
alter table channels add constraint channels_distributor_name_key unique (distributor_id, name);

alter table clusters drop constraint clusters_name_key;
alter table clusters add constraint clusters_distributor_name_key unique (distributor_id, name);

alter table product_hierarchy drop constraint unique_name_per_parent;
alter table product_hierarchy
  add constraint product_hierarchy_distributor_parent_name_key
  unique nulls not distinct (distributor_id, parent_id, name);

alter table products drop constraint products_ean_key;
alter table products add constraint products_distributor_ean_key unique (distributor_id, ean);

alter table products drop constraint products_sku_code_key;
create unique index products_distributor_sku_code_key
  on products (distributor_id, sku_code)
  where sku_code is not null;

create index channels_distributor_idx on channels (distributor_id);
create index clusters_distributor_idx on clusters (distributor_id);
create index product_hierarchy_distributor_idx on product_hierarchy (distributor_id);
create index products_distributor_idx on products (distributor_id);
create index sales_reps_distributor_idx on sales_reps (distributor_id);
create index sales_targets_distributor_date_idx on sales_targets (distributor_id, target_date);
create index file_imports_distributor_created_idx on file_imports (distributor_id, created_at desc);

create or replace function validate_distributor_relationships()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'product_hierarchy' then
    if new.parent_id is not null and not exists (
      select 1
      from product_hierarchy parent
      where parent.id = new.parent_id
        and parent.distributor_id = new.distributor_id
    ) then
      raise exception 'product_hierarchy parent belongs to another distributor';
    end if;
  elsif tg_table_name = 'products' then
    if not exists (
      select 1
      from product_hierarchy ph
      where ph.id = new.subcategory_id
        and ph.distributor_id = new.distributor_id
    ) then
      raise exception 'product hierarchy belongs to another distributor';
    end if;
  elsif tg_table_name = 'sales_reps' then
    if new.manager_id is not null and not exists (
      select 1
      from sales_reps manager
      where manager.id = new.manager_id
        and manager.distributor_id = new.distributor_id
    ) then
      raise exception 'manager belongs to another distributor';
    end if;

    if new.supervisor_id is not null and not exists (
      select 1
      from sales_reps supervisor
      where supervisor.id = new.supervisor_id
        and supervisor.distributor_id = new.distributor_id
    ) then
      raise exception 'supervisor belongs to another distributor';
    end if;
  elsif tg_table_name = 'customers' then
    if new.channel_id is not null and not exists (
      select 1
      from channels ch
      where ch.id = new.channel_id
        and ch.distributor_id = new.distributor_id
    ) then
      raise exception 'channel belongs to another distributor';
    end if;

    if new.cluster_id is not null and not exists (
      select 1
      from clusters cl
      where cl.id = new.cluster_id
        and cl.distributor_id = new.distributor_id
    ) then
      raise exception 'cluster belongs to another distributor';
    end if;

    if new.sales_rep_id is not null and not exists (
      select 1
      from sales_reps sr
      where sr.id = new.sales_rep_id
        and sr.distributor_id = new.distributor_id
    ) then
      raise exception 'sales rep belongs to another distributor';
    end if;
  elsif tg_table_name = 'file_imports' then
    if new.imported_by is not null and not exists (
      select 1
      from distributor_users du
      where du.user_id = new.imported_by
        and du.distributor_id = new.distributor_id
        and du.status = 'active'
    ) then
      raise exception 'import user is not linked to distributor';
    end if;
  elsif tg_table_name = 'sales_targets' then
    if not exists (
      select 1
      from customers c
      where c.id = new.customer_id
        and c.distributor_id = new.distributor_id
    ) then
      raise exception 'target customer belongs to another distributor';
    end if;

    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'target product belongs to another distributor';
    end if;
  elsif tg_table_name = 'stock_snapshots' then
    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'stock product belongs to another distributor';
    end if;
  elsif tg_table_name = 'sell_out' then
    if not exists (
      select 1
      from customers c
      where c.id = new.customer_id
        and c.distributor_id = new.distributor_id
    ) then
      raise exception 'sell out customer belongs to another distributor';
    end if;

    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'sell out product belongs to another distributor';
    end if;

    if new.sales_rep_id is not null and not exists (
      select 1
      from sales_reps sr
      where sr.id = new.sales_rep_id
        and sr.distributor_id = new.distributor_id
    ) then
      raise exception 'sell out sales rep belongs to another distributor';
    end if;
  elsif tg_table_name = 'sell_in' then
    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'sell in product belongs to another distributor';
    end if;
  end if;

  if tg_table_name in ('sales_targets', 'stock_snapshots', 'sell_out', 'sell_in') then
    if new.import_id is not null then
      if not exists (
        select 1
        from file_imports fi
        where fi.id = new.import_id
          and fi.distributor_id = new.distributor_id
      ) then
        raise exception 'import belongs to another distributor';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger product_hierarchy_validate_distributor
  before insert or update on product_hierarchy
  for each row execute function validate_distributor_relationships();

create trigger products_validate_distributor
  before insert or update on products
  for each row execute function validate_distributor_relationships();

create trigger sales_reps_validate_distributor
  before insert or update on sales_reps
  for each row execute function validate_distributor_relationships();

create trigger customers_validate_distributor
  before insert or update on customers
  for each row execute function validate_distributor_relationships();

create trigger file_imports_validate_distributor
  before insert or update on file_imports
  for each row execute function validate_distributor_relationships();

create trigger sales_targets_validate_distributor
  before insert or update on sales_targets
  for each row execute function validate_distributor_relationships();

create trigger stock_snapshots_validate_distributor
  before insert or update on stock_snapshots
  for each row execute function validate_distributor_relationships();

create trigger sell_out_validate_distributor
  before insert or update on sell_out
  for each row execute function validate_distributor_relationships();

create trigger sell_in_validate_distributor
  before insert or update on sell_in
  for each row execute function validate_distributor_relationships();

do $$
declare
  v_table text;
  v_policy text;
begin
  foreach v_table in array array[
    'distributors', 'channels', 'clusters', 'product_hierarchy', 'products',
    'sales_reps', 'customers', 'file_type_configs', 'file_imports',
    'file_import_logs', 'sell_out', 'sell_in', 'stock_snapshots',
    'sales_targets'
  ]
  loop
    for v_policy in
      select policyname
      from pg_policies
      where schemaname = 'public'
        and tablename = v_table
    loop
      execute format('drop policy if exists %I on %I', v_policy, v_table);
    end loop;
  end loop;
end;
$$;

create policy distributors_read_authorized on distributors
  for select to authenticated
  using (id in (select current_user_distributor_ids()));

create policy distributors_update_authorized on distributors
  for update to authenticated
  using (id in (select current_user_distributor_ids()))
  with check (id in (select current_user_distributor_ids()));

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'channels', 'clusters', 'product_hierarchy', 'products',
    'sales_reps', 'customers'
  ]
  loop
    execute format(
      'create policy %I on %I for select to authenticated using (distributor_id in (select current_user_distributor_ids()))',
      v_table || '_read_authorized', v_table
    );
    execute format(
      'create policy %I on %I for insert to authenticated with check (distributor_id in (select current_user_distributor_ids()))',
      v_table || '_insert_authorized', v_table
    );
    execute format(
      'create policy %I on %I for update to authenticated using (distributor_id in (select current_user_distributor_ids())) with check (distributor_id in (select current_user_distributor_ids()))',
      v_table || '_update_authorized', v_table
    );
    execute format(
      'create policy %I on %I for delete to authenticated using (distributor_id in (select current_user_distributor_ids()))',
      v_table || '_delete_authorized', v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array['sell_out', 'sell_in', 'stock_snapshots', 'sales_targets']
  loop
    execute format(
      'create policy %I on %I for select to authenticated using (distributor_id in (select current_user_distributor_ids()))',
      v_table || '_read_authorized', v_table
    );
  end loop;
end;
$$;

create policy file_imports_read_authorized on file_imports
  for select to authenticated
  using (distributor_id in (select current_user_distributor_ids()));

create policy file_imports_insert_authorized on file_imports
  for insert to authenticated
  with check (
    imported_by = (select auth.uid())
    and distributor_id in (select current_user_distributor_ids())
  );

create policy file_import_logs_read_authorized on file_import_logs
  for select to authenticated
  using (
    exists (
      select 1
      from file_imports fi
      where fi.id = file_import_logs.import_id
        and fi.distributor_id in (select current_user_distributor_ids())
    )
  );

create policy file_type_configs_read on file_type_configs
  for select to authenticated using (true);

revoke insert, update, delete on file_type_configs from authenticated;
grant select on file_type_configs to authenticated;

create or replace function fn_sell_out_metrics(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric,
  total_cost numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(so.gross_value), 0)::numeric,
    coalesce(sum(so.quantity), 0)::numeric,
    coalesce(sum(so.quantity * coalesce(so.unit_cost, 0)), 0)::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  left join sales_reps sr on sr.id = so.sales_rep_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id = resolve_authorized_distributor_id(p_distributor_id)
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

drop function if exists fn_target_metrics(
  date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
);

create function fn_target_metrics(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric,
  coverage bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(t.gross_value), 0)::numeric,
    coalesce(sum(t.quantity), 0)::numeric,
    count(distinct t.customer_id)
  from sales_targets t
  join products p on p.id = t.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = t.customer_id
  left join sales_reps sr on sr.id = c.sales_rep_id
  where t.target_date between p_start and p_end
    and t.distributor_id = resolve_authorized_distributor_id(p_distributor_id)
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or t.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or c.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

drop function if exists fn_customer_count(uuid, uuid, uuid, uuid);

create function fn_customer_count(
  p_distributor_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from customers c
  left join sales_reps sr on sr.id = c.sales_rep_id
  where c.status = 'active'
    and c.distributor_id = resolve_authorized_distributor_id(p_distributor_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or c.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function report_status_mtd(
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_cur record;
  v_prev record;
  v_tgt record;
  v_total_days integer;
  v_elapsed_days integer;
  v_projected_value numeric;
  v_cur_ticket numeric;
  v_prev_ticket numeric;
  v_tgt_ticket numeric;
  v_pdv_count bigint;
begin
  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);

  select * into v_cur from fn_sell_out_metrics(
    p_current_start, p_current_end, v_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev from fn_sell_out_metrics(
    p_previous_start, p_previous_end, v_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_tgt from fn_target_metrics(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    v_distributor_id, p_macro_category_id, p_category_id, p_subcategory_id,
    p_product_id, p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  v_total_days := p_current_end - p_current_start + 1;
  v_elapsed_days := greatest(1, least(current_date, p_current_end) - p_current_start + 1);
  v_projected_value := fn_safe_div(v_cur.total_value, v_elapsed_days) * v_total_days;
  v_cur_ticket := fn_safe_div(v_cur.total_value, v_cur.coverage::numeric);
  v_prev_ticket := fn_safe_div(v_prev.total_value, v_prev.coverage::numeric);
  v_tgt_ticket := fn_safe_div(v_tgt.total_value, v_tgt.coverage::numeric);
  v_pdv_count := fn_customer_count(v_distributor_id, p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  return jsonb_build_object(
    'sell_out_value', jsonb_build_object(
      'current', v_cur.total_value,
      'target', v_tgt.total_value,
      'previous', v_prev.total_value,
      'current_vs_target', fn_ratio(v_cur.total_value, v_tgt.total_value),
      'previous_vs_target', fn_ratio(v_prev.total_value, v_tgt.total_value)
    ),
    'sell_out_quantity', jsonb_build_object(
      'current', v_cur.total_quantity,
      'target', v_tgt.total_quantity,
      'previous', v_prev.total_quantity,
      'current_vs_target', fn_ratio(v_cur.total_quantity, v_tgt.total_quantity),
      'previous_vs_target', fn_ratio(v_prev.total_quantity, v_tgt.total_quantity)
    ),
    'coverage', jsonb_build_object(
      'current', v_cur.coverage,
      'target', v_tgt.coverage,
      'previous', v_prev.coverage,
      'current_vs_target', fn_ratio(v_cur.coverage::numeric, v_tgt.coverage::numeric),
      'previous_vs_target', fn_ratio(v_prev.coverage::numeric, v_tgt.coverage::numeric)
    ),
    'avg_ticket', jsonb_build_object(
      'current', v_cur_ticket,
      'target', v_tgt_ticket,
      'previous', v_prev_ticket,
      'current_vs_target', fn_ratio(v_cur_ticket, v_tgt_ticket),
      'previous_vs_target', fn_ratio(v_prev_ticket, v_tgt_ticket)
    ),
    'drop_size', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_quantity, v_cur.invoice_count::numeric),
      'target', fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric),
      'previous', fn_safe_div(v_prev.total_quantity, v_prev.invoice_count::numeric),
      'current_vs_target', fn_ratio(
        fn_safe_div(v_cur.total_quantity, v_cur.invoice_count::numeric),
        fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric)),
      'previous_vs_target', fn_ratio(
        fn_safe_div(v_prev.total_quantity, v_prev.invoice_count::numeric),
        fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric))
    ),
    'avg_price', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value, v_cur.total_quantity),
      'target', fn_safe_div(v_tgt.total_value, v_tgt.total_quantity),
      'previous', fn_safe_div(v_prev.total_value, v_prev.total_quantity),
      'current_vs_target', fn_ratio(
        fn_safe_div(v_cur.total_value, v_cur.total_quantity),
        fn_safe_div(v_tgt.total_value, v_tgt.total_quantity)),
      'previous_vs_target', fn_ratio(
        fn_safe_div(v_prev.total_value, v_prev.total_quantity),
        fn_safe_div(v_tgt.total_value, v_tgt.total_quantity))
    ),
    'markup_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value - v_cur.total_cost, v_cur.total_cost),
      'previous', fn_safe_div(v_prev.total_value - v_prev.total_cost, v_prev.total_cost)
    ),
    'margin_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value - v_cur.total_cost, v_cur.total_value),
      'previous', fn_safe_div(v_prev.total_value - v_prev.total_cost, v_prev.total_value)
    ),
    'trend_value', jsonb_build_object(
      'projected', v_projected_value,
      'projected_vs_target', fn_ratio(v_projected_value, v_tgt.total_value)
    ),
    'probability_value', coalesce(fn_safe_div(v_cur.total_value, v_tgt.total_value), 0),
    'probability_coverage', coalesce(fn_safe_div(v_cur.coverage::numeric, v_pdv_count::numeric), 0),
    'probability_ticket', coalesce(fn_safe_div(v_cur_ticket, v_tgt_ticket), 0),
    'period', jsonb_build_object(
      'total_days', v_total_days,
      'elapsed_days', v_elapsed_days,
      'pdv_count', v_pdv_count
    )
  );
end;
$$;

create or replace function report_status_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null
)
returns table (
  group_id uuid,
  group_name text,
  current_value numeric,
  target_value numeric,
  current_vs_target numeric,
  previous_value numeric,
  previous_vs_target numeric,
  coverage bigint,
  avg_ticket numeric,
  drop_size numeric,
  avg_price numeric,
  markup_pct numeric,
  margin_pct numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
begin
  if p_group_by not in ('seller', 'category', 'channel') then
    raise exception 'report_status_analysis: invalid p_group_by %', p_group_by;
  end if;

  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);

  return query
  with cur as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(so.gross_value) as v_value,
      sum(so.quantity) as v_quantity,
      sum(so.quantity * coalesce(so.unit_cost, 0)) as v_cost,
      count(distinct so.customer_id) as v_coverage,
      count(distinct so.invoice_number) as v_invoices
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_current_start and p_current_end
      and so.distributor_id = v_distributor_id
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  prev as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(so.gross_value) as v_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_previous_start and p_previous_end
      and so.distributor_id = v_distributor_id
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  tgt as (
    select
      case p_group_by
        when 'seller' then c.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(t.gross_value) as v_value
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = t.customer_id
    where t.target_date between coalesce(p_target_start, p_current_start)
      and coalesce(p_target_end, p_current_end)
      and t.distributor_id = v_distributor_id
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or t.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  keys as (
    select cur.gid from cur
    union
    select prev.gid from prev
    union
    select tgt.gid from tgt
  )
  select
    k.gid,
    coalesce(sr.name, ph.name, ch.name, '-'),
    coalesce(cur.v_value, 0),
    tgt.v_value,
    fn_ratio(coalesce(cur.v_value, 0), tgt.v_value),
    coalesce(prev.v_value, 0),
    fn_ratio(coalesce(prev.v_value, 0), tgt.v_value),
    coalesce(cur.v_coverage, 0),
    fn_safe_div(cur.v_value, cur.v_coverage::numeric),
    fn_safe_div(cur.v_quantity, cur.v_invoices::numeric),
    fn_safe_div(cur.v_value, cur.v_quantity),
    fn_safe_div(cur.v_value - cur.v_cost, cur.v_cost),
    fn_safe_div(cur.v_value - cur.v_cost, cur.v_value)
  from keys k
  left join cur on cur.gid = k.gid
  left join prev on prev.gid = k.gid
  left join tgt on tgt.gid = k.gid
  left join sales_reps sr on p_group_by = 'seller' and sr.id = k.gid
  left join product_hierarchy ph on p_group_by = 'category' and ph.id = k.gid
  left join channels ch on p_group_by = 'channel' and ch.id = k.gid
  where k.gid is not null
  order by 3 desc;
end;
$$;

create or replace function report_evolution_weekly(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null
)
returns table (
  bucket_start date,
  total_value numeric,
  total_quantity numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    date_trunc('week', so.invoice_date)::date,
    sum(so.gross_value)::numeric,
    sum(so.quantity)::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id = resolve_authorized_distributor_id(p_distributor_id)
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  group by 1
  order by 1
$$;

create or replace function report_three_month_history(
  p_reference_month date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null
)
returns table (
  month_start date,
  total_value numeric,
  total_quantity numeric,
  total_cost numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    date_trunc('month', so.invoice_date)::date,
    sum(so.gross_value)::numeric,
    sum(so.quantity)::numeric,
    sum(so.quantity * coalesce(so.unit_cost, 0))::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  where so.invoice_date >= (date_trunc('month', p_reference_month) - interval '2 months')::date
    and so.invoice_date < (date_trunc('month', p_reference_month) + interval '1 month')::date
    and so.distributor_id = resolve_authorized_distributor_id(p_distributor_id)
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
  group by 1
  order by 1
$$;

create or replace function report_evolution_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null
)
returns table (
  group_id uuid,
  group_name text,
  current_value numeric,
  previous_value numeric,
  value_change_pct numeric,
  current_quantity numeric,
  previous_quantity numeric,
  quantity_change_pct numeric,
  current_ticket numeric,
  previous_ticket numeric,
  ticket_change_pct numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
begin
  if p_group_by not in ('category', 'channel', 'customer') then
    raise exception 'report_evolution_analysis: invalid p_group_by %', p_group_by;
  end if;

  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);

  return query
  with base as (
    select
      case p_group_by
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
        when 'customer' then so.customer_id
      end as gid,
      so.invoice_date between p_current_start and p_current_end as is_current,
      so.gross_value,
      so.quantity,
      so.customer_id,
      so.invoice_number
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where (
        so.invoice_date between p_current_start and p_current_end
        or so.invoice_date between p_previous_start and p_previous_end
      )
      and so.distributor_id = v_distributor_id
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
      and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  ),
  grouped as (
    select
      b.gid,
      sum(b.gross_value) filter (where b.is_current) as cur_value,
      sum(b.gross_value) filter (where not b.is_current) as prev_value,
      sum(b.quantity) filter (where b.is_current) as cur_quantity,
      sum(b.quantity) filter (where not b.is_current) as prev_quantity,
      count(distinct b.customer_id) filter (where b.is_current) as cur_coverage,
      count(distinct b.customer_id) filter (where not b.is_current) as prev_coverage,
      count(distinct b.invoice_number) filter (where b.is_current) as cur_invoices,
      count(distinct b.invoice_number) filter (where not b.is_current) as prev_invoices
    from base b
    where b.gid is not null
    group by b.gid
  )
  select
    g.gid,
    coalesce(ph.name, ch.name, cust.legal_name, '-'),
    coalesce(g.cur_value, 0),
    coalesce(g.prev_value, 0),
    fn_ratio(coalesce(g.cur_value, 0), g.prev_value),
    coalesce(g.cur_quantity, 0),
    coalesce(g.prev_quantity, 0),
    fn_ratio(coalesce(g.cur_quantity, 0), g.prev_quantity),
    case when p_group_by = 'customer'
      then fn_safe_div(g.cur_value, g.cur_invoices::numeric)
      else fn_safe_div(g.cur_value, g.cur_coverage::numeric)
    end,
    case when p_group_by = 'customer'
      then fn_safe_div(g.prev_value, g.prev_invoices::numeric)
      else fn_safe_div(g.prev_value, g.prev_coverage::numeric)
    end,
    case when p_group_by = 'customer'
      then fn_ratio(fn_safe_div(g.cur_value, g.cur_invoices::numeric), fn_safe_div(g.prev_value, g.prev_invoices::numeric))
      else fn_ratio(fn_safe_div(g.cur_value, g.cur_coverage::numeric), fn_safe_div(g.prev_value, g.prev_coverage::numeric))
    end
  from grouped g
  left join product_hierarchy ph on p_group_by = 'category' and ph.id = g.gid
  left join channels ch on p_group_by = 'channel' and ch.id = g.gid
  left join customers cust on p_group_by = 'customer' and cust.id = g.gid
  order by 3 desc;
end;
$$;

create or replace function fn_fast_facts_dimension(
  p_dimension text,
  p_current_start date,
  p_current_end date,
  p_target_start date,
  p_target_end date,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_total_days integer := p_current_end - p_current_start + 1;
  v_elapsed_days integer := greatest(1, least(current_date, p_current_end) - p_current_start + 1);
  v_result jsonb;
begin
  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);

  with cur as (
    select
      case p_dimension
        when 'seller' then so.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then so.product_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
        when 'customer' then so.customer_id
      end as gid,
      sum(so.gross_value) as v_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = so.customer_id
    left join sales_reps sr on sr.id = so.sales_rep_id
    where so.invoice_date between p_current_start and p_current_end
      and so.distributor_id = v_distributor_id
    group by 1
  ),
  tgt as (
    select
      case p_dimension
        when 'seller' then c.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then t.product_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
        when 'customer' then t.customer_id
      end as gid,
      sum(t.gross_value) as v_value
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = t.customer_id
    left join sales_reps sr on sr.id = c.sales_rep_id
    where t.target_date between p_target_start and p_target_end
      and t.distributor_id = v_distributor_id
    group by 1
  ),
  joined as (
    select
      tgt.gid,
      coalesce(cur.v_value, 0) as cur_value,
      tgt.v_value as tgt_value,
      fn_safe_div(coalesce(cur.v_value, 0), tgt.v_value) as achievement,
      least(1, coalesce(
        fn_safe_div(fn_safe_div(coalesce(cur.v_value, 0), v_elapsed_days) * v_total_days, tgt.v_value), 0
      )) as probability
    from tgt
    left join cur on cur.gid = tgt.gid
    where tgt.gid is not null and tgt.v_value > 0
  ),
  named as (
    select
      j.*,
      coalesce(sr.name, pr.name, ph.name, ch.name, cust.legal_name, '-') as group_name
    from joined j
    left join sales_reps sr on p_dimension in ('seller', 'supervisor') and sr.id = j.gid
    left join products pr on p_dimension = 'product' and pr.id = j.gid
    left join product_hierarchy ph on p_dimension = 'category' and ph.id = j.gid
    left join channels ch on p_dimension = 'channel' and ch.id = j.gid
    left join customers cust on p_dimension = 'customer' and cust.id = j.gid
  )
  select jsonb_build_object(
    'dimension', p_dimension,
    'eligible_count', count(*),
    'achieved_count', count(*) filter (where achievement >= 1),
    'achieved_pct', fn_safe_div(count(*) filter (where achievement >= 1), count(*)::numeric),
    'avg_probability', avg(probability),
    'best', (
      select jsonb_build_object('name', n.group_name, 'achievement', n.achievement)
      from named n order by n.achievement desc nulls last limit 1
    ),
    'worst', (
      select jsonb_build_object('name', n.group_name, 'achievement', n.achievement)
      from named n order by n.achievement asc nulls last limit 1
    )
  )
  into v_result
  from named;

  return coalesce(v_result, jsonb_build_object('dimension', p_dimension, 'eligible_count', 0));
end;
$$;

create or replace function report_fast_facts(
  p_current_start date,
  p_current_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_dimension text;
  v_result jsonb := '{}'::jsonb;
begin
  v_distributor_id := resolve_authorized_distributor_id(p_distributor_id);

  foreach v_dimension in array array['seller', 'supervisor', 'product', 'category', 'channel', 'customer']
  loop
    v_result := v_result || jsonb_build_object(
      v_dimension,
      fn_fast_facts_dimension(
        v_dimension, p_current_start, p_current_end,
        coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
        v_distributor_id
      )
    );
  end loop;

  return v_result;
end;
$$;

create or replace function process_sell_out_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
  select fi.distributor_id, d.code
  into v_distributor_id, v_distributor_code
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_sell_out_staging: import % has no distributor', p_import_id;
  end if;

  for v_month in
    select distinct date_trunc('month', s.invoice_date::date)::date
    from staging_sell_out s
    where s.import_id = p_import_id and fn_is_iso_date(s.invoice_date)
  loop
    perform ensure_month_partition('sell_out', v_month);
  end loop;

  with parsed as (
    select
      s.line_number,
      v_distributor_id as distributor_id,
      c.id as customer_id,
      c.sales_rep_id,
      p.id as product_id,
      s.invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when s.distributor_code is distinct from v_distributor_code then 'unauthorized distributor code: ' || coalesce(s.distributor_code, '<null>')
        when c.id is null then 'unknown customer cnpj: ' || coalesce(s.customer_cnpj, '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_out s
    left join lateral (
      select c.id, c.sales_rep_id
      from customers c
      where c.distributor_id = v_distributor_id
        and regexp_replace(coalesce(c.cnpj, ''), '\D', '', 'g') = regexp_replace(coalesce(s.customer_cnpj, ''), '\D', '', 'g')
      order by c.created_at, c.id
      limit 1
    ) c on true
    left join products p
      on p.distributor_id = v_distributor_id
      and p.ean = s.product_ean
    where s.import_id = p_import_id
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  inserted as (
    insert into sell_out (
      distributor_id, customer_id, product_id, sales_rep_id,
      invoice_number, invoice_date, quantity, gross_value, unit_cost, import_id
    )
    select
      distributor_id, customer_id, product_id, sales_rep_id,
      invoice_number, invoice_date, quantity, gross_value, unit_cost, p_import_id
    from parsed
    where rejection_reason is null
    returning 1
  )
  select
    (select count(*) from inserted),
    (select count(*) from rejected)
  into v_inserted, v_rejected;

  delete from staging_sell_out where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_inserted, v_rejected;
end;
$$;

create or replace function process_sell_in_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
  select fi.distributor_id, d.code
  into v_distributor_id, v_distributor_code
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_sell_in_staging: import % has no distributor', p_import_id;
  end if;

  for v_month in
    select distinct date_trunc('month', s.invoice_date::date)::date
    from staging_sell_in s
    where s.import_id = p_import_id and fn_is_iso_date(s.invoice_date)
  loop
    perform ensure_month_partition('sell_in', v_month);
  end loop;

  with parsed as (
    select
      s.line_number,
      v_distributor_id as distributor_id,
      p.id as product_id,
      s.invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when s.distributor_code is distinct from v_distributor_code then 'unauthorized distributor code: ' || coalesce(s.distributor_code, '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_in s
    left join products p
      on p.distributor_id = v_distributor_id
      and p.ean = s.product_ean
    where s.import_id = p_import_id
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  inserted as (
    insert into sell_in (
      distributor_id, product_id, invoice_number, invoice_date,
      quantity, gross_value, unit_cost, import_id
    )
    select
      distributor_id, product_id, invoice_number, invoice_date,
      quantity, gross_value, unit_cost, p_import_id
    from parsed
    where rejection_reason is null
    returning 1
  )
  select
    (select count(*) from inserted),
    (select count(*) from rejected)
  into v_inserted, v_rejected;

  delete from staging_sell_in where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_inserted, v_rejected;
end;
$$;

revoke execute on function fn_sell_out_metrics(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_target_metrics(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_customer_count(uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_fast_facts_dimension(text, date, date, date, date, uuid) from public, anon, authenticated;
revoke execute on function validate_distributor_relationships() from public, anon, authenticated;
revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
revoke execute on function process_sell_in_staging(uuid) from public, anon, authenticated;

revoke execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
revoke execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
revoke execute on function report_evolution_weekly(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
revoke execute on function report_three_month_history(date, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
revoke execute on function report_evolution_analysis(text, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
revoke execute on function report_fast_facts(date, date, date, date, uuid) from public, anon;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function report_evolution_weekly(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function report_three_month_history(date, uuid, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function report_evolution_analysis(text, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function report_fast_facts(date, date, date, date, uuid) to authenticated;
