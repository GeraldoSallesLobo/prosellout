-- High-volume transactional tables.
--
-- sell_out and sell_in are range-partitioned by month so that:
--   * MTD report queries prune to a single partition;
--   * bulk loads touch only the partitions of the loaded period;
--   * old data can be archived with a cheap DROP/DETACH PARTITION.

create table sell_out (
  id bigint generated always as identity,
  distributor_id uuid not null references distributors(id),
  customer_id uuid not null references customers(id),
  product_id uuid not null references products(id),
  sales_rep_id uuid references sales_reps(id),
  invoice_number text,
  invoice_date date not null,
  quantity numeric(14, 3) not null check (quantity > 0),
  gross_value numeric(14, 2) not null check (gross_value >= 0),
  unit_cost numeric(14, 4),
  import_id uuid references file_imports(id),
  created_at timestamptz not null default now(),
  primary key (id, invoice_date)
) partition by range (invoice_date);

create index sell_out_date_distributor_idx on sell_out (invoice_date, distributor_id);
create index sell_out_product_idx on sell_out (product_id, invoice_date);
create index sell_out_customer_idx on sell_out (customer_id, invoice_date);
create index sell_out_sales_rep_idx on sell_out (sales_rep_id, invoice_date);

create table sell_in (
  id bigint generated always as identity,
  distributor_id uuid not null references distributors(id),
  product_id uuid not null references products(id),
  invoice_number text,
  invoice_date date not null,
  quantity numeric(14, 3) not null check (quantity > 0),
  gross_value numeric(14, 2) not null check (gross_value >= 0),
  unit_cost numeric(14, 4),
  import_id uuid references file_imports(id),
  created_at timestamptz not null default now(),
  primary key (id, invoice_date)
) partition by range (invoice_date);

create index sell_in_date_distributor_idx on sell_in (invoice_date, distributor_id);
create index sell_in_product_idx on sell_in (product_id, invoice_date);

create table stock_snapshots (
  id bigint generated always as identity primary key,
  distributor_id uuid not null references distributors(id),
  product_id uuid not null references products(id),
  snapshot_date date not null,
  quantity numeric(14, 3) not null,
  gross_value numeric(14, 2) not null default 0,
  import_id uuid references file_imports(id),
  created_at timestamptz not null default now(),
  unique (distributor_id, product_id, snapshot_date)
);

create index stock_snapshots_date_idx on stock_snapshots (snapshot_date);

create table sales_targets (
  id bigint generated always as identity primary key,
  customer_id uuid not null references customers(id),
  product_id uuid not null references products(id),
  target_date date not null,
  quantity numeric(14, 3) not null default 0,
  gross_value numeric(14, 2) not null default 0,
  import_id uuid references file_imports(id),
  created_at timestamptz not null default now(),
  unique (customer_id, product_id, target_date)
);

create index sales_targets_date_idx on sales_targets (target_date);

-- ---------------------------------------------------------------------------
-- Partition management
-- ---------------------------------------------------------------------------

-- Creates the monthly partition that contains p_month, when missing.
-- Called by migrations/seed, by the ETL loader before a bulk load and by a
-- monthly pg_cron job that keeps partitions ahead of time.
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
  end if;
end;
$$;

-- Bootstrap a rolling window of partitions: 24 months back, 3 months ahead.
do $$
declare
  v_month date;
begin
  for v_month in
    select generate_series(
      date_trunc('month', now()) - interval '24 months',
      date_trunc('month', now()) + interval '3 months',
      interval '1 month'
    )::date
  loop
    perform ensure_month_partition('sell_out', v_month);
    perform ensure_month_partition('sell_in', v_month);
  end loop;
end;
$$;

-- Keep future partitions created automatically (day 25 of every month).
select cron.schedule(
  'create-next-month-partitions',
  '0 3 25 * *',
  $$
    select ensure_month_partition('sell_out', (now() + interval '2 months')::date);
    select ensure_month_partition('sell_in', (now() + interval '2 months')::date);
  $$
);
