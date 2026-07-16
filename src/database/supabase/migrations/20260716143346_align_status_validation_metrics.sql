-- Align the imported QA sample with the Status MTD validation worksheet.
--
-- The real files confirmed three gaps:
-- - Sell Out rows may introduce PDVs that are not present in Clientes yet. Those
--   rows must still feed sales totals, so Sell Out creates a minimal PDV stub.
--   Meta keeps requiring an existing customer.
-- - Meta is seller-scoped in the layout and must store the seller relationship
--   instead of inferring it from the customer portfolio.
-- - Status MTD follows a monthly worksheet. Value/volume use the selected date
--   range, while coverage/ticket use the month at the start of each period.

alter table sales_targets
  add column if not exists sales_rep_id uuid references sales_reps(id);

alter table sales_targets
  drop constraint if exists sales_targets_customer_id_product_id_target_date_key;

alter table sales_targets
  drop constraint if exists sales_targets_customer_product_seller_target_key;

alter table sales_targets
  add constraint sales_targets_customer_product_seller_target_key
  unique nulls not distinct (customer_id, product_id, sales_rep_id, target_date);

create index if not exists sales_targets_sales_rep_date_idx
  on sales_targets (sales_rep_id, target_date);

create or replace function validate_distributor_relationships()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'product_hierarchy' then
    if new.parent_id is not null and not exists (
      select 1
      from product_hierarchy parent
      where parent.id = new.parent_id
        and parent.distributor_id = new.distributor_id
    ) then
      raise exception 'product_hierarchy parent belongs to another distributor';
    end if;
  elsif tg_table_name = 'products' then
    if not exists (
      select 1
      from product_hierarchy ph
      where ph.id = new.subcategory_id
        and ph.distributor_id = new.distributor_id
    ) then
      raise exception 'product hierarchy belongs to another distributor';
    end if;
  elsif tg_table_name = 'sales_reps' then
    if new.manager_id is not null and not exists (
      select 1
      from sales_reps manager
      where manager.id = new.manager_id
        and manager.distributor_id = new.distributor_id
    ) then
      raise exception 'manager belongs to another distributor';
    end if;

    if new.supervisor_id is not null and not exists (
      select 1
      from sales_reps supervisor
      where supervisor.id = new.supervisor_id
        and supervisor.distributor_id = new.distributor_id
    ) then
      raise exception 'supervisor belongs to another distributor';
    end if;
  elsif tg_table_name = 'customers' then
    if new.channel_id is not null and not exists (
      select 1
      from channels ch
      where ch.id = new.channel_id
        and ch.distributor_id = new.distributor_id
    ) then
      raise exception 'channel belongs to another distributor';
    end if;

    if new.cluster_id is not null and not exists (
      select 1
      from clusters cl
      where cl.id = new.cluster_id
        and cl.distributor_id = new.distributor_id
    ) then
      raise exception 'cluster belongs to another distributor';
    end if;

    if new.sales_rep_id is not null and not exists (
      select 1
      from sales_reps sr
      where sr.id = new.sales_rep_id
        and sr.distributor_id = new.distributor_id
    ) then
      raise exception 'sales rep belongs to another distributor';
    end if;
  elsif tg_table_name = 'file_imports' then
    if new.imported_by is not null and not exists (
      select 1
      from distributor_users du
      where du.user_id = new.imported_by
        and du.distributor_id = new.distributor_id
        and du.status = 'active'
    ) then
      raise exception 'import user is not linked to distributor';
    end if;
  elsif tg_table_name = 'sales_targets' then
    if not exists (
      select 1
      from customers c
      where c.id = new.customer_id
        and c.distributor_id = new.distributor_id
    ) then
      raise exception 'target customer belongs to another distributor';
    end if;

    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'target product belongs to another distributor';
    end if;

    if new.sales_rep_id is not null and not exists (
      select 1
      from sales_reps sr
      where sr.id = new.sales_rep_id
        and sr.distributor_id = new.distributor_id
    ) then
      raise exception 'target sales rep belongs to another distributor';
    end if;
  elsif tg_table_name = 'stock_snapshots' then
    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'stock product belongs to another distributor';
    end if;
  elsif tg_table_name = 'sell_out' then
    if not exists (
      select 1
      from customers c
      where c.id = new.customer_id
        and c.distributor_id = new.distributor_id
    ) then
      raise exception 'sell out customer belongs to another distributor';
    end if;

    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'sell out product belongs to another distributor';
    end if;

    if new.sales_rep_id is not null and not exists (
      select 1
      from sales_reps sr
      where sr.id = new.sales_rep_id
        and sr.distributor_id = new.distributor_id
    ) then
      raise exception 'sell out sales rep belongs to another distributor';
    end if;
  elsif tg_table_name = 'sell_in' then
    if not exists (
      select 1
      from products p
      where p.id = new.product_id
        and p.distributor_id = new.distributor_id
    ) then
      raise exception 'sell in product belongs to another distributor';
    end if;
  end if;

  if tg_table_name in ('sales_targets', 'stock_snapshots', 'sell_out', 'sell_in') then
    if new.import_id is not null then
      if not exists (
        select 1
        from file_imports fi
        where fi.id = new.import_id
          and fi.distributor_id = new.distributor_id
      ) then
        raise exception 'import belongs to another distributor';
      end if;
    end if;
  end if;

  return new;
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
      distributor_id, customer_id, product_id, sales_rep_id, target_date,
      quantity, gross_value, import_id
    )
    select
      v_distributor_id, customer_id, product_id, sales_rep_id, target_date,
      quantity, gross_value, p_import_id
    from aggregated_rows
    on conflict (customer_id, product_id, sales_rep_id, target_date) do update set
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

create or replace function fn_sell_out_metrics(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric,
  total_cost numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(so.gross_value), 0)::numeric,
    coalesce(sum(so.quantity), 0)::numeric,
    coalesce(sum(so.quantity * coalesce(so.unit_cost, 0)), 0)::numeric,
    count(distinct so.customer_id) filter (
      where date_trunc('month', so.invoice_date)::date = date_trunc('month', p_start)::date
    ),
    count(*)::bigint
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  left join sales_reps sr on sr.id = so.sales_rep_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_sell_out_last_invoice_date(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select max(so.invoice_date)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  left join sales_reps sr on sr.id = so.sales_rep_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or so.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function fn_target_metrics(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric,
  coverage bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(t.gross_value), 0)::numeric,
    coalesce(sum(t.quantity), 0)::numeric,
    count(distinct t.customer_id) filter (
      where date_trunc('month', t.target_date)::date = date_trunc('month', p_start)::date
    )
  from sales_targets t
  join products p on p.id = t.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = t.customer_id
  left join sales_reps sr on sr.id = t.sales_rep_id
  where t.target_date between p_start and p_end
    and t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and (p_category_id is null or sub.parent_id = p_category_id)
    and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
    and (p_product_id is null or t.product_id = p_product_id)
    and (p_channel_id is null or c.channel_id = p_channel_id)
    and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    and (p_sales_rep_id is null or t.sales_rep_id = p_sales_rep_id)
    and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
$$;

create or replace function report_status_mtd(
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cur record;
  v_prev record;
  v_tgt record;
  v_cur_si record;
  v_prev_si record;
  v_total_days integer;
  v_elapsed_days integer;
  v_projected_value numeric;
  v_cur_ticket numeric;
  v_prev_ticket numeric;
  v_tgt_ticket numeric;
  v_cur_avg_price numeric;
  v_prev_avg_price numeric;
  v_tgt_avg_price numeric;
  v_cur_sell_in_price numeric;
  v_prev_sell_in_price numeric;
  v_pdv_count bigint;
  v_last_current_invoice_date date;
begin
  select * into v_cur from fn_sell_out_metrics(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev from fn_sell_out_metrics(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_cur_si from fn_sell_in_metrics_for_sell_out_filter(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev_si from fn_sell_in_metrics_for_sell_out_filter(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id);

  select * into v_tgt from fn_target_metrics(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_distributor_id, p_macro_category_id, p_category_id, p_subcategory_id,
    p_product_id, p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  select fn_sell_out_last_invoice_date(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_id, p_subcategory_id, p_product_id, p_channel_id, p_cluster_id,
    p_sales_rep_id, p_supervisor_id)
  into v_last_current_invoice_date;

  v_total_days := p_current_end - p_current_start + 1;
  v_elapsed_days := greatest(
    1,
    least(coalesce(v_last_current_invoice_date, current_date), p_current_end) - p_current_start + 1
  );
  v_projected_value := fn_safe_div(v_cur.total_value, v_elapsed_days) * v_total_days;

  v_cur_ticket := fn_safe_div(v_cur.total_value, v_cur.coverage::numeric);
  v_prev_ticket := fn_safe_div(v_prev.total_value, v_prev.coverage::numeric);
  v_tgt_ticket := fn_safe_div(v_tgt.total_value, v_tgt.coverage::numeric);

  v_cur_avg_price := fn_safe_div(v_cur.total_value, v_cur.total_quantity);
  v_prev_avg_price := fn_safe_div(v_prev.total_value, v_prev.total_quantity);
  v_tgt_avg_price := fn_safe_div(v_tgt.total_value, v_tgt.total_quantity);
  v_cur_sell_in_price := fn_safe_div(v_cur_si.total_value, v_cur_si.total_quantity);
  v_prev_sell_in_price := fn_safe_div(v_prev_si.total_value, v_prev_si.total_quantity);

  v_pdv_count := fn_customer_count(
    p_distributor_id, p_channel_id, p_cluster_id, p_sales_rep_id, p_supervisor_id);

  return jsonb_build_object(
    'sell_out_value', jsonb_build_object(
      'current', v_cur.total_value,
      'target', v_tgt.total_value,
      'previous', v_prev.total_value,
      'current_vs_target', fn_ratio(v_cur.total_value, v_tgt.total_value),
      'previous_vs_target', fn_ratio(v_prev.total_value, v_tgt.total_value)
    ),
    'sell_out_quantity', jsonb_build_object(
      'current', v_cur.total_quantity,
      'target', v_tgt.total_quantity,
      'previous', v_prev.total_quantity,
      'current_vs_target', fn_ratio(v_cur.total_quantity, v_tgt.total_quantity),
      'previous_vs_target', fn_ratio(v_prev.total_quantity, v_tgt.total_quantity)
    ),
    'coverage', jsonb_build_object(
      'current', v_cur.coverage,
      'target', v_tgt.coverage,
      'previous', v_prev.coverage,
      'current_vs_target', fn_ratio(v_cur.coverage::numeric, v_tgt.coverage::numeric),
      'previous_vs_target', fn_ratio(v_prev.coverage::numeric, v_tgt.coverage::numeric)
    ),
    'avg_ticket', jsonb_build_object(
      'current', v_cur_ticket,
      'target', v_tgt_ticket,
      'previous', v_prev_ticket,
      'current_vs_target', fn_ratio(v_cur_ticket, v_tgt_ticket),
      'previous_vs_target', fn_ratio(v_prev_ticket, v_tgt_ticket)
    ),
    'drop_size', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_quantity, v_cur.invoice_count::numeric),
      'target', fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric),
      'previous', fn_safe_div(v_prev.total_quantity, v_prev.invoice_count::numeric),
      'current_vs_target', fn_ratio(
        fn_safe_div(v_cur.total_quantity, v_cur.invoice_count::numeric),
        fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric)),
      'previous_vs_target', fn_ratio(
        fn_safe_div(v_prev.total_quantity, v_prev.invoice_count::numeric),
        fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric))
    ),
    'avg_price', jsonb_build_object(
      'current', v_cur_avg_price,
      'target', v_tgt_avg_price,
      'previous', v_prev_avg_price,
      'current_vs_target', fn_ratio(v_cur_avg_price, v_tgt_avg_price),
      'previous_vs_target', fn_ratio(v_prev_avg_price, v_tgt_avg_price)
    ),
    'markup_pct', jsonb_build_object(
      'current', fn_ratio(v_cur_avg_price, v_cur_sell_in_price),
      'previous', fn_ratio(v_prev_avg_price, v_prev_sell_in_price)
    ),
    'margin_pct', jsonb_build_object(
      'current', fn_safe_div(v_cur_avg_price - v_cur_sell_in_price, v_cur_avg_price),
      'previous', fn_safe_div(v_prev_avg_price - v_prev_sell_in_price, v_prev_avg_price)
    ),
    'avg_turnover', jsonb_build_object(
      'current', fn_safe_div(v_cur.total_value, v_cur.total_value - v_cur_si.total_value),
      'previous', fn_safe_div(v_prev.total_value, v_prev.total_value - v_prev_si.total_value)
    ),
    'avg_coverage', jsonb_build_object(
      'current', fn_safe_div(v_cur_si.total_quantity - v_cur.total_quantity, v_cur.total_quantity),
      'previous', fn_safe_div(v_prev_si.total_quantity - v_prev.total_quantity, v_prev.total_quantity)
    ),
    'trend_value', jsonb_build_object(
      'projected', v_projected_value,
      'projected_vs_target', fn_ratio(v_projected_value, v_tgt.total_value)
    ),
    'probability_value', coalesce(fn_safe_div(v_cur.total_value, v_tgt.total_value), 0),
    'probability_coverage', coalesce(fn_safe_div(v_cur.coverage::numeric, v_pdv_count::numeric), 0),
    'probability_ticket', coalesce(fn_safe_div(v_cur_ticket, v_tgt_ticket), 0),
    'period', jsonb_build_object(
      'total_days', v_total_days,
      'elapsed_days', v_elapsed_days,
      'pdv_count', v_pdv_count
    )
  );
end;
$$;

create or replace function report_status_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_product_id uuid default null,
  p_channel_id uuid default null,
  p_cluster_id uuid default null
)
returns table (
  group_id uuid,
  group_name text,
  current_value numeric,
  target_value numeric,
  current_vs_target numeric,
  previous_value numeric,
  previous_vs_target numeric,
  coverage bigint,
  avg_ticket numeric,
  drop_size numeric,
  avg_price numeric,
  markup_pct numeric,
  margin_pct numeric,
  avg_turnover numeric,
  avg_coverage numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_group_by not in ('seller', 'category', 'channel') then
    raise exception 'report_status_analysis: invalid p_group_by %', p_group_by;
  end if;

  return query
  with cur_base as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      so.distributor_id,
      so.product_id,
      so.customer_id,
      so.gross_value,
      so.quantity
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_current_start and p_current_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
  ),
  cur as (
    select
      gid,
      sum(gross_value) as v_value,
      sum(quantity) as v_quantity,
      count(distinct customer_id) as v_coverage,
      count(*)::bigint as v_invoices
    from cur_base
    group by 1
  ),
  si as (
    select
      scope.gid,
      sum(si.gross_value) as v_value,
      sum(si.quantity) as v_quantity
    from (
      select distinct gid, distributor_id, product_id
      from cur_base
      where gid is not null
    ) scope
    join sell_in si
      on si.distributor_id = scope.distributor_id
     and si.product_id = scope.product_id
    where si.invoice_date between p_current_start and p_current_end
    group by 1
  ),
  prev as (
    select
      case p_group_by
        when 'seller' then so.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(so.gross_value) as v_value
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date between p_previous_start and p_previous_end
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or so.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  tgt as (
    select
      case p_group_by
        when 'seller' then t.sales_rep_id
        when 'category' then sub.parent_id
        when 'channel' then c.channel_id
      end as gid,
      sum(t.gross_value) as v_value
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = t.customer_id
    where t.target_date between coalesce(p_target_start, p_current_start)
      and coalesce(p_target_end, p_current_end)
      and t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and (p_category_id is null or sub.parent_id = p_category_id)
      and (p_subcategory_id is null or p.subcategory_id = p_subcategory_id)
      and (p_product_id is null or t.product_id = p_product_id)
      and (p_channel_id is null or c.channel_id = p_channel_id)
      and (p_cluster_id is null or c.cluster_id = p_cluster_id)
    group by 1
  ),
  keys as (
    select cur.gid from cur
    union
    select prev.gid from prev
    union
    select tgt.gid from tgt
  ),
  calculated as (
    select
      k.gid,
      coalesce(sr.name, ph.name, ch.name, '—') as group_name,
      coalesce(cur.v_value, 0) as current_value,
      tgt.v_value as target_value,
      fn_ratio(coalesce(cur.v_value, 0), tgt.v_value) as current_vs_target,
      coalesce(prev.v_value, 0) as previous_value,
      fn_ratio(coalesce(prev.v_value, 0), tgt.v_value) as previous_vs_target,
      coalesce(cur.v_coverage, 0) as coverage,
      fn_safe_div(cur.v_value, cur.v_coverage::numeric) as avg_ticket,
      fn_safe_div(cur.v_quantity, cur.v_invoices::numeric) as drop_size,
      fn_safe_div(cur.v_value, cur.v_quantity) as avg_price,
      fn_safe_div(si.v_value, si.v_quantity) as sell_in_avg_price,
      fn_safe_div(cur.v_value, cur.v_value - si.v_value) as avg_turnover,
      fn_safe_div(si.v_quantity - cur.v_quantity, cur.v_quantity) as avg_coverage
    from keys k
    left join cur on cur.gid = k.gid
    left join si on si.gid = k.gid
    left join prev on prev.gid = k.gid
    left join tgt on tgt.gid = k.gid
    left join sales_reps sr on p_group_by = 'seller' and sr.id = k.gid
    left join product_hierarchy ph on p_group_by = 'category' and ph.id = k.gid
    left join channels ch on p_group_by = 'channel' and ch.id = k.gid
    where k.gid is not null
  )
  select
    c.gid,
    c.group_name,
    c.current_value,
    c.target_value,
    c.current_vs_target,
    c.previous_value,
    c.previous_vs_target,
    c.coverage,
    c.avg_ticket,
    c.drop_size,
    c.avg_price,
    fn_ratio(c.avg_price, c.sell_in_avg_price),
    fn_safe_div(c.avg_price - c.sell_in_avg_price, c.avg_price),
    c.avg_turnover,
    c.avg_coverage
  from calculated c
  order by 3 desc;
end;
$$;

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

revoke execute on function process_sell_out_staging(uuid) from public, anon, authenticated;
revoke execute on function process_targets_staging(uuid) from public, anon, authenticated;
revoke execute on function fn_sell_out_metrics(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_sell_out_last_invoice_date(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_target_metrics(date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function fn_format_import_log_message(uuid, text) from public, anon, authenticated;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  to authenticated;
grant execute on function report_status_analysis(text, date, date, date, date, date, date, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
  to authenticated;
