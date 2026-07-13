-- Treat targets as a replaceable monthly plan. Re-importing a target file must
-- remove older targets for the imported months, otherwise rows removed from a
-- corrected spreadsheet would stay active in reports.

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

  with valid_target_months as (
    select distinct date_trunc('month', s.target_date::date)::date as target_date
    from staging_targets s
    join lateral (
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
    join lateral (
      select p.id
      from products p
      where fn_ean_core(p.ean) = fn_ean_core(s.product_ean)
        and p.distributor_id = v_distributor_id
      order by p.created_at, p.id
      limit 1
    ) p on true
    where s.import_id = p_import_id
      and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
      and fn_is_iso_date(s.target_date)
  )
  delete from sales_targets st
  using valid_target_months vtm
  where st.distributor_id = v_distributor_id
    and st.target_date = vtm.target_date
    and st.import_id is distinct from p_import_id;

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

revoke execute on function process_targets_staging(uuid) from public, anon, authenticated;
