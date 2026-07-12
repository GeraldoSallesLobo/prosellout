-- Local stress seed for the Status MTD channel chart.
-- Run after the generated sample seed to add 65 extra active channels with
-- current, previous, and target values in July 2026.

select ensure_month_partition('sell_out', '2026-06-01'::date);
select ensure_month_partition('sell_out', '2026-07-01'::date);

with constants as (
  select
    'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id
),
channel_seed as (
  select
    series_number,
    'Stress Channel ' || lpad(series_number::text, 2, '0') as channel_name
  from generate_series(1, 65) as series_number
)
insert into channels (distributor_id, name, status)
select
  constants.distributor_id,
  channel_seed.channel_name,
  'active'::entity_status
from channel_seed
cross join constants
on conflict (distributor_id, name) do update set
  status = excluded.status,
  updated_at = now();

with constants as (
  select
    'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id,
    '4fd7c37a-5299-5b65-a8dc-5b38da651ef4'::uuid as cluster_id
),
channel_seed as (
  select
    series_number,
    'Stress Channel ' || lpad(series_number::text, 2, '0') as channel_name,
    'MANY-CHANNELS-PDV-' || lpad(series_number::text, 2, '0') as pdv_code
  from generate_series(1, 65) as series_number
),
seller_seed as (
  select
    id,
    row_number() over (order by code nulls last, name) as row_number,
    count(*) over () as row_count
  from sales_reps
  where distributor_id = (select distributor_id from constants)
    and role = 'seller'
    and status = 'active'
)
insert into customers (
  distributor_id,
  cnpj,
  legal_name,
  trade_name,
  address,
  district,
  city,
  state,
  zip_code,
  channel_id,
  cluster_id,
  sales_rep_id,
  pdv_code,
  status
)
select
  constants.distributor_id,
  (97000000000000 + channel_seed.series_number)::text,
  'Stress Customer ' || lpad(channel_seed.series_number::text, 2, '0'),
  'Stress Customer ' || lpad(channel_seed.series_number::text, 2, '0'),
  'Local seed address',
  'LOCAL',
  'CURITIBA',
  'PR',
  '80000000',
  channels.id,
  constants.cluster_id,
  seller_seed.id,
  channel_seed.pdv_code,
  'active'::entity_status
from channel_seed
cross join constants
join channels
  on channels.distributor_id = constants.distributor_id
 and channels.name = channel_seed.channel_name
join seller_seed
  on seller_seed.row_number = ((channel_seed.series_number - 1) % seller_seed.row_count) + 1
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
  sales_rep_id = excluded.sales_rep_id,
  status = excluded.status,
  updated_at = now();

with constants as (
  select 'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id
)
delete from sell_out
using customers
where sell_out.customer_id = customers.id
  and customers.distributor_id = (select distributor_id from constants)
  and customers.pdv_code like 'MANY-CHANNELS-PDV-%';

with constants as (
  select 'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id
)
delete from sales_targets
using customers
where sales_targets.customer_id = customers.id
  and customers.distributor_id = (select distributor_id from constants)
  and customers.pdv_code like 'MANY-CHANNELS-PDV-%';

with constants as (
  select 'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id
),
customer_seed as (
  select
    customers.id as customer_id,
    customers.sales_rep_id,
    row_number() over (order by customers.pdv_code) as row_number
  from customers
  where customers.distributor_id = (select distributor_id from constants)
    and customers.pdv_code like 'MANY-CHANNELS-PDV-%'
),
product_seed as (
  select
    id,
    row_number() over (order by sku_code, name) as row_number,
    count(*) over () as row_count
  from products
  where distributor_id = (select distributor_id from constants)
    and status = 'active'
)
insert into sell_out (
  distributor_id,
  customer_id,
  product_id,
  sales_rep_id,
  invoice_number,
  invoice_date,
  quantity,
  gross_value,
  unit_cost
)
select
  constants.distributor_id,
  customer_seed.customer_id,
  product_seed.id,
  customer_seed.sales_rep_id,
  'MANY-CHANNELS-202607-' || lpad(customer_seed.row_number::text, 2, '0'),
  '2026-07-01'::date + ((customer_seed.row_number - 1) % 12),
  (120 + customer_seed.row_number)::numeric(14, 3),
  (52000 - (customer_seed.row_number * 520))::numeric(14, 2),
  ((52000 - (customer_seed.row_number * 520)) / (120 + customer_seed.row_number) * 0.62)::numeric(14, 4)
from customer_seed
cross join constants
join product_seed
  on product_seed.row_number = ((customer_seed.row_number - 1) % product_seed.row_count) + 1;

with constants as (
  select 'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id
),
customer_seed as (
  select
    customers.id as customer_id,
    customers.sales_rep_id,
    row_number() over (order by customers.pdv_code) as row_number
  from customers
  where customers.distributor_id = (select distributor_id from constants)
    and customers.pdv_code like 'MANY-CHANNELS-PDV-%'
),
product_seed as (
  select
    id,
    row_number() over (order by sku_code, name) as row_number,
    count(*) over () as row_count
  from products
  where distributor_id = (select distributor_id from constants)
    and status = 'active'
)
insert into sell_out (
  distributor_id,
  customer_id,
  product_id,
  sales_rep_id,
  invoice_number,
  invoice_date,
  quantity,
  gross_value,
  unit_cost
)
select
  constants.distributor_id,
  customer_seed.customer_id,
  product_seed.id,
  customer_seed.sales_rep_id,
  'MANY-CHANNELS-202606-' || lpad(customer_seed.row_number::text, 2, '0'),
  '2026-06-01'::date + ((customer_seed.row_number - 1) % 12),
  (110 + customer_seed.row_number)::numeric(14, 3),
  ((52000 - (customer_seed.row_number * 520)) * 0.82)::numeric(14, 2),
  (((52000 - (customer_seed.row_number * 520)) * 0.82) / (110 + customer_seed.row_number) * 0.64)::numeric(14, 4)
from customer_seed
cross join constants
join product_seed
  on product_seed.row_number = ((customer_seed.row_number - 1) % product_seed.row_count) + 1;

with constants as (
  select 'ea6289a9-888c-564b-ae58-d2f465b09b86'::uuid as distributor_id
),
customer_seed as (
  select
    customers.id as customer_id,
    row_number() over (order by customers.pdv_code) as row_number
  from customers
  where customers.distributor_id = (select distributor_id from constants)
    and customers.pdv_code like 'MANY-CHANNELS-PDV-%'
),
product_seed as (
  select
    id,
    row_number() over (order by sku_code, name) as row_number,
    count(*) over () as row_count
  from products
  where distributor_id = (select distributor_id from constants)
    and status = 'active'
)
insert into sales_targets (
  distributor_id,
  customer_id,
  product_id,
  target_date,
  quantity,
  gross_value
)
select
  constants.distributor_id,
  customer_seed.customer_id,
  product_seed.id,
  '2026-07-01'::date,
  (150 + customer_seed.row_number)::numeric(14, 3),
  ((52000 - (customer_seed.row_number * 520)) * 1.18)::numeric(14, 2)
from customer_seed
cross join constants
join product_seed
  on product_seed.row_number = ((customer_seed.row_number - 1) % product_seed.row_count) + 1
on conflict (customer_id, product_id, target_date) do update set
  distributor_id = excluded.distributor_id,
  quantity = excluded.quantity,
  gross_value = excluded.gross_value,
  created_at = now();

select refresh_report_views();
