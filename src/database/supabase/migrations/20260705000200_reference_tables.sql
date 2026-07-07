-- Reference (master data) tables: distributors, product hierarchy, commercial
-- hierarchy, channels, clusters and customers.

create type entity_status as enum ('active', 'inactive');
create type hierarchy_level as enum ('macro_category', 'category', 'subcategory');
create type sales_role as enum ('supervisor', 'seller');

-- Shared trigger to keep updated_at columns current.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table distributors (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  cnpj text unique,
  city text,
  state char(2),
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table channels (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table clusters (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Product tree: macro_category -> category -> subcategory.
create table product_hierarchy (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references product_hierarchy(id) on delete restrict,
  level hierarchy_level not null,
  name text not null,
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Only macro categories live at the root of the tree.
  constraint macro_category_is_root check ((level = 'macro_category') = (parent_id is null)),
  constraint unique_name_per_parent unique nulls not distinct (parent_id, name)
);

create index product_hierarchy_parent_idx on product_hierarchy (parent_id);

create table products (
  id uuid primary key default gen_random_uuid(),
  ean text not null unique,
  sku_code text unique,
  name text not null,
  subcategory_id uuid not null references product_hierarchy(id),
  unit_label text not null default 'CX',
  units_per_pack numeric(10, 2) not null default 1,
  box_count numeric(10, 2),
  distributor_id uuid references distributors(id),
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index products_subcategory_idx on products (subcategory_id);

-- Commercial tree: supervisor -> sellers.
create table sales_reps (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role sales_role not null,
  code text,
  distributor_id uuid references distributors(id),
  portfolio_size integer,
  manager_id uuid references sales_reps(id),
  supervisor_id uuid references sales_reps(id) on delete restrict,
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint supervisor_is_root check ((role = 'supervisor') = (supervisor_id is null))
);

create index sales_reps_supervisor_idx on sales_reps (supervisor_id);

create table customers (
  id uuid primary key default gen_random_uuid(),
  cnpj text,
  legal_name text not null,
  trade_name text,
  address text,
  district text,
  city text,
  state char(2),
  zip_code text,
  channel_id uuid references channels(id),
  cluster_id uuid references clusters(id),
  sales_rep_id uuid references sales_reps(id),
  distributor_id uuid references distributors(id),
  pdv_code text,
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- PDV real identity is (distributor, pdv_code); CNPJ vem mascarado/não único.
create unique index customers_distributor_pdv_key on customers (distributor_id, pdv_code);
create index customers_distributor_idx on customers (distributor_id);

create index customers_channel_idx on customers (channel_id);
create index customers_cluster_idx on customers (cluster_id);
create index customers_sales_rep_idx on customers (sales_rep_id);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'distributors', 'channels', 'clusters', 'product_hierarchy',
    'products', 'sales_reps', 'customers'
  ]
  loop
    execute format(
      'create trigger %I before update on %I for each row execute function set_updated_at()',
      v_table || '_set_updated_at', v_table
    );
  end loop;
end;
$$;

-- EAN core: strips the leading DUN-14 digit so 13/14-digit EANs match.
create or replace function fn_ean_core(p_ean text)
returns text
language sql
immutable
as $$
  select case
    when length(p_ean) = 14 and left(p_ean, 1) = '1' then right(p_ean, 13)
    else p_ean
  end
$$;
