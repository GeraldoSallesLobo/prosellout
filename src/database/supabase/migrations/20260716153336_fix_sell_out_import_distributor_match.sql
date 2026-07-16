-- Hotfix for Sell Out imports that use the distributor CNPJ in the layout.
-- The staging processor must scope rows by file_imports.distributor_id and
-- validate the incoming distributor value with fn_import_distributor_matches.

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
  v_distributor_id uuid;
  v_distributor_code text;
  v_distributor_cnpj text;
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

  insert into customers (distributor_id, pdv_code, legal_name, trade_name, status)
  select distinct
    v_distributor_id,
    btrim(s.customer_pdv_code),
    'PDV ' || btrim(s.customer_pdv_code),
    'PDV ' || btrim(s.customer_pdv_code),
    'active'::entity_status
  from staging_sell_out s
  join products p
    on fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
   and p.distributor_id = v_distributor_id
  join sales_reps sr
    on sr.distributor_id = v_distributor_id
   and sr.role = 'seller'
   and sr.code = s.sales_rep_code
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
  on conflict (distributor_id, pdv_code) do nothing;

  with parsed as (
    select
      s.line_number,
      v_distributor_id as distributor_id,
      c.id as customer_id,
      sr.id as sales_rep_id,
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
        when nullif(btrim(s.sales_rep_code), '') is null then 'missing seller code'
        when sr.id is null then 'unknown seller code: ' || coalesce(s.sales_rep_code, '<null>')
        when not fn_is_iso_date(s.invoice_date) then 'invalid invoice_date: ' || coalesce(s.invoice_date, '<null>')
        when nullif(s.delivery_date, '') is not null and not fn_is_iso_date(s.delivery_date)
          then 'invalid delivery_date: ' || coalesce(s.delivery_date, '<null>')
        when not fn_is_numeric(s.quantity) or s.quantity::numeric <= 0 then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when not fn_is_numeric(s.gross_value) then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
      end as rejection_reason
    from staging_sell_out s
    left join customers c
      on c.distributor_id = v_distributor_id
     and (
       (nullif(s.customer_pdv_code, '') is not null and c.pdv_code = s.customer_pdv_code)
       or (
         nullif(s.customer_pdv_code, '') is null
         and regexp_replace(coalesce(c.cnpj, ''), '\D', '', 'g') =
           regexp_replace(coalesce(s.customer_cnpj, ''), '\D', '', 'g')
       )
     )
    left join sales_reps sr
      on sr.distributor_id = v_distributor_id
     and sr.role = 'seller'
     and sr.code = s.sales_rep_code
    left join products p
      on fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
     and p.distributor_id = v_distributor_id
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

revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
