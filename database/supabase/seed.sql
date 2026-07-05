-- Demo/development seed.
-- Generates master data plus ~4 months of synthetic sell out (current month,
-- two previous months and the same month of the previous year), targets,
-- sell in and stock. Deterministic via setseed().

select setseed(0.42);

-- ---------------------------------------------------------------------------
-- Master data
-- ---------------------------------------------------------------------------
insert into channels (name) values
  ('Açougue'), ('Padaria'), ('Restaurante'), ('Até 4 Check'),
  ('Até 10 Check'), ('Acima 10 Check'), ('Confeitaria'), ('Conveniência');

insert into clusters (name) values ('Ouro'), ('Prata'), ('Bronze');

insert into distributors (code, name, cnpj, city, state) values
  ('DIST001', 'Distribuidora Alfa', '11222333000181', 'São Paulo', 'SP'),
  ('DIST002', 'Distribuidora Beta', '22333444000172', 'Campinas', 'SP'),
  ('DIST003', 'Distribuidora Gama', '33444555000163', 'Curitiba', 'PR');

-- Product tree: 1 macro category -> 4 categories -> subcategories.
with macro as (
  insert into product_hierarchy (level, name) values ('macro_category', 'Alimentos')
  returning id
),
categories as (
  insert into product_hierarchy (parent_id, level, name)
  select macro.id, 'category', c.name
  from macro, (values ('Snacks de Batatas'), ('Yok Extrusados'), ('Popcorn Microondas'), ('Batata Palha')) as c(name)
  returning id, name
)
insert into product_hierarchy (parent_id, level, name)
select categories.id, 'subcategory', s.sub_name
from categories
join (values
  ('Snacks de Batatas', 'Lisa'),
  ('Snacks de Batatas', 'Ondulada'),
  ('Yok Extrusados', 'Sabores'),
  ('Popcorn Microondas', 'Tradicional'),
  ('Batata Palha', 'Extrafina'),
  ('Batata Palha', 'Clássica')
) as s(cat_name, sub_name) on s.cat_name = categories.name;

insert into products (ean, sku_code, name, subcategory_id, unit_label, units_per_pack)
select p.ean, p.sku_code, p.name, ph.id, 'CX', p.units_per_pack
from (values
  ('7891000100011', 'SKU-001', 'LISA 36/45G', 'Lisa', 36),
  ('7891000100028', 'SKU-002', 'ONDULADA 14/90G', 'Ondulada', 14),
  ('7891000100035', 'SKU-003', 'ONDULADA 36/45G', 'Ondulada', 36),
  ('7891000100042', 'SKU-004', 'CEBOLA CX 24/54G', 'Sabores', 24),
  ('7891000100059', 'SKU-005', 'PRES 30/54G', 'Sabores', 30),
  ('7891000100066', 'SKU-006', 'PRES 16/153G', 'Sabores', 16),
  ('7891000100073', 'SKU-007', 'SAL 36/100G', 'Tradicional', 36),
  ('7891000100080', 'SKU-008', 'CAR CX 30/160G', 'Tradicional', 30),
  ('7891000100097', 'SKU-009', 'EXTRAFINA 20X100G', 'Extrafina', 20),
  ('7891000100103', 'SKU-010', 'EXTRAFINA 24X140G', 'Extrafina', 24),
  ('7891000100110', 'SKU-011', 'CLÁSSICA 20X100G', 'Clássica', 20),
  ('7891000100127', 'SKU-012', 'CLÁSSICA 12X500G', 'Clássica', 12)
) as p(ean, sku_code, name, sub_name, units_per_pack)
join product_hierarchy ph on ph.level = 'subcategory' and ph.name = p.sub_name;

-- Commercial tree: 3 supervisors x 3 sellers.
with supervisors as (
  insert into sales_reps (name, role)
  select 'Supervisor ' || n, 'supervisor' from generate_series(1, 3) n
  returning id, name
)
insert into sales_reps (name, role, supervisor_id)
select 'Vendedor ' || s.n, 'seller', sup.id
from generate_series(1, 9) as s(n)
join supervisors sup on sup.name = 'Supervisor ' || (((s.n - 1) / 3) + 1);

-- 40 customers spread across channels, clusters and sellers.
insert into customers (cnpj, legal_name, district, city, state, zip_code, channel_id, cluster_id, sales_rep_id)
select
  lpad((10000000000100 + n)::text, 14, '0'),
  'Cliente ' || lpad(n::text, 3, '0') || ' Comércio de Alimentos Ltda',
  'Bairro ' || (1 + (n % 8)),
  (array['São Paulo', 'Campinas', 'Santos', 'Curitiba', 'Londrina'])[1 + (n % 5)],
  (array['SP', 'SP', 'SP', 'PR', 'PR'])[1 + (n % 5)],
  lpad((1000000 + n * 137)::text, 8, '0'),
  (select id from channels order by name offset (n % 8) limit 1),
  (select id from clusters order by name offset (n % 3) limit 1),
  (select id from sales_reps where role = 'seller' order by name offset (n % 9) limit 1)
from generate_series(1, 40) n;

-- ---------------------------------------------------------------------------
-- File pipeline configuration + sample history
-- ---------------------------------------------------------------------------
insert into file_type_configs (code, name, target_table, processing_routine, file_format) values
  ('SELL_OUT', 'Sell Out Distribuidor', 'sell_out', 'process_sell_out_staging', 'xlsx'),
  ('SELL_IN', 'Sell In Indústria', 'sell_in', 'process_sell_in_staging', 'xlsx'),
  ('CUSTOMERS', 'Base de Clientes', 'customers', 'upsert_customers', 'csv'),
  ('TARGETS', 'Metas por Cliente/SKU', 'sales_targets', 'upsert_targets', 'xlsx'),
  ('STOCK', 'Estoque Distribuidor', 'stock_snapshots', 'upsert_stock', 'csv'),
  ('PLANNER', 'Planificador', 'planner_entries', 'upsert_planner_entries', 'xlsx'),
  ('PRODUCTS', 'Base de Produtos', 'products', 'upsert_products', 'xlsx');

insert into file_imports (file_name, sheet_name, file_type_id, status, total_records, processed_records, error_count, finished_at)
select
  'sellout_' || to_char(current_date - n, 'YYYYMMDD') || '.xlsx',
  'Base',
  (select id from file_type_configs where code = 'SELL_OUT'),
  case when n = 1 then 'completed_with_errors'::import_status else 'completed'::import_status end,
  18000 + n * 977,
  18000 + n * 977 - case when n = 1 then 12 else 0 end,
  case when n = 1 then 12 else 0 end,
  now() - (n || ' days')::interval
from generate_series(1, 6) n;

insert into file_imports (file_name, sheet_name, file_type_id, status, total_records, processed_records, error_count, finished_at)
select
  prefix || '_' || to_char(current_date - n, 'YYYYMMDD') || '.xlsx',
  sheet,
  (select id from file_type_configs where code = type_code),
  'completed'::import_status,
  1200 + n * 37,
  1200 + n * 37,
  0,
  now() - (n || ' days')::interval
from generate_series(1, 3) n,
  (values
    ('produtos', 'Produtos', 'PRODUCTS'),
    ('planificador', 'Plano', 'PLANNER')
  ) as sources(prefix, sheet, type_code);

insert into file_import_logs (import_id, line_number, level, message)
select i.id, 40 + g, 'error', 'unknown product ean: 78910001999' || g
from file_imports i, generate_series(1, 3) g
where i.status = 'completed_with_errors';

-- ---------------------------------------------------------------------------
-- Transactional data
-- ---------------------------------------------------------------------------
-- Ensure partitions for the seeded window (also done by the migration, but the
-- seed may run on a fresh month).
select ensure_month_partition('sell_out', m::date)
from generate_series(date_trunc('month', current_date) - interval '13 months', date_trunc('month', current_date), interval '1 month') m;
select ensure_month_partition('sell_in', m::date)
from generate_series(date_trunc('month', current_date) - interval '13 months', date_trunc('month', current_date), interval '1 month') m;

-- NOTE: the price formula below (stable pseudo-random R$ 18.00-98.00 per EAN)
-- is repeated as a CTE in each insert on purpose. The Supabase CLI sends the
-- seed as a prepared-statement batch: every statement is parsed BEFORE any of
-- them runs, so a view created here would not exist yet when the following
-- inserts are prepared.

-- Sell out: one invoice per customer/day when the customer "buys", with 1-5
-- SKUs per invoice. Covers current month, two previous months and the same
-- month one year ago.
with product_prices as (
  select
    p.id as product_id,
    18 + (('x' || substr(md5(p.ean), 1, 6))::bit(24)::int % 8000) / 100.0 as unit_price
  from products p
),
days as (
  select d::date as invoice_date
  from generate_series(date_trunc('month', current_date) - interval '2 months', current_date, interval '1 day') d
  union all
  select d::date
  from generate_series(
    date_trunc('month', current_date) - interval '12 months',
    date_trunc('month', current_date) - interval '11 months' - interval '1 day',
    interval '1 day') d
),
distributor_list as (
  select id, row_number() over (order by code) - 1 as idx from distributors
),
customer_list as (
  select id, sales_rep_id, row_number() over (order by cnpj) - 1 as idx from customers
),
purchases as (
  select
    d.invoice_date,
    c.id as customer_id,
    c.sales_rep_id,
    (select dl.id from distributor_list dl where dl.idx = c.idx % 3) as distributor_id,
    'NF-' || to_char(d.invoice_date, 'YYYYMMDD') || '-' || lpad(c.idx::text, 3, '0') as invoice_number
  from days d
  cross join customer_list c
  where random() < 0.42
)
insert into sell_out (distributor_id, customer_id, product_id, sales_rep_id, invoice_number, invoice_date, quantity, gross_value, unit_cost)
select
  pu.distributor_id,
  pu.customer_id,
  pp.product_id,
  pu.sales_rep_id,
  pu.invoice_number,
  pu.invoice_date,
  qty.quantity,
  round((qty.quantity * pp.unit_price)::numeric, 2),
  round((pp.unit_price * 0.78)::numeric, 4)
from purchases pu
cross join product_prices pp
cross join lateral (select (1 + floor(random() * 18))::numeric as quantity) qty
where random() < 0.30;

-- Targets: full months, per customer x product, calibrated near realized
-- volume so achievement rates are realistic.
with product_prices as (
  select
    p.id as product_id,
    18 + (('x' || substr(md5(p.ean), 1, 6))::bit(24)::int % 8000) / 100.0 as unit_price
  from products p
)
insert into sales_targets (customer_id, product_id, target_date, quantity, gross_value)
select
  c.id,
  pp.product_id,
  m.month_start,
  round((40 + random() * 60)::numeric, 0),
  round(((40 + random() * 60) * pp.unit_price * 1.02)::numeric, 2)
from customers c
cross join product_prices pp
cross join (
  select generate_series(
    date_trunc('month', current_date) - interval '2 months',
    date_trunc('month', current_date),
    interval '1 month')::date as month_start
  union all
  select (date_trunc('month', current_date) - interval '12 months')::date
) m
where random() < 0.55;

-- Sell in: monthly replenishment per distributor x product.
with product_prices as (
  select
    p.id as product_id,
    18 + (('x' || substr(md5(p.ean), 1, 6))::bit(24)::int % 8000) / 100.0 as unit_price
  from products p
)
insert into sell_in (distributor_id, product_id, invoice_number, invoice_date, quantity, gross_value, unit_cost)
select
  d.id,
  pp.product_id,
  'SI-' || to_char(m.month_start, 'YYYYMM') || '-' || d.code,
  m.month_start + 4,
  round((400 + random() * 1600)::numeric, 0),
  round(((400 + random() * 1600) * pp.unit_price * 0.78)::numeric, 2),
  round((pp.unit_price * 0.72)::numeric, 4)
from distributors d
cross join product_prices pp
cross join (
  select generate_series(
    date_trunc('month', current_date) - interval '2 months',
    date_trunc('month', current_date),
    interval '1 month')::date as month_start
) m;

-- Stock: latest snapshot per distributor x product.
with product_prices as (
  select
    p.id as product_id,
    18 + (('x' || substr(md5(p.ean), 1, 6))::bit(24)::int % 8000) / 100.0 as unit_price
  from products p
)
insert into stock_snapshots (distributor_id, product_id, snapshot_date, quantity, gross_value)
select
  d.id,
  pp.product_id,
  current_date,
  round((50 + random() * 800)::numeric, 0),
  round(((50 + random() * 800) * pp.unit_price * 0.78)::numeric, 2)
from distributors d
cross join product_prices pp;

select refresh_report_views();
