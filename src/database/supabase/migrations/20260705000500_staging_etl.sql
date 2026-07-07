-- Bulk-load staging area.
--
-- The AWS ETL Lambda COPYs raw text rows into these UNLOGGED tables (fast, no
-- WAL) and then calls the process_* functions, which validate rows, resolve
-- natural keys (code/cnpj/ean) to ids, insert into the partitioned tables and
-- write per-line rejections to file_import_logs.

create unlogged table staging_sell_out (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  customer_cnpj text,
  product_ean text,
  invoice_number text,
  invoice_date text,
  quantity text,
  gross_value text,
  unit_cost text
);

create index staging_sell_out_import_idx on staging_sell_out (import_id);

create unlogged table staging_sell_in (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  product_ean text,
  invoice_number text,
  invoice_date text,
  quantity text,
  gross_value text,
  unit_cost text
);

create index staging_sell_in_import_idx on staging_sell_in (import_id);

-- Numeric with optional decimal part, e.g. "10" or "10.5".
create or replace function fn_is_numeric(p_value text)
returns boolean
language sql
immutable
as $$
  select p_value ~ '^[0-9]+([.][0-9]+)?$'
$$;

-- ISO date, e.g. "2026-07-05".
create or replace function fn_is_iso_date(p_value text)
returns boolean
language sql
immutable
as $$
  select p_value ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
$$;

create or replace function process_sell_out_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
  -- Make sure every partition touched by this batch exists before inserting.
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
      d.id as distributor_id,
      c.id as customer_id,
      c.sales_rep_id,
      p.id as product_id,
      s.invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when d.id is null then 'unknown distributor code: ' || coalesce(s.distributor_code, '<null>')
        when c.id is null then 'unknown customer cnpj: ' || coalesce(s.customer_cnpj, '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_out s
    left join distributors d on d.code = s.distributor_code
    left join customers c on regexp_replace(c.cnpj, '\D', '', 'g') = regexp_replace(coalesce(s.customer_cnpj, ''), '\D', '', 'g')
    left join products p on p.ean = s.product_ean
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
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_month date;
begin
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
      d.id as distributor_id,
      p.id as product_id,
      s.invoice_number,
      case when fn_is_iso_date(s.invoice_date) then s.invoice_date::date end as invoice_date,
      case when fn_is_numeric(s.quantity) then s.quantity::numeric end as quantity,
      case when fn_is_numeric(s.gross_value) then s.gross_value::numeric end as gross_value,
      case when fn_is_numeric(s.unit_cost) then s.unit_cost::numeric end as unit_cost,
      case
        when d.id is null then 'unknown distributor code: ' || coalesce(s.distributor_code, '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_in s
    left join distributors d on d.code = s.distributor_code
    left join products p on p.ean = s.product_ean
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

-- Marks an import as finished, choosing the final status from the error count.
create or replace function finish_file_import(p_import_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update file_imports
  set
    status = case
      when error_count = 0 then 'completed'::import_status
      when processed_records = 0 then 'failed'::import_status
      else 'completed_with_errors'::import_status
    end,
    finished_at = now()
  where id = p_import_id;
end;
$$;
