create or replace function process_products_staging(p_import_id uuid)
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
    raise exception 'process_products_staging: import % has no distributor', p_import_id;
  end if;

  insert into product_hierarchy (distributor_id, parent_id, level, name, status)
  select distinct v_distributor_id, null::uuid, 'macro_category'::hierarchy_level, btrim(s.macro_category_name), 'active'::entity_status
  from staging_products s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.macro_category_name), '') is not null
  on conflict (distributor_id, parent_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into product_hierarchy (distributor_id, parent_id, level, name, status)
  select distinct v_distributor_id, macro.id, 'category'::hierarchy_level, btrim(s.category_name), 'active'::entity_status
  from staging_products s
  join product_hierarchy macro
    on macro.distributor_id = v_distributor_id
   and macro.level = 'macro_category'
   and macro.name = btrim(s.macro_category_name)
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.category_name), '') is not null
  on conflict (distributor_id, parent_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into product_hierarchy (distributor_id, parent_id, level, name, status)
  select distinct v_distributor_id, category.id, 'subcategory'::hierarchy_level, btrim(s.subcategory_name), 'active'::entity_status
  from staging_products s
  join product_hierarchy macro
    on macro.distributor_id = v_distributor_id
   and macro.level = 'macro_category'
   and macro.name = btrim(s.macro_category_name)
  join product_hierarchy category
    on category.distributor_id = v_distributor_id
   and category.parent_id = macro.id
   and category.level = 'category'
   and category.name = btrim(s.category_name)
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.subcategory_name), '') is not null
  on conflict (distributor_id, parent_id, name) do update set
    status = 'active',
    updated_at = now();

  with parsed as (
    select
      s.line_number,
      nullif(btrim(s.product_ean), '') as product_ean,
      nullif(btrim(s.product_name), '') as product_name,
      nullif(btrim(s.sku_code), '') as sku_code,
      case
        when nullif(btrim(s.units_per_pack), '') is null then 1
        when fn_is_numeric(s.units_per_pack) then s.units_per_pack::numeric
      end as units_per_pack,
      case
        when nullif(btrim(s.box_count), '') is null then null
        when fn_is_numeric(s.box_count) then s.box_count::numeric
      end as box_count,
      subcategory.id as subcategory_id,
      case
        when not fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
          then 'unauthorized distributor: ' || coalesce(s.distributor_code, '<null>')
        when nullif(btrim(s.product_ean), '') is null then 'missing product ean'
        when nullif(btrim(s.product_name), '') is null then 'missing product name'
        when nullif(btrim(s.macro_category_name), '') is null then 'missing macro category'
        when nullif(btrim(s.category_name), '') is null then 'missing category'
        when nullif(btrim(s.subcategory_name), '') is null then 'missing subcategory'
        when nullif(btrim(s.units_per_pack), '') is not null
          and not fn_is_numeric(s.units_per_pack)
          then 'invalid units_per_pack: ' || coalesce(s.units_per_pack, '<null>')
        when fn_is_numeric(s.units_per_pack) and s.units_per_pack::numeric <= 0
          then 'invalid units_per_pack: ' || coalesce(s.units_per_pack, '<null>')
        when nullif(btrim(s.box_count), '') is not null and not fn_is_numeric(s.box_count)
          then 'invalid box_count: ' || coalesce(s.box_count, '<null>')
        when subcategory.id is null then 'unknown product hierarchy'
      end as rejection_reason
    from staging_products s
    left join product_hierarchy macro
      on macro.distributor_id = v_distributor_id
     and macro.level = 'macro_category'
     and macro.name = btrim(s.macro_category_name)
    left join product_hierarchy category
      on category.distributor_id = v_distributor_id
     and category.parent_id = macro.id
     and category.level = 'category'
     and category.name = btrim(s.category_name)
    left join product_hierarchy subcategory
      on subcategory.distributor_id = v_distributor_id
     and subcategory.parent_id = category.id
     and subcategory.level = 'subcategory'
     and subcategory.name = btrim(s.subcategory_name)
    where s.import_id = p_import_id
  ),
  valid_rows as (
    select * from parsed where rejection_reason is null
  ),
  deduped_rows as (
    select distinct on (product_ean) *
    from valid_rows
    order by product_ean, line_number desc
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  upserted as (
    insert into products (
      distributor_id, ean, sku_code, name, subcategory_id,
      unit_label, units_per_pack, box_count, status
    )
    select
      v_distributor_id, product_ean, sku_code, product_name, subcategory_id,
      'CX', units_per_pack, box_count, 'active'::entity_status
    from deduped_rows
    on conflict on constraint products_distributor_ean_key do update set
      sku_code = excluded.sku_code,
      name = excluded.name,
      subcategory_id = excluded.subcategory_id,
      unit_label = excluded.unit_label,
      units_per_pack = excluded.units_per_pack,
      box_count = excluded.box_count,
      status = 'active',
      updated_at = now()
    returning 1
  )
  select
    (select count(*) from valid_rows),
    (select count(*) from rejected)
  into v_processed, v_rejected;

  delete from staging_products where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
end;
$$;

revoke execute on function process_products_staging(uuid) from public, anon, authenticated;
