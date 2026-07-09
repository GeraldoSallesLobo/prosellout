-- Align the AWS import pipeline with the real distributor layouts.
--
-- The sample files use distributor CNPJ, PDV code, seller code, optional
-- delivery date and no invoice number/cost. Earlier ETL versions expected an
-- internal distributor code, customer CNPJ and invoice/cost columns.

alter table staging_sell_out
  add column if not exists customer_pdv_code text,
  add column if not exists sales_rep_code text,
  add column if not exists delivery_date text;

alter table sell_out
  add column if not exists delivery_date date;

create unlogged table if not exists staging_customers (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  customer_pdv_code text,
  customer_cnpj text,
  legal_name text,
  trade_name text,
  address text,
  district text,
  city text,
  state text,
  zip_code text,
  channel_name text,
  cluster_name text
);

create index if not exists staging_customers_import_idx on staging_customers (import_id);

create unlogged table if not exists staging_products (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  product_ean text,
  product_name text,
  box_count text,
  units_per_pack text,
  subcategory_name text,
  category_name text,
  macro_category_name text,
  sku_code text
);

create index if not exists staging_products_import_idx on staging_products (import_id);

create unlogged table if not exists staging_sellers (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  seller_code text,
  seller_name text,
  portfolio_size text,
  supervisor_code text,
  supervisor_name text,
  manager_code text,
  manager_name text
);

create index if not exists staging_sellers_import_idx on staging_sellers (import_id);

create unique index if not exists sales_reps_distributor_role_code_key
  on sales_reps (distributor_id, role, code)
  where code is not null;

create unlogged table if not exists staging_targets (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  customer_pdv_code text,
  customer_cnpj text,
  sales_rep_code text,
  product_ean text,
  target_date text,
  delivery_date text,
  quantity text,
  gross_value text
);

create index if not exists staging_targets_import_idx on staging_targets (import_id);

alter table staging_customers enable row level security;
alter table staging_products enable row level security;
alter table staging_sellers enable row level security;
alter table staging_targets enable row level security;

revoke all on staging_customers from public, anon, authenticated;
revoke all on staging_products from public, anon, authenticated;
revoke all on staging_sellers from public, anon, authenticated;
revoke all on staging_targets from public, anon, authenticated;

insert into file_type_configs (id, code, name, target_table, processing_routine, file_format, status)
values
  ('6203bef9-2c9a-5429-b370-43506154f057', 'SELL_OUT', 'Sell Out Distribuidor', 'sell_out', 'process_sell_out_staging', 'xlsx', 'active'),
  ('8dd36250-0d58-5c15-b535-fc16ee81f409', 'SELL_IN', 'Sell In Indústria', 'sell_in', 'process_sell_in_staging', 'xlsx', 'active'),
  ('4933f10f-670d-59c2-bb17-9339099d6830', 'CUSTOMERS', 'Base de Clientes', 'customers', 'process_customers_staging', 'xlsx', 'active'),
  ('9d6aab7f-3a48-5497-8d55-04f9afcc503e', 'PRODUCTS', 'Base de Produtos', 'products', 'process_products_staging', 'xlsx', 'active'),
  ('f2570305-8991-5de9-9e4b-76fc717eb938', 'SELLERS', 'Base de Vendedores', 'sales_reps', 'process_sellers_staging', 'xlsx', 'active'),
  ('55d6c9af-cb2b-5d8b-a801-3be9b7cb3fd8', 'TARGETS', 'Metas por Cliente/SKU', 'sales_targets', 'process_targets_staging', 'xlsx', 'active')
on conflict (code) do update set
  name = excluded.name,
  target_table = excluded.target_table,
  processing_routine = excluded.processing_routine,
  file_format = excluded.file_format,
  status = excluded.status,
  updated_at = now();

create or replace function fn_import_distributor_matches(
  p_value text,
  p_distributor_code text,
  p_distributor_cnpj text
)
returns boolean
language sql
immutable
as $$
  select nullif(p_value, '') is null
    or regexp_replace(p_value, '\D', '', 'g') in (
      regexp_replace(coalesce(p_distributor_code, ''), '\D', '', 'g'),
      regexp_replace(coalesce(p_distributor_cnpj, ''), '\D', '', 'g')
    )
$$;

create or replace function process_customers_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_processed bigint := 0;
  v_rejected bigint := 0;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_customers_staging: import % has no distributor', p_import_id;
  end if;

  insert into channels (distributor_id, name, status)
  select distinct v_distributor_id, btrim(s.channel_name), 'active'::entity_status
  from staging_customers s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.channel_name), '') is not null
  on conflict (distributor_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into clusters (distributor_id, name, status)
  select distinct v_distributor_id, btrim(s.cluster_name), 'active'::entity_status
  from staging_customers s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.cluster_name), '') is not null
  on conflict (distributor_id, name) do update set
    status = 'active',
    updated_at = now();

  with parsed as (
    select
      s.line_number,
      nullif(btrim(s.customer_pdv_code), '') as customer_pdv_code,
      nullif(btrim(s.customer_cnpj), '') as customer_cnpj,
      nullif(btrim(s.legal_name), '') as legal_name,
      nullif(btrim(s.trade_name), '') as trade_name,
      nullif(btrim(s.address), '') as address,
      nullif(btrim(s.district), '') as district,
      nullif(btrim(s.city), '') as city,
      left(nullif(btrim(s.state), ''), 2) as state,
      nullif(btrim(s.zip_code), '') as zip_code,
      ch.id as channel_id,
      cl.id as cluster_id,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when nullif(btrim(s.customer_pdv_code), '') is null then 'missing customer pdv code'
        when nullif(btrim(s.legal_name), '') is null then 'missing legal name'
      end as rejection_reason
    from staging_customers s
    left join channels ch
      on ch.distributor_id = v_distributor_id
     and ch.name = nullif(btrim(s.channel_name), '')
    left join clusters cl
      on cl.distributor_id = v_distributor_id
     and cl.name = nullif(btrim(s.cluster_name), '')
    where s.import_id = p_import_id
  ),
  valid_rows as (
    select * from parsed where rejection_reason is null
  ),
  deduped_rows as (
    select distinct on (customer_pdv_code) *
    from valid_rows
    order by customer_pdv_code, line_number desc
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  upserted as (
    insert into customers (
      distributor_id, pdv_code, cnpj, legal_name, trade_name, address,
      district, city, state, zip_code, channel_id, cluster_id, status
    )
    select
      v_distributor_id, customer_pdv_code, customer_cnpj, legal_name, trade_name, address,
      district, city, state, zip_code, channel_id, cluster_id, 'active'::entity_status
    from deduped_rows
    on conflict (distributor_id, pdv_code) do update set
      cnpj = excluded.cnpj,
      legal_name = excluded.legal_name,
      trade_name = excluded.trade_name,
      address = excluded.address,
      district = excluded.district,
      city = excluded.city,
      state = excluded.state,
      zip_code = excluded.zip_code,
      channel_id = excluded.channel_id,
      cluster_id = excluded.cluster_id,
      status = 'active',
      updated_at = now()
    returning 1
  )
  select
    (select count(*) from valid_rows),
    (select count(*) from rejected)
  into v_processed, v_rejected;

  delete from staging_customers where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
end;
$$;

create or replace function process_products_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_processed bigint := 0;
  v_rejected bigint := 0;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_products_staging: import % has no distributor', p_import_id;
  end if;

  insert into product_hierarchy (distributor_id, parent_id, level, name, status)
  select distinct v_distributor_id, null, 'macro_category'::hierarchy_level, btrim(s.macro_category_name), 'active'::entity_status
  from staging_products s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.macro_category_name), '') is not null
  on conflict (distributor_id, parent_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into product_hierarchy (distributor_id, parent_id, level, name, status)
  select distinct v_distributor_id, macro.id, 'category'::hierarchy_level, btrim(s.category_name), 'active'::entity_status
  from staging_products s
  join product_hierarchy macro
    on macro.distributor_id = v_distributor_id
   and macro.level = 'macro_category'
   and macro.name = btrim(s.macro_category_name)
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.category_name), '') is not null
  on conflict (distributor_id, parent_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into product_hierarchy (distributor_id, parent_id, level, name, status)
  select distinct v_distributor_id, category.id, 'subcategory'::hierarchy_level, btrim(s.subcategory_name), 'active'::entity_status
  from staging_products s
  join product_hierarchy macro
    on macro.distributor_id = v_distributor_id
   and macro.level = 'macro_category'
   and macro.name = btrim(s.macro_category_name)
  join product_hierarchy category
    on category.distributor_id = v_distributor_id
   and category.parent_id = macro.id
   and category.level = 'category'
   and category.name = btrim(s.category_name)
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.subcategory_name), '') is not null
  on conflict (distributor_id, parent_id, name) do update set
    status = 'active',
    updated_at = now();

  with parsed as (
    select
      s.line_number,
      nullif(btrim(s.product_ean), '') as product_ean,
      nullif(btrim(s.product_name), '') as product_name,
      nullif(btrim(s.sku_code), '') as sku_code,
      case
        when nullif(btrim(s.units_per_pack), '') is null then 1
        when fn_is_numeric(s.units_per_pack) then s.units_per_pack::numeric
      end as units_per_pack,
      case
        when nullif(btrim(s.box_count), '') is null then null
        when fn_is_numeric(s.box_count) then s.box_count::numeric
      end as box_count,
      subcategory.id as subcategory_id,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when nullif(btrim(s.product_ean), '') is null then 'missing product ean'
        when nullif(btrim(s.product_name), '') is null then 'missing product name'
        when nullif(btrim(s.macro_category_name), '') is null then 'missing macro category'
        when nullif(btrim(s.category_name), '') is null then 'missing category'
        when nullif(btrim(s.subcategory_name), '') is null then 'missing subcategory'
        when nullif(btrim(s.units_per_pack), '') is not null
          and not fn_is_numeric(s.units_per_pack)
          then 'invalid units_per_pack: ' || coalesce(s.units_per_pack, '<null>')
        when fn_is_numeric(s.units_per_pack) and s.units_per_pack::numeric <= 0
          then 'invalid units_per_pack: ' || coalesce(s.units_per_pack, '<null>')
        when nullif(btrim(s.box_count), '') is not null and not fn_is_numeric(s.box_count)
          then 'invalid box_count: ' || coalesce(s.box_count, '<null>')
        when subcategory.id is null then 'unknown product hierarchy'
      end as rejection_reason
    from staging_products s
    left join product_hierarchy macro
      on macro.distributor_id = v_distributor_id
     and macro.level = 'macro_category'
     and macro.name = btrim(s.macro_category_name)
    left join product_hierarchy category
      on category.distributor_id = v_distributor_id
     and category.parent_id = macro.id
     and category.level = 'category'
     and category.name = btrim(s.category_name)
    left join product_hierarchy subcategory
      on subcategory.distributor_id = v_distributor_id
     and subcategory.parent_id = category.id
     and subcategory.level = 'subcategory'
     and subcategory.name = btrim(s.subcategory_name)
    where s.import_id = p_import_id
  ),
  valid_rows as (
    select * from parsed where rejection_reason is null
  ),
  deduped_rows as (
    select distinct on (product_ean) *
    from valid_rows
    order by product_ean, line_number desc
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  upserted as (
    insert into products (
      distributor_id, ean, sku_code, name, subcategory_id,
      unit_label, units_per_pack, box_count, status
    )
    select
      v_distributor_id, product_ean, sku_code, product_name, subcategory_id,
      'CX', units_per_pack, box_count, 'active'::entity_status
    from deduped_rows
    on conflict on constraint products_distributor_ean_key do update set
      sku_code = excluded.sku_code,
      name = excluded.name,
      subcategory_id = excluded.subcategory_id,
      unit_label = excluded.unit_label,
      units_per_pack = excluded.units_per_pack,
      box_count = excluded.box_count,
      status = 'active',
      updated_at = now()
    returning 1
  )
  select
    (select count(*) from valid_rows),
    (select count(*) from rejected)
  into v_processed, v_rejected;

  delete from staging_products where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
end;
$$;

create or replace function process_sellers_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_processed bigint := 0;
  v_rejected bigint := 0;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_sellers_staging: import % has no distributor', p_import_id;
  end if;

  insert into sales_reps (distributor_id, role, code, name, status)
  select distinct
    v_distributor_id,
    'supervisor'::sales_role,
    btrim(s.supervisor_code),
    coalesce(nullif(btrim(s.supervisor_name), ''), 'Supervisor ' || btrim(s.supervisor_code)),
    'active'::entity_status
  from staging_sellers s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.supervisor_code), '') is not null
  on conflict (distributor_id, role, code) where code is not null do update set
    name = excluded.name,
    status = 'active',
    updated_at = now();

  with parsed as (
    select
      s.line_number,
      nullif(btrim(s.seller_code), '') as seller_code,
      nullif(btrim(s.seller_name), '') as seller_name,
      case
        when nullif(btrim(s.portfolio_size), '') is null then null
        when fn_is_numeric(s.portfolio_size) then s.portfolio_size::numeric::integer
      end as portfolio_size,
      supervisor.id as supervisor_id,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when nullif(btrim(s.seller_code), '') is null then 'missing seller code'
        when nullif(btrim(s.seller_name), '') is null then 'missing seller name'
        when nullif(btrim(s.supervisor_code), '') is null then 'missing supervisor code'
        when nullif(btrim(s.portfolio_size), '') is not null and not fn_is_numeric(s.portfolio_size)
          then 'invalid portfolio_size: ' || coalesce(s.portfolio_size, '<null>')
        when supervisor.id is null then 'unknown supervisor code: ' || coalesce(s.supervisor_code, '<null>')
      end as rejection_reason
    from staging_sellers s
    left join sales_reps supervisor
      on supervisor.distributor_id = v_distributor_id
     and supervisor.role = 'supervisor'
     and supervisor.code = btrim(s.supervisor_code)
    where s.import_id = p_import_id
  ),
  valid_rows as (
    select * from parsed where rejection_reason is null
  ),
  deduped_rows as (
    select distinct on (seller_code) *
    from valid_rows
    order by seller_code, line_number desc
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  upserted as (
    insert into sales_reps (
      distributor_id, role, code, name, supervisor_id, portfolio_size, status
    )
    select
      v_distributor_id, 'seller'::sales_role, seller_code, seller_name,
      supervisor_id, portfolio_size, 'active'::entity_status
    from deduped_rows
    on conflict (distributor_id, role, code) where code is not null do update set
      name = excluded.name,
      supervisor_id = excluded.supervisor_id,
      portfolio_size = excluded.portfolio_size,
      status = 'active',
      updated_at = now()
    returning 1
  )
  select
    (select count(*) from valid_rows),
    (select count(*) from rejected)
  into v_processed, v_rejected;

  delete from staging_sellers where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
end;
$$;

create or replace function process_targets_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_processed bigint := 0;
  v_rejected bigint := 0;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_targets_staging: import % has no distributor', p_import_id;
  end if;

  with parsed as (
    select
      s.line_number,
      c.id as customer_id,
      p.id as product_id,
      case when fn_is_iso_date(s.target_date) then date_trunc('month', s.target_date::date)::date end as target_date,
      case
        when nullif(btrim(s.quantity), '') is null then 0
        when fn_is_numeric(s.quantity) then s.quantity::numeric
      end as quantity,
      case
        when nullif(btrim(s.gross_value), '') is null then 0
        when fn_is_numeric(s.gross_value) then s.gross_value::numeric
      end as gross_value,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when c.id is null then 'unknown customer code/cnpj: ' ||
          coalesce(nullif(s.customer_pdv_code, ''), nullif(s.customer_cnpj, ''), '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.target_date) then 'invalid target_date: ' || coalesce(s.target_date, '<null>')
        when nullif(btrim(s.quantity), '') is not null and not fn_is_numeric(s.quantity)
          then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when nullif(btrim(s.gross_value), '') is not null and not fn_is_numeric(s.gross_value)
          then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
        when nullif(btrim(s.quantity), '') is null and nullif(btrim(s.gross_value), '') is null
          then 'missing target values'
      end as rejection_reason
    from staging_targets s
    left join lateral (
      select c.id
      from customers c
      where c.distributor_id = v_distributor_id
        and (
          (nullif(s.customer_pdv_code, '') is not null and c.pdv_code = s.customer_pdv_code)
          or (
            nullif(s.customer_pdv_code, '') is null
            and regexp_replace(coalesce(c.cnpj, ''), '\D', '', 'g') =
              regexp_replace(coalesce(s.customer_cnpj, ''), '\D', '', 'g')
          )
        )
      order by c.created_at, c.id
      limit 1
    ) c on true
    left join lateral (
      select p.id
      from products p
      where fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
        and p.distributor_id = v_distributor_id
      order by p.created_at, p.id
      limit 1
    ) p on true
    where s.import_id = p_import_id
  ),
  valid_rows as (
    select * from parsed where rejection_reason is null
  ),
  aggregated_rows as (
    select
      customer_id,
      product_id,
      target_date,
      sum(quantity) as quantity,
      sum(gross_value) as gross_value
    from valid_rows
    group by customer_id, product_id, target_date
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  upserted as (
    insert into sales_targets (
      distributor_id, customer_id, product_id, target_date,
      quantity, gross_value, import_id
    )
    select
      v_distributor_id, customer_id, product_id, target_date,
      quantity, gross_value, p_import_id
    from aggregated_rows
    on conflict (customer_id, product_id, target_date) do update set
      distributor_id = excluded.distributor_id,
      quantity = case
        when sales_targets.import_id = excluded.import_id
          then sales_targets.quantity + excluded.quantity
        else excluded.quantity
      end,
      gross_value = case
        when sales_targets.import_id = excluded.import_id
          then sales_targets.gross_value + excluded.gross_value
        else excluded.gross_value
      end,
      import_id = excluded.import_id
    returning 1
  )
  select
    (select count(*) from valid_rows),
    (select count(*) from rejected)
  into v_processed, v_rejected;

  delete from staging_targets where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
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
  v_distributor_cnpj text;
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
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
      coalesce(sr.id, c.sales_rep_id) as sales_rep_id,
      p.id as product_id,
      coalesce(nullif(s.invoice_number, ''), p_import_id::text || '-' || s.line_number::text) as invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case
        when nullif(s.delivery_date, '') is null then null
        when fn_is_iso_date(s.delivery_date) then s.delivery_date::date
      end as delivery_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when c.id is null then 'unknown customer code/cnpj: ' ||
          coalesce(nullif(s.customer_pdv_code, ''), nullif(s.customer_cnpj, ''), '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when nullif(s.delivery_date, '') is not null and not fn_is_iso_date(s.delivery_date)
          then 'invalid delivery_date: ' || coalesce(s.delivery_date, '<null>')
        when not fn_is_numeric(s.quantity) then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_out s
    left join lateral (
      select c.id, c.sales_rep_id
      from customers c
      where c.distributor_id = v_distributor_id
        and (
          (nullif(s.customer_pdv_code, '') is not null and c.pdv_code = s.customer_pdv_code)
          or (
            nullif(s.customer_pdv_code, '') is null
            and regexp_replace(coalesce(c.cnpj, ''), '\D', '', 'g') =
              regexp_replace(coalesce(s.customer_cnpj, ''), '\D', '', 'g')
          )
        )
      order by c.created_at, c.id
      limit 1
    ) c on true
    left join lateral (
      select sr.id
      from sales_reps sr
      where sr.distributor_id = v_distributor_id
        and sr.role = 'seller'
        and sr.code = s.sales_rep_code
      order by sr.created_at, sr.id
      limit 1
    ) sr on true
    left join lateral (
      select p.id
      from products p
      where fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
        and (p.distributor_id is null or p.distributor_id = v_distributor_id)
      order by case when p.distributor_id = v_distributor_id then 0 else 1 end, p.created_at, p.id
      limit 1
    ) p on true
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
      invoice_number, invoice_date, delivery_date, quantity, gross_value, unit_cost, import_id
    )
    select
      distributor_id, customer_id, product_id, sales_rep_id,
      invoice_number, invoice_date, delivery_date, quantity, gross_value, unit_cost, p_import_id
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
  v_distributor_cnpj text;
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
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
      coalesce(nullif(s.invoice_number, ''), p_import_id::text || '-' || s.line_number::text) as invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when not fn_is_numeric(s.quantity) then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_in s
    left join lateral (
      select p.id
      from products p
      where fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
        and (p.distributor_id is null or p.distributor_id = v_distributor_id)
      order by case when p.distributor_id = v_distributor_id then 0 else 1 end, p.created_at, p.id
      limit 1
    ) p on true
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

revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
revoke execute on function process_sell_in_staging(uuid) from public, anon, authenticated;
revoke execute on function process_customers_staging(uuid) from public, anon, authenticated;
revoke execute on function process_products_staging(uuid) from public, anon, authenticated;
revoke execute on function process_sellers_staging(uuid) from public, anon, authenticated;
revoke execute on function process_targets_staging(uuid) from public, anon, authenticated;
revoke execute on function fn_import_distributor_matches(text, text, text) from public, anon, authenticated;
