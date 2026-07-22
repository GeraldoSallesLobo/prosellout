alter table staging_sell_out
  add column if not exists channel_name text,
  add column if not exists cluster_name text;

alter table staging_targets
  add column if not exists channel_name text,
  add column if not exists cluster_name text;

alter table sell_out
  add column if not exists channel_id uuid references channels(id),
  add column if not exists cluster_id uuid references clusters(id);

alter table sales_targets
  add column if not exists channel_id uuid references channels(id),
  add column if not exists cluster_id uuid references clusters(id);

create index if not exists sell_out_channel_date_idx
  on sell_out (channel_id, invoice_date);

create index if not exists sell_out_cluster_date_idx
  on sell_out (cluster_id, invoice_date);

create index if not exists sales_targets_channel_date_idx
  on sales_targets (channel_id, target_date);

create index if not exists sales_targets_cluster_date_idx
  on sales_targets (cluster_id, target_date);

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

  with parsed as (
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
    left join channels ch
      on ch.distributor_id = v_distributor_id
     and ch.name = nullif(btrim(s.channel_name), '')
    left join clusters cl
      on cl.distributor_id = v_distributor_id
     and cl.name = nullif(btrim(s.cluster_name), '')
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
      distributor_id, customer_id, product_id, sales_rep_id, channel_id, cluster_id,
      invoice_number, invoice_date, delivery_date, quantity, gross_value, unit_cost, import_id
    )
    select
      distributor_id, customer_id, product_id, sales_rep_id, channel_id, cluster_id,
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

  insert into channels (distributor_id, name, status)
  select distinct v_distributor_id, btrim(s.channel_name), 'active'::entity_status
  from staging_targets s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.channel_name), '') is not null
  on conflict (distributor_id, name) do update set
    status = 'active',
    updated_at = now();

  insert into clusters (distributor_id, name, status)
  select distinct v_distributor_id, btrim(s.cluster_name), 'active'::entity_status
  from staging_targets s
  where s.import_id = p_import_id
    and fn_import_distributor_matches(s.distributor_code, v_distributor_code, v_distributor_cnpj)
    and nullif(btrim(s.cluster_name), '') is not null
  on conflict (distributor_id, name) do update set
    status = 'active',
    updated_at = now();

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
    join sales_reps sr
      on sr.distributor_id = v_distributor_id
     and sr.role = 'seller'
     and sr.code = s.sales_rep_code
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
      sr.id as sales_rep_id,
      ch.id as channel_id,
      cl.id as cluster_id,
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
        when nullif(btrim(s.sales_rep_code), '') is null then 'missing seller code'
        when sr.id is null then 'unknown seller code: ' || coalesce(s.sales_rep_code, '<null>')
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
    left join sales_reps sr
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
  ),
  valid_rows as (
    select * from parsed where rejection_reason is null
  ),
  aggregated_rows as (
    select
      customer_id,
      product_id,
      sales_rep_id,
      target_date,
      min(channel_id::text)::uuid as channel_id,
      min(cluster_id::text)::uuid as cluster_id,
      sum(quantity) as quantity,
      sum(gross_value) as gross_value
    from valid_rows
    group by customer_id, product_id, sales_rep_id, target_date
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
      distributor_id, customer_id, product_id, sales_rep_id, channel_id, cluster_id,
      target_date, quantity, gross_value, import_id
    )
    select
      v_distributor_id, customer_id, product_id, sales_rep_id, channel_id, cluster_id,
      target_date, quantity, gross_value, p_import_id
    from aggregated_rows
    on conflict (customer_id, product_id, sales_rep_id, target_date) do update set
      distributor_id = excluded.distributor_id,
      channel_id = excluded.channel_id,
      cluster_id = excluded.cluster_id,
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

create or replace function fn_fast_facts_dimension(
  p_dimension text,
  p_current_start date,
  p_current_end date,
  p_target_start date,
  p_target_end date,
  p_previous_start date,
  p_previous_end date,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total_days integer := greatest(1, p_current_end - p_current_start + 1);
  v_elapsed_days integer;
  v_last_current_invoice_date date;
  v_result jsonb;
begin
  perform assert_authorized_distributor_scope(p_distributor_id);

  select max(so.invoice_date)
  into v_last_current_invoice_date
  from sell_out so
  where so.invoice_date between p_current_start and p_current_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id));

  v_elapsed_days := greatest(
    1,
    least(coalesce(v_last_current_invoice_date, current_date), p_current_end) - p_current_start + 1
  );

  with cur as (
    select
      case p_dimension
        when 'seller' then so.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then so.product_id
        when 'category' then sub.parent_id
        when 'channel' then coalesce(so.channel_id, c.channel_id)
        when 'customer' then so.customer_id
      end as gid,
      sum(so.gross_value) as total_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = so.customer_id
    left join sales_reps sr on sr.id = so.sales_rep_id
    where so.invoice_date between p_current_start and p_current_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    group by 1
  ),
  prev as (
    select
      case p_dimension
        when 'seller' then so.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then so.product_id
        when 'category' then sub.parent_id
        when 'channel' then coalesce(so.channel_id, c.channel_id)
        when 'customer' then so.customer_id
      end as gid,
      sum(so.gross_value) as total_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = so.customer_id
    left join sales_reps sr on sr.id = so.sales_rep_id
    where so.invoice_date between p_previous_start and p_previous_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    group by 1
  ),
  tgt as (
    select
      case p_dimension
        when 'seller' then t.sales_rep_id
        when 'supervisor' then sr.supervisor_id
        when 'product' then t.product_id
        when 'category' then sub.parent_id
        when 'channel' then coalesce(t.channel_id, c.channel_id)
        when 'customer' then t.customer_id
      end as gid,
      sum(t.gross_value) as total_value
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join customers c on c.id = t.customer_id
    left join sales_reps sr on sr.id = t.sales_rep_id
    where t.target_date between p_target_start and p_target_end
      and t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    group by 1
  ),
  joined as (
    select
      coalesce(cur.gid, tgt.gid) as gid,
      coalesce(cur.total_value, 0) as current_value,
      case when coalesce(tgt.total_value, 0) > 0 then tgt.total_value end as target_value,
      coalesce(prev.total_value, 0) as previous_value,
      case
        when coalesce(tgt.total_value, 0) > 0
          then fn_safe_div(coalesce(cur.total_value, 0), tgt.total_value)
      end as achievement,
      case
        when coalesce(tgt.total_value, 0) > 0
          then fn_ratio(coalesce(cur.total_value, 0), tgt.total_value)
      end as current_vs_target,
      fn_ratio(coalesce(cur.total_value, 0), prev.total_value) as current_vs_previous,
      case
        when coalesce(tgt.total_value, 0) > 0
          then least(1, coalesce(
            fn_safe_div(fn_safe_div(coalesce(cur.total_value, 0), v_elapsed_days) * v_total_days, tgt.total_value),
            0
          ))
        when coalesce(cur.total_value, 0) > 0
          then 1
      end as probability,
      case
        when coalesce(tgt.total_value, 0) > 0
          then coalesce(cur.total_value, 0) >= tgt.total_value
        else coalesce(cur.total_value, 0) > 0
      end as is_achieved
    from cur
    full outer join tgt on tgt.gid = cur.gid
    left join prev on prev.gid = coalesce(cur.gid, tgt.gid)
    where coalesce(cur.gid, tgt.gid) is not null
      and (coalesce(cur.total_value, 0) > 0 or coalesce(tgt.total_value, 0) > 0)
  ),
  named as (
    select
      j.*,
      coalesce(sr.name, pr.name, ph.name, ch.name, cust.legal_name, '-') as group_name
    from joined j
    left join sales_reps sr on p_dimension in ('seller', 'supervisor') and sr.id = j.gid
    left join products pr on p_dimension = 'product' and pr.id = j.gid
    left join product_hierarchy ph on p_dimension = 'category' and ph.id = j.gid
    left join channels ch on p_dimension = 'channel' and ch.id = j.gid
    left join customers cust on p_dimension = 'customer' and cust.id = j.gid
  )
  select jsonb_build_object(
    'dimension', p_dimension,
    'eligible_count', count(*),
    'achieved_count', count(*) filter (where is_achieved),
    'not_achieved_count', count(*) filter (where not is_achieved),
    'achieved_pct', fn_safe_div(count(*) filter (where is_achieved), count(*)::numeric),
    'avg_probability', avg(probability),
    'best', (
      select jsonb_build_object(
        'name', n.group_name,
        'current_value', n.current_value,
        'target_value', n.target_value,
        'previous_value', n.previous_value,
        'achievement', n.achievement,
        'current_vs_target', n.current_vs_target,
        'current_vs_previous', n.current_vs_previous
      )
      from named n
      order by (n.achievement is null), n.achievement desc nulls last, n.current_value desc
      limit 1
    ),
    'worst', (
      select jsonb_build_object(
        'name', n.group_name,
        'current_value', n.current_value,
        'target_value', n.target_value,
        'previous_value', n.previous_value,
        'achievement', n.achievement,
        'current_vs_target', n.current_vs_target,
        'current_vs_previous', n.current_vs_previous
      )
      from named n
      where n.current_value > 0
        or not exists (select 1 from named with_sales where with_sales.current_value > 0)
      order by (n.achievement is null), n.achievement asc nulls last, n.current_value asc
      limit 1
    )
  )
  into v_result
  from named;

  return coalesce(v_result, jsonb_build_object(
    'dimension', p_dimension,
    'eligible_count', 0,
    'achieved_count', 0,
    'not_achieved_count', 0,
    'achieved_pct', null,
    'avg_probability', null,
    'best', null,
    'worst', null
  ));
end;
$$;

revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
revoke execute on function process_targets_staging(uuid) from public, anon, authenticated;
revoke execute on function fn_fast_facts_dimension(text, date, date, date, date, date, date, uuid)
  from public, anon, authenticated;
