-- Separate "nothing to import" rows from real validation errors.
--
-- A Sell Out/Sell In line with zero quantity AND zero value carries no sale:
-- rejecting it as an error made clean files look broken. Those lines are now
-- logged as warnings, counted apart from errors and no longer flip the import
-- status to completed_with_errors.

begin;

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
  add column skipped_count integer not null default 0;

-- Zero quantity and zero value means the line has no movement to record. Both
-- values must parse as numbers, otherwise the line is a real validation error.
create or replace function fn_import_row_has_no_movement(
  p_quantity text,
  p_gross_value text
)
returns boolean
language sql
immutable
as $$
  select fn_is_numeric(p_quantity)
    and fn_is_numeric(p_gross_value)
    and p_quantity::numeric = 0
    and p_gross_value::numeric = 0
$$;

-- A file whose lines were all skipped did not fail: "failed" is for files that
-- produced nothing usable at all.
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
      when processed_records + skipped_count = 0 then 'failed'::import_status
      else 'completed_with_errors'::import_status
    end,
    finished_at = now()
  where id = p_import_id;
end;
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
  v_skipped bigint := 0;
  v_processed_records integer := 0;
  v_error_count integer := 0;
  v_skipped_count integer := 0;
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
        when fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          and fn_import_row_has_no_movement(s.quantity, s.gross_value)
          then 'row without movement'
      end as skip_reason,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        -- A row with no movement is skipped, so the remaining checks would only
        -- report problems on a line that has nothing to import anyway.
        when fn_import_row_has_no_movement(s.quantity, s.gross_value) then null
        when c.id is null then 'unknown customer code/cnpj: ' ||
          coalesce(nullif(s.customer_pdv_code, ''), nullif(s.customer_cnpj, ''), '<null>')
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when nullif(btrim(s.sales_rep_code), '') is null then 'missing seller code'
        when sr.id is null then 'unknown seller code: ' || coalesce(s.sales_rep_code, '<null>')
        -- coalesce guards the empty cell: COPY reads it as NULL, and an unguarded
        -- NULL falls through every branch into a not-null column, aborting the part.
        when not coalesce(fn_is_iso_date(s.invoice_date), false)
          then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when nullif(s.delivery_date, '') is not null and not fn_is_iso_date(s.delivery_date)
          then 'invalid delivery_date: ' || coalesce(s.delivery_date, '<null>')
        when not coalesce(fn_is_numeric(s.quantity), false) or s.quantity::numeric <= 0
          then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not coalesce(fn_is_numeric(s.gross_value), false)
          then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
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
  skipped as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'warning'::import_log_level, skip_reason
    from parsed
    where skip_reason is not null
    returning 1
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error'::import_log_level, rejection_reason
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
      and skip_reason is null
    on conflict (import_id, line_number) do nothing
    returning 1
  )
  select
    count(distinct parsed.line_number) filter (
      where parsed.rejection_reason is null and parsed.skip_reason is null
    ),
    count(distinct parsed.line_number) filter (where parsed.rejection_reason is not null),
    count(distinct parsed.line_number) filter (where parsed.skip_reason is not null)
  into v_inserted, v_rejected, v_skipped
  from parsed
  cross join (select count(*) from buffered) buffered_effect
  cross join (select count(*) from rejected) rejected_effect
  cross join (select count(*) from skipped) skipped_effect
  cross join (select count(*) from cleared_staging) cleared_effect;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected,
    skipped_count = skipped_count + v_skipped
  where id = p_import_id
  returning processed_records, error_count, skipped_count, total_records
  into v_processed_records, v_error_count, v_skipped_count, v_total_records;

  if v_total_records > 0
    and v_processed_records + v_error_count + v_skipped_count >= v_total_records then
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
  v_skipped bigint := 0;
  v_processed_records integer := 0;
  v_error_count integer := 0;
  v_skipped_count integer := 0;
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
        when fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          and fn_import_row_has_no_movement(s.quantity, s.gross_value)
          then 'row without movement'
      end as skip_reason,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        -- A row with no movement is skipped, so the remaining checks would only
        -- report problems on a line that has nothing to import anyway.
        when fn_import_row_has_no_movement(s.quantity, s.gross_value) then null
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        -- coalesce guards the empty cell: COPY reads it as NULL, and an unguarded
        -- NULL falls through every branch into a not-null column, aborting the part.
        when not coalesce(fn_is_iso_date(s.invoice_date), false)
          then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when not coalesce(fn_is_numeric(s.quantity), false)
          then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not coalesce(fn_is_numeric(s.gross_value), false)
          then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
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
  skipped as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'warning'::import_log_level, skip_reason
    from parsed
    where skip_reason is not null
    returning 1
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error'::import_log_level, rejection_reason
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
      and skip_reason is null
    on conflict (import_id, line_number) do nothing
    returning 1
  )
  select
    count(distinct parsed.line_number) filter (
      where parsed.rejection_reason is null and parsed.skip_reason is null
    ),
    count(distinct parsed.line_number) filter (where parsed.rejection_reason is not null),
    count(distinct parsed.line_number) filter (where parsed.skip_reason is not null)
  into v_inserted, v_rejected, v_skipped
  from parsed
  cross join (select count(*) from buffered) buffered_effect
  cross join (select count(*) from rejected) rejected_effect
  cross join (select count(*) from skipped) skipped_effect
  cross join (select count(*) from cleared_staging) cleared_effect;

  update file_imports
  set
    processed_records = processed_records + v_inserted,
    error_count = error_count + v_rejected,
    skipped_count = skipped_count + v_skipped
  where id = p_import_id
  returning processed_records, error_count, skipped_count, total_records
  into v_processed_records, v_error_count, v_skipped_count, v_total_records;

  if v_total_records > 0
    and v_processed_records + v_error_count + v_skipped_count >= v_total_records then
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

-- The processors emit machine-readable keys; the user-facing text lives here.
-- The BEFORE INSERT trigger on file_import_logs rewrites every message through
-- this function.
create or replace function fn_format_import_log_message(
  p_import_id uuid,
  p_message text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message text := coalesce(p_message, '');
  v_detail text;
  v_distributor_code text;
  v_distributor_cnpj text;
  v_expected_distributor text;
begin
  if left(v_message, char_length('validator: ')) = 'validator: ' then
    v_message := substring(v_message from char_length('validator: ') + 1);
  end if;

  -- Answered before the distributor lookup below: this is the highest-volume
  -- message and the trigger runs once per log row.
  if v_message = 'row without movement' then
    return 'Não foi importada porque volume e valor estão zerados: não há venda a registrar.'
      || ' Nenhum dado foi perdido; ajuste a planilha apenas se esta linha deveria ter valores.';
  end if;

  select d.code, d.cnpj
  into v_distributor_code, v_distributor_cnpj
  from file_imports fi
  join distributors d on d.id = fi.distributor_id
  where fi.id = p_import_id;

  v_expected_distributor := concat_ws(
    ' ou ',
    case
      when nullif(btrim(coalesce(v_distributor_code, '')), '') is not null
        then 'código ' || btrim(v_distributor_code)
    end,
    case
      when nullif(btrim(coalesce(v_distributor_cnpj, '')), '') is not null
        then 'CNPJ ' || btrim(v_distributor_cnpj)
    end
  );

  if nullif(v_expected_distributor, '') is null then
    v_expected_distributor := 'o distribuidor vinculado à conta';
  end if;

  if left(v_message, char_length('date not activated because a newer import is already active:'))
    = 'date not activated because a newer import is already active:' then
    v_detail := fn_import_log_message_detail(
      v_message,
      'date not activated because a newer import is already active:'
    );
    return 'A data '
      || coalesce(
           case when fn_is_iso_date(v_detail) then to_char(v_detail::date, 'DD/MM/YYYY') end,
           nullif(v_detail, ''),
           'informada'
         )
      || ' foi mantida como estava porque já existe uma importação mais recente ativa para ela.'
      || ' Envie este arquivo novamente se ele deve substituir a versão atual.';
  end if;

  if left(v_message, char_length('unauthorized distributor:')) = 'unauthorized distributor:' then
    v_detail := fn_import_log_message_detail(v_message, 'unauthorized distributor:');
    return 'Distribuidor da planilha não corresponde ao distribuidor da conta. Valor informado: '
      || fn_import_log_display_value(v_detail)
      || '. Esperado: '
      || v_expected_distributor
      || '. Ajuste a coluna Distribuidor/CNPJ Distribuidor ou o cadastro do distribuidor antes de importar novamente.';
  end if;

  if left(v_message, char_length('missing required columns:')) = 'missing required columns:' then
    v_detail := fn_import_log_message_detail(v_message, 'missing required columns:');
    return 'Layout inválido: o arquivo não contém as colunas obrigatórias '
      || fn_import_log_display_value(v_detail)
      || '. Confira o modelo esperado para este tipo de importação na aba Arquivos > Configuração.';
  end if;

  if v_message = 'no data rows found' then
    return 'O arquivo não possui linhas de dados após o cabeçalho. Preencha ao menos uma linha e tente novamente.';
  end if;

  if left(v_message, char_length('import ')) = 'import '
    and right(v_message, char_length(' not found')) = ' not found' then
    return 'Registro de importação não encontrado. Envie o arquivo novamente.';
  end if;

  if left(v_message, char_length('no ETL spec for target table')) = 'no ETL spec for target table' then
    return 'Tipo de importação ainda não configurado no pipeline AWS. Verifique a configuração do tipo de arquivo.';
  end if;

  if v_message = 'missing customer pdv code' then
    return 'Cliente sem código PDV. Preencha a coluna PDV/Código PDV.';
  end if;

  if v_message = 'missing legal name' then
    return 'Cliente sem razão social. Preencha a coluna Razão Social.';
  end if;

  if v_message = 'missing product ean' then
    return 'Produto sem EAN. Preencha a coluna EAN.';
  end if;

  if v_message = 'missing product name' then
    return 'Produto sem descrição. Preencha a coluna Descrição/Nome do Produto.';
  end if;

  if v_message = 'missing macro category' then
    return 'Produto sem macrocategoria. Preencha a coluna Macrocategoria.';
  end if;

  if v_message = 'missing category' then
    return 'Produto sem categoria. Preencha a coluna Categoria.';
  end if;

  if v_message = 'missing subcategory' then
    return 'Produto sem subcategoria. Preencha a coluna Subcategoria.';
  end if;

  if v_message = 'unknown product hierarchy' then
    return 'Hierarquia do produto não encontrada. Confira Macrocategoria, Categoria e Subcategoria na mesma linha.';
  end if;

  if v_message = 'missing seller code' then
    return 'Vendedor sem código. Preencha a coluna Código do Vendedor/Vendedor.';
  end if;

  if left(v_message, char_length('unknown seller code:')) = 'unknown seller code:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown seller code:');
    return 'Vendedor não encontrado para este distribuidor. Código informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Vendedores antes de importar Sell Out ou Meta.';
  end if;

  if v_message = 'missing seller name' then
    return 'Vendedor sem nome. Preencha a coluna Nome do Vendedor.';
  end if;

  if v_message = 'missing supervisor code' then
    return 'Vendedor sem supervisor. Preencha a coluna Código do Supervisor/Supervisor.';
  end if;

  if v_message = 'missing target values' then
    return 'Meta sem valor e sem volume. Preencha ao menos uma das colunas Valor ou Quantidade.';
  end if;

  if left(v_message, char_length('unknown customer code/cnpj:')) = 'unknown customer code/cnpj:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown customer code/cnpj:');
    return 'Cliente não encontrado para este distribuidor. Valor informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Clientes antes de importar Meta. Sell Out cria o PDV automaticamente quando o código PDV é informado.';
  end if;

  if left(v_message, char_length('unknown customer cnpj:')) = 'unknown customer cnpj:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown customer cnpj:');
    return 'Cliente não encontrado para este distribuidor. CNPJ informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Clientes antes de importar Meta.';
  end if;

  if left(v_message, char_length('unknown product ean:')) = 'unknown product ean:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown product ean:');
    return 'Produto não encontrado para este distribuidor. EAN informado: '
      || fn_import_log_display_value(v_detail)
      || '. Importe ou ajuste Produtos antes de importar Sell In, Sell Out ou Meta.';
  end if;

  if left(v_message, char_length('unknown supervisor code:')) = 'unknown supervisor code:' then
    v_detail := fn_import_log_message_detail(v_message, 'unknown supervisor code:');
    return 'Supervisor não encontrado para este distribuidor. Código informado: '
      || fn_import_log_display_value(v_detail)
      || '. Confira a coluna Supervisor/Código do Supervisor.';
  end if;

  if left(v_message, char_length('invalid invoice_date:')) = 'invalid invoice_date:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid invoice_date:');
    return 'Data de faturamento inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use uma data válida no formato DD/MM/AAAA ou AAAA-MM-DD.';
  end if;

  if left(v_message, char_length('invalid delivery_date:')) = 'invalid delivery_date:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid delivery_date:');
    return 'Data de entrega inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use uma data válida no formato DD/MM/AAAA ou AAAA-MM-DD, ou deixe em branco.';
  end if;

  if left(v_message, char_length('invalid target_date:')) = 'invalid target_date:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid target_date:');
    return 'Data da meta inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use uma data válida no formato DD/MM/AAAA ou AAAA-MM-DD.';
  end if;

  if left(v_message, char_length('invalid quantity:')) = 'invalid quantity:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid quantity:');
    return 'Quantidade inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números; para Sell In e Sell Out a quantidade deve ser maior que zero.';
  end if;

  if left(v_message, char_length('invalid gross_value:')) = 'invalid gross_value:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid gross_value:');
    return 'Valor inválido: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números, por exemplo 1234,56.';
  end if;

  if left(v_message, char_length('invalid units_per_pack:')) = 'invalid units_per_pack:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid units_per_pack:');
    return 'Unidades por caixa inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use um número maior que zero.';
  end if;

  if left(v_message, char_length('invalid box_count:')) = 'invalid box_count:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid box_count:');
    return 'Quantidade de caixas inválida: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números ou deixe em branco.';
  end if;

  if left(v_message, char_length('invalid portfolio_size:')) = 'invalid portfolio_size:' then
    v_detail := fn_import_log_message_detail(v_message, 'invalid portfolio_size:');
    return 'Tamanho da carteira inválido: '
      || fn_import_log_display_value(v_detail)
      || '. Use apenas números inteiros ou deixe em branco.';
  end if;

  if p_message is distinct from v_message then
    return 'Erro de validação do arquivo: ' || v_message;
  end if;

  return p_message;
end;
$$;

revoke execute on function fn_import_row_has_no_movement(text, text) from public, anon, authenticated;
revoke execute on function fn_format_import_log_message(uuid, text) from public, anon, authenticated;
revoke execute on function finish_file_import(uuid) from public, anon, authenticated;
revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
revoke execute on function process_sell_in_staging(uuid) from public, anon, authenticated;

commit;
