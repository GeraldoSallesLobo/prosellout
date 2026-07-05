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
  supervisor_id uuid references sales_reps(id) on delete restrict,
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint supervisor_is_root check ((role = 'supervisor') = (supervisor_id is null))
);

create index sales_reps_supervisor_idx on sales_reps (supervisor_id);

create table customers (
  id uuid primary key default gen_random_uuid(),
  cnpj text not null unique,
  legal_name text not null,
  district text,
  city text,
  state char(2),
  zip_code text,
  channel_id uuid references channels(id),
  cluster_id uuid references clusters(id),
  sales_rep_id uuid references sales_reps(id),
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
