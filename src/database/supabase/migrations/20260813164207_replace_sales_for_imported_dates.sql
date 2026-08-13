-- Treat Sell Out and Sell In files as date-scoped snapshots.
--
-- Valid rows are buffered in logged tables while independent SQS parts are
-- processed. The completed import is activated atomically so a failed part
-- cannot replace the previous snapshot with partial data. Distributor locks
-- serialize overlapping imports, and a completed newer import always wins.

-- The whole migration runs in one explicit transaction: the Supabase CLI
-- executes statements individually in autocommit mode, where a bare LOCK TABLE
-- is rejected (25P01) and would be released immediately anyway.
begin;

-- The old processors write each part directly to the final tables. Holding an
-- exclusive lock makes the transition race-safe and also protects the
-- server-generated sequence used to order competing imports.
lock table file_imports in access exclusive mode;

do $$
begin
  if exists (
    select 1
    from file_imports fi
    join file_type_configs config on config.id = fi.file_type_id
    where fi.status = 'processing'
      and config.target_table in ('sell_out', 'sell_in')
  ) then
    raise exception using
      message = 'Cannot replace sales import processors while Sell Out or Sell In imports are processing',
      hint = 'Wait for active sales imports to finish, then apply this migration again.';
  end if;
end;
$$;

alter table file_imports
  add column ingestion_sequence bigint generated always as identity;

alter table file_imports
  add constraint file_imports_ingestion_sequence_key unique (ingestion_sequence);

create table file_import_processed_lines (
  import_id uuid not null references file_imports(id) on delete cascade,
  line_number integer not null,
  created_at timestamptz not null default now(),
  primary key (import_id, line_number)
);

create table pending_sell_out_import_rows (
  import_id uuid not null references file_imports(id) on delete cascade,
  line_number integer not null,
  distributor_id uuid not null references distributors(id),
  customer_id uuid not null references customers(id),
  product_id uuid not null references products(id),
  sales_rep_id uuid references sales_reps(id),
  channel_id uuid references channels(id),
  cluster_id uuid references clusters(id),
  invoice_number text,
  invoice_date date not null,
  delivery_date date,
  quantity numeric(14, 3) not null check (quantity > 0),
  gross_value numeric(14, 2) not null check (gross_value >= 0),
  unit_cost numeric(14, 4),
  primary key (import_id, line_number)
);

create index pending_sell_out_import_date_idx
  on pending_sell_out_import_rows (import_id, invoice_date);

create table pending_sell_in_import_rows (
  import_id uuid not null references file_imports(id) on delete cascade,
  line_number integer not null,
  distributor_id uuid not null references distributors(id),
  product_id uuid not null references products(id),
  invoice_number text,
  invoice_date date not null,
  quantity numeric(14, 3) not null check (quantity > 0),
  gross_value numeric(14, 2) not null check (gross_value >= 0),
  unit_cost numeric(14, 4),
  primary key (import_id, line_number)
);

create index pending_sell_in_import_date_idx
  on pending_sell_in_import_rows (import_id, invoice_date);

alter table file_import_processed_lines enable row level security;
alter table pending_sell_out_import_rows enable row level security;
alter table pending_sell_in_import_rows enable row level security;

revoke all on file_import_processed_lines from public, anon, authenticated;
revoke all on pending_sell_out_import_rows from public, anon, authenticated;
revoke all on pending_sell_in_import_rows from public, anon, authenticated;

create or replace function process_sell_out_staging(p_import_id uuid)
returns table (inserted_count bigint, rejected_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted bigint := 0;
  v_rejected bigint := 0;
  v_processed_records integer := 0;
  v_error_count integer := 0;
  v_total_records integer := 0;
  v_activated_dates date[] := '{}'::date[];
  v_month date;
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_import_status import_status;
  v_import_sequence bigint;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_sell_out_staging: import % has no distributor', p_import_id;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('sell_out_import'),
    hashtext(v_distributor_id::text)
  );

  select fi.status, fi.total_records, fi.ingestion_sequence
  into v_import_status, v_total_records, v_import_sequence
  from file_imports fi
  where fi.id = p_import_id;

  if v_import_status in ('completed', 'completed_with_errors', 'failed') then
    delete from staging_sell_out where import_id = p_import_id;
    delete from pending_sell_out_import_rows where import_id = p_import_id;
    delete from file_import_processed_lines where import_id = p_import_id;
    return query select 0::bigint, 0::bigint;
    return;
  end if;

  insert into channels (distributor_id, name, status)
  select distinct v_distributor_id, btrim(s.channel_name), 'active'::entity_status
  from staging_sell_out s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.channel_name), '') is not null
  on conflict (distributor_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into clusters (distributor_id, name, status)
  select distinct v_distributor_id, btrim(s.cluster_name), 'active'::entity_status
  from staging_sell_out s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.cluster_name), '') is not null
  on conflict (distributor_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into customers (
    distributor_id, pdv_code, legal_name, trade_name, channel_id, cluster_id, status
  )
  select distinct on (btrim(s.customer_pdv_code))
    v_distributor_id,
    btrim(s.customer_pdv_code),
    'PDV ' || btrim(s.customer_pdv_code),
    'PDV ' || btrim(s.customer_pdv_code),
    ch.id,
    cl.id,
    'active'::entity_status
  from staging_sell_out s
  join products p
    on fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
   and p.distributor_id = v_distributor_id
  join sales_reps sr
    on sr.distributor_id = v_distributor_id
   and sr.role = 'seller'
   and sr.code = s.sales_rep_code
  left join channels ch
    on ch.distributor_id = v_distributor_id
   and ch.name = nullif(btrim(s.channel_name), '')
  left join clusters cl
    on cl.distributor_id = v_distributor_id
   and cl.name = nullif(btrim(s.cluster_name), '')
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.customer_pdv_code), '') is not null
    and fn_is_iso_date(s.invoice_date)
    and fn_is_numeric(s.quantity)
    and s.quantity::numeric > 0
    and fn_is_numeric(s.gross_value)
    and not exists (
      select 1
      from customers c
      where c.distributor_id = v_distributor_id
        and c.pdv_code = btrim(s.customer_pdv_code)
    )
  order by btrim(s.customer_pdv_code), s.line_number desc
  on conflict (distributor_id, pdv_code) do nothing;

  with source_rows as materialized (
    select distinct on (s.line_number) s.*
    from staging_sell_out s
    where s.import_id = p_import_id
    order by s.line_number
  ),
  claimed_lines as (
    insert into file_import_processed_lines (import_id, line_number)
    select p_import_id, s.line_number
    from source_rows s
    on conflict (import_id, line_number) do nothing
    returning line_number
  ),
  cleared_staging as (
    delete from staging_sell_out staged
    using source_rows source
    where staged.import_id = p_import_id
      and staged.line_number = source.line_number
    returning 1
  ),
  parsed as (
    select
      s.line_number,
      v_distributor_id as distributor_id,
      c.id as customer_id,
      sr.id as sales_rep_id,
      p.id as product_id,
      ch.id as channel_id,
      cl.id as cluster_id,
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
        when nullif(btrim(s.sales_rep_code), '') is null then 'missing seller code'
        when sr.id is null then 'unknown seller code: ' || coalesce(s.sales_rep_code, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when nullif(s.delivery_date, '') is not null and not fn_is_iso_date(s.delivery_date)
          then 'invalid delivery_date: ' || coalesce(s.delivery_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from source_rows s
    join claimed_lines claimed on claimed.line_number = s.line_number
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
    left join sales_reps sr
      on sr.distributor_id = v_distributor_id
     and sr.role = 'seller'
     and sr.code = s.sales_rep_code
    left join lateral (
      select p.id
      from products p
      where fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
        and p.distributor_id = v_distributor_id
      order by p.created_at, p.id
      limit 1
    ) p on true
    left join channels ch
      on ch.distributor_id = v_distributor_id
     and ch.name = nullif(btrim(s.channel_name), '')
    left join clusters cl
      on cl.distributor_id = v_distributor_id
     and cl.name = nullif(btrim(s.cluster_name), '')
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  buffered as (
    insert into pending_sell_out_import_rows (
      import_id, line_number, distributor_id, customer_id, product_id, sales_rep_id,
      channel_id, cluster_id, invoice_number, invoice_date, delivery_date,
      quantity, gross_value, unit_cost
    )
    select
      p_import_id, line_number, distributor_id, customer_id, product_id, sales_rep_id,
      channel_id, cluster_id, invoice_number, invoice_date, delivery_date,
      quantity, gross_value, unit_cost
    from parsed
    where rejection_reason is null
    on conflict (import_id, line_number) do nothing
    returning 1
  )
  select
    count(distinct parsed.line_number) filter (where parsed.rejection_reason is null),
    count(distinct parsed.line_number) filter (where parsed.rejection_reason is not null)
  into v_inserted, v_rejected
  from parsed
  cross join (select count(*) from buffered) buffered_effect
  cross join (select count(*) from rejected) rejected_effect
  cross join (select count(*) from cleared_staging) cleared_effect;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected
  where id = p_import_id
  returning processed_records, error_count, total_records
  into v_processed_records, v_error_count, v_total_records;

  if v_total_records > 0 and v_processed_records + v_error_count >= v_total_records then
    for v_month in
      select distinct date_trunc('month', pending.invoice_date)::date
      from pending_sell_out_import_rows pending
      where pending.import_id = p_import_id
    loop
      perform ensure_month_partition('sell_out', v_month);
    end loop;

    select coalesce(array_agg(pending.invoice_date), '{}'::date[])
    into v_activated_dates
    from (
      select distinct rows.invoice_date
      from pending_sell_out_import_rows rows
      where rows.import_id = p_import_id
    ) pending
    where not exists (
        select 1
        from sell_out current_rows
        join file_imports current_import on current_import.id = current_rows.import_id
        where current_rows.distributor_id = v_distributor_id
          and current_rows.invoice_date = pending.invoice_date
          and current_rows.import_id is distinct from p_import_id
          and current_import.status in ('completed', 'completed_with_errors')
          and current_import.ingestion_sequence > v_import_sequence
      );

    insert into file_import_logs (import_id, level, message)
    select
      p_import_id,
      'warning'::import_log_level,
      'date not activated because a newer import is already active: ' || pending.invoice_date::text
    from (
      select distinct rows.invoice_date
      from pending_sell_out_import_rows rows
      where rows.import_id = p_import_id
    ) pending
    where not (pending.invoice_date = any(v_activated_dates));

    delete from sell_out current_rows
    where current_rows.distributor_id = v_distributor_id
      and current_rows.invoice_date = any(v_activated_dates)
      and current_rows.import_id is distinct from p_import_id;

    insert into sell_out (
      distributor_id, customer_id, product_id, sales_rep_id, channel_id, cluster_id,
      invoice_number, invoice_date, delivery_date, quantity, gross_value, unit_cost, import_id
    )
    select
      pending.distributor_id, pending.customer_id, pending.product_id,
      pending.sales_rep_id, pending.channel_id, pending.cluster_id,
      pending.invoice_number, pending.invoice_date, pending.delivery_date,
      pending.quantity, pending.gross_value, pending.unit_cost, pending.import_id
    from pending_sell_out_import_rows pending
    where pending.import_id = p_import_id
      and pending.invoice_date = any(v_activated_dates);

    perform finish_file_import(p_import_id);
    delete from pending_sell_out_import_rows where import_id = p_import_id;
    delete from file_import_processed_lines where import_id = p_import_id;
  end if;

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
  v_processed_records integer := 0;
  v_error_count integer := 0;
  v_total_records integer := 0;
  v_activated_dates date[] := '{}'::date[];
  v_month date;
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_import_status import_status;
  v_import_sequence bigint;
begin
  select fi.distributor_id, d.code, d.cnpj
  into v_distributor_id, v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  if v_distributor_id is null then
    raise exception 'process_sell_in_staging: import % has no distributor', p_import_id;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('sell_in_import'),
    hashtext(v_distributor_id::text)
  );

  select fi.status, fi.total_records, fi.ingestion_sequence
  into v_import_status, v_total_records, v_import_sequence
  from file_imports fi
  where fi.id = p_import_id;

  if v_import_status in ('completed', 'completed_with_errors', 'failed') then
    delete from staging_sell_in where import_id = p_import_id;
    delete from pending_sell_in_import_rows where import_id = p_import_id;
    delete from file_import_processed_lines where import_id = p_import_id;
    return query select 0::bigint, 0::bigint;
    return;
  end if;

  with source_rows as materialized (
    select distinct on (s.line_number) s.*
    from staging_sell_in s
    where s.import_id = p_import_id
    order by s.line_number
  ),
  claimed_lines as (
    insert into file_import_processed_lines (import_id, line_number)
    select p_import_id, s.line_number
    from source_rows s
    on conflict (import_id, line_number) do nothing
    returning line_number
  ),
  cleared_staging as (
    delete from staging_sell_in staged
    using source_rows source
    where staged.import_id = p_import_id
      and staged.line_number = source.line_number
    returning 1
  ),
  parsed as (
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
    from source_rows s
    join claimed_lines claimed on claimed.line_number = s.line_number
    left join lateral (
      select p.id
      from products p
      where fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
        and (p.distributor_id is null or p.distributor_id = v_distributor_id)
      order by case when p.distributor_id = v_distributor_id then 0 else 1 end, p.created_at, p.id
      limit 1
    ) p on true
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  buffered as (
    insert into pending_sell_in_import_rows (
      import_id, line_number, distributor_id, product_id, invoice_number,
      invoice_date, quantity, gross_value, unit_cost
    )
    select
      p_import_id, line_number, distributor_id, product_id, invoice_number,
      invoice_date, quantity, gross_value, unit_cost
    from parsed
    where rejection_reason is null
    on conflict (import_id, line_number) do nothing
    returning 1
  )
  select
    count(distinct parsed.line_number) filter (where parsed.rejection_reason is null),
    count(distinct parsed.line_number) filter (where parsed.rejection_reason is not null)
  into v_inserted, v_rejected
  from parsed
  cross join (select count(*) from buffered) buffered_effect
  cross join (select count(*) from rejected) rejected_effect
  cross join (select count(*) from cleared_staging) cleared_effect;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected
  where id = p_import_id
  returning processed_records, error_count, total_records
  into v_processed_records, v_error_count, v_total_records;

  if v_total_records > 0 and v_processed_records + v_error_count >= v_total_records then
    for v_month in
      select distinct date_trunc('month', pending.invoice_date)::date
      from pending_sell_in_import_rows pending
      where pending.import_id = p_import_id
    loop
      perform ensure_month_partition('sell_in', v_month);
    end loop;

    select coalesce(array_agg(pending.invoice_date), '{}'::date[])
    into v_activated_dates
    from (
      select distinct rows.invoice_date
      from pending_sell_in_import_rows rows
      where rows.import_id = p_import_id
    ) pending
    where not exists (
        select 1
        from sell_in current_rows
        join file_imports current_import on current_import.id = current_rows.import_id
        where current_rows.distributor_id = v_distributor_id
          and current_rows.invoice_date = pending.invoice_date
          and current_rows.import_id is distinct from p_import_id
          and current_import.status in ('completed', 'completed_with_errors')
          and current_import.ingestion_sequence > v_import_sequence
      );

    insert into file_import_logs (import_id, level, message)
    select
      p_import_id,
      'warning'::import_log_level,
      'date not activated because a newer import is already active: ' || pending.invoice_date::text
    from (
      select distinct rows.invoice_date
      from pending_sell_in_import_rows rows
      where rows.import_id = p_import_id
    ) pending
    where not (pending.invoice_date = any(v_activated_dates));

    delete from sell_in current_rows
    where current_rows.distributor_id = v_distributor_id
      and current_rows.invoice_date = any(v_activated_dates)
      and current_rows.import_id is distinct from p_import_id;

    insert into sell_in (
      distributor_id, product_id, invoice_number, invoice_date,
      quantity, gross_value, unit_cost, import_id
    )
    select
      pending.distributor_id, pending.product_id, pending.invoice_number,
      pending.invoice_date, pending.quantity, pending.gross_value,
      pending.unit_cost, pending.import_id
    from pending_sell_in_import_rows pending
    where pending.import_id = p_import_id
      and pending.invoice_date = any(v_activated_dates);

    perform finish_file_import(p_import_id);
    delete from pending_sell_in_import_rows where import_id = p_import_id;
    delete from file_import_processed_lines where import_id = p_import_id;
  end if;

  return query select v_inserted, v_rejected;
end;
$$;

revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
revoke execute on function process_sell_in_staging(uuid) from public, anon, authenticated;

commit;
