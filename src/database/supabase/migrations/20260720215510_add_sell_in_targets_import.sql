-- Add a dedicated Sell In target import. Sell Out targets remain in
-- sales_targets because they are customer/seller scoped. Sell In targets are
-- distributor/product/month scoped and feed target Mark Up, Margin and
-- Average Turnover in Status MTD.

create table if not exists sell_in_targets (
  id bigint generated always as identity primary key,
  distributor_id uuid not null references distributors(id),
  product_id uuid not null references products(id),
  target_date date not null,
  quantity numeric(14, 3) not null default 0 check (quantity >= 0),
  gross_value numeric(14, 2) not null default 0 check (gross_value >= 0),
  import_id uuid references file_imports(id),
  created_at timestamptz not null default now(),
  unique (distributor_id, product_id, target_date)
);

create index if not exists sell_in_targets_distributor_date_idx
  on sell_in_targets (distributor_id, target_date);

create index if not exists sell_in_targets_product_date_idx
  on sell_in_targets (product_id, target_date);

create unlogged table if not exists staging_sell_in_targets (
  import_id uuid not null,
  line_number integer not null,
  distributor_code text,
  product_ean text,
  target_date text,
  quantity text,
  gross_value text
);

create index if not exists staging_sell_in_targets_import_idx
  on staging_sell_in_targets (import_id);

alter table sell_in_targets enable row level security;
alter table staging_sell_in_targets enable row level security;

revoke all on staging_sell_in_targets from public, anon, authenticated;

drop policy if exists sell_in_targets_read_authorized on sell_in_targets;
create policy sell_in_targets_read_authorized on sell_in_targets
  for select to authenticated
  using (distributor_id in (select current_user_distributor_ids()));

grant select on sell_in_targets to authenticated;

create or replace function validate_sell_in_target_relationships()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from products p
    where p.id = new.product_id
      and p.distributor_id = new.distributor_id
  ) then
    raise exception 'sell in target product belongs to another distributor';
  end if;

  if new.import_id is not null and not exists (
    select 1
    from file_imports fi
    where fi.id = new.import_id
      and fi.distributor_id = new.distributor_id
  ) then
    raise exception 'import belongs to another distributor';
  end if;

  return new;
end;
$$;

drop trigger if exists sell_in_targets_validate_distributor on sell_in_targets;
create trigger sell_in_targets_validate_distributor
  before insert or update on sell_in_targets
  for each row execute function validate_sell_in_target_relationships();

update file_type_configs
set
  name = 'Meta Sell Out',
  updated_at = now()
where code = 'TARGETS';

insert into file_type_configs (id, code, name, target_table, processing_routine, file_format, status)
values (
  '75dedc9f-f5b7-522a-9f43-4688ff657728',
  'SELL_IN_TARGETS',
  'Meta Sell In',
  'sell_in_targets',
  'process_sell_in_targets_staging',
  'xlsx',
  'active'
)
on conflict (code) do update set
  name = excluded.name,
  target_table = excluded.target_table,
  processing_routine = excluded.processing_routine,
  file_format = excluded.file_format,
  status = excluded.status,
  updated_at = now();

create or replace function process_sell_in_targets_staging(p_import_id uuid)
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
    raise exception 'process_sell_in_targets_staging: import % has no distributor', p_import_id;
  end if;

  with valid_target_months as (
    select distinct date_trunc('month', s.target_date::date)::date as target_date
    from staging_sell_in_targets s
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
  delete from sell_in_targets sit
  using valid_target_months vtm
  where sit.distributor_id = v_distributor_id
    and sit.target_date = vtm.target_date
    and sit.import_id is distinct from p_import_id;

  with parsed as (
    select
      s.line_number,
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
        when p.id is null then 'unknown product ean: ' || coalesce(s.product_ean, '<null>')
        when not fn_is_iso_date(s.target_date) then 'invalid target_date: ' || coalesce(s.target_date, '<null>')
        when nullif(btrim(s.quantity), '') is not null and not fn_is_numeric(s.quantity)
          then 'invalid quantity: ' || coalesce(s.quantity, '<null>')
        when nullif(btrim(s.gross_value), '') is not null and not fn_is_numeric(s.gross_value)
          then 'invalid gross_value: ' || coalesce(s.gross_value, '<null>')
        when nullif(btrim(s.quantity), '') is null and nullif(btrim(s.gross_value), '') is null
          then 'missing target values'
      end as rejection_reason
    from staging_sell_in_targets s
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
      product_id,
      target_date,
      sum(quantity) as quantity,
      sum(gross_value) as gross_value
    from valid_rows
    group by product_id, target_date
  ),
  rejected as (
    insert into file_import_logs (import_id, line_number, level, message)
    select p_import_id, line_number, 'error', rejection_reason
    from parsed
    where rejection_reason is not null
    returning 1
  ),
  upserted as (
    insert into sell_in_targets (
      distributor_id, product_id, target_date, quantity, gross_value, import_id
    )
    select
      v_distributor_id, product_id, target_date, quantity, gross_value, p_import_id
    from aggregated_rows
    on conflict (distributor_id, product_id, target_date) do update set
      quantity = case
        when sell_in_targets.import_id = excluded.import_id
          then sell_in_targets.quantity + excluded.quantity
        else excluded.quantity
      end,
      gross_value = case
        when sell_in_targets.import_id = excluded.import_id
          then sell_in_targets.gross_value + excluded.gross_value
        else excluded.gross_value
      end,
      import_id = excluded.import_id
    returning 1
  )
  select
    (select count(*) from valid_rows),
    (select count(*) from rejected)
  into v_processed, v_rejected;

  delete from staging_sell_in_targets where import_id = p_import_id;

  update file_imports
  set
    processed_records = processed_records + v_processed,
    error_count = error_count + v_rejected
  where id = p_import_id;

  return query select v_processed, v_rejected;
end;
$$;

create or replace function fn_sell_in_target_metrics_filtered(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  total_value numeric,
  total_quantity numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with target_scope_filters as (
    select
      fn_report_uuid_filter_has_values(p_channel_ids)
      or fn_report_uuid_filter_has_values(p_cluster_ids)
      or p_sales_rep_id is not null
      or p_supervisor_id is not null as has_customer_or_seller_filter
  ),
  target_scope as (
    select distinct t.distributor_id, t.product_id
    from sales_targets t
    join products p on p.id = t.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = t.customer_id
    left join sales_reps sr on sr.id = t.sales_rep_id
    where t.target_date between p_start and p_end
      and t.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(t.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
      and fn_report_uuid_filter_matches(c.cluster_id, p_cluster_ids)
      and (p_sales_rep_id is null or t.sales_rep_id = p_sales_rep_id)
      and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
  )
  select
    coalesce(sum(sit.gross_value), 0)::numeric,
    coalesce(sum(sit.quantity), 0)::numeric
  from sell_in_targets sit
  join products p on p.id = sit.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  cross join target_scope_filters filters
  where sit.target_date between p_start and p_end
    and sit.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(sit.product_id, p_product_ids)
    and (
      not filters.has_customer_or_seller_filter
      or exists (
        select 1
        from target_scope scope
        where scope.distributor_id = sit.distributor_id
          and scope.product_id = sit.product_id
      )
    )
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
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
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
  v_tgt_si record;
  v_total_days integer;
  v_elapsed_days integer;
  v_projected_value numeric;
  v_cur_ticket numeric;
  v_prev_ticket numeric;
  v_tgt_ticket numeric;
  v_cur_drop_size numeric;
  v_prev_drop_size numeric;
  v_tgt_drop_size numeric;
  v_cur_avg_price numeric;
  v_prev_avg_price numeric;
  v_tgt_avg_price numeric;
  v_cur_sell_in_price numeric;
  v_prev_sell_in_price numeric;
  v_tgt_sell_in_price numeric;
  v_cur_markup numeric;
  v_prev_markup numeric;
  v_tgt_markup numeric;
  v_cur_margin numeric;
  v_prev_margin numeric;
  v_tgt_margin numeric;
  v_cur_turnover numeric;
  v_prev_turnover numeric;
  v_tgt_turnover numeric;
  v_pdv_count bigint;
  v_last_current_invoice_date date;
begin
  select * into v_cur from fn_sell_out_metrics_filtered(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev from fn_sell_out_metrics_filtered(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_cur_si from fn_sell_in_metrics_for_sell_out_filter_filtered(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_prev_si from fn_sell_in_metrics_for_sell_out_filter_filtered(
    p_previous_start, p_previous_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
    p_sales_rep_id, p_supervisor_id);

  select * into v_tgt from fn_target_metrics_filtered(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_distributor_id, p_macro_category_id, p_category_ids, p_subcategory_ids,
    p_product_ids, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

  select * into v_tgt_si from fn_sell_in_target_metrics_filtered(
    coalesce(p_target_start, p_current_start), coalesce(p_target_end, p_current_end),
    p_distributor_id, p_macro_category_id, p_category_ids, p_subcategory_ids,
    p_product_ids, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

  select fn_sell_out_last_invoice_date_filtered(
    p_current_start, p_current_end, p_distributor_id, p_macro_category_id,
    p_category_ids, p_subcategory_ids, p_product_ids, p_channel_ids, p_cluster_ids,
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

  v_cur_drop_size := fn_safe_div(v_cur.total_quantity, v_cur.coverage::numeric);
  v_prev_drop_size := fn_safe_div(v_prev.total_quantity, v_prev.coverage::numeric);
  v_tgt_drop_size := fn_safe_div(v_tgt.total_quantity, v_tgt.coverage::numeric);

  v_cur_avg_price := fn_safe_div(v_cur.total_value, v_cur.total_quantity);
  v_prev_avg_price := fn_safe_div(v_prev.total_value, v_prev.total_quantity);
  v_tgt_avg_price := fn_safe_div(v_tgt.total_value, v_tgt.total_quantity);
  v_cur_sell_in_price := fn_safe_div(v_cur_si.total_value, v_cur_si.total_quantity);
  v_prev_sell_in_price := fn_safe_div(v_prev_si.total_value, v_prev_si.total_quantity);
  v_tgt_sell_in_price := fn_safe_div(v_tgt_si.total_value, v_tgt_si.total_quantity);

  v_cur_markup := fn_safe_div(v_cur_avg_price, v_cur_sell_in_price) - 1;
  v_prev_markup := fn_safe_div(v_prev_avg_price, v_prev_sell_in_price) - 1;
  v_tgt_markup := fn_safe_div(v_tgt_avg_price, v_tgt_sell_in_price) - 1;
  v_cur_margin := fn_safe_div(v_cur_avg_price - v_cur_sell_in_price, v_cur_avg_price);
  v_prev_margin := fn_safe_div(v_prev_avg_price - v_prev_sell_in_price, v_prev_avg_price);
  v_tgt_margin := fn_safe_div(v_tgt_avg_price - v_tgt_sell_in_price, v_tgt_avg_price);
  v_cur_turnover := fn_safe_div(v_cur.total_value, v_cur.total_value - v_cur_si.total_value);
  v_prev_turnover := fn_safe_div(v_prev.total_value, v_prev.total_value - v_prev_si.total_value);
  v_tgt_turnover := fn_safe_div(v_tgt.total_value, v_tgt.total_value - v_tgt_si.total_value);

  v_pdv_count := fn_customer_count_filtered(
    p_distributor_id, p_channel_ids, p_cluster_ids, p_sales_rep_id, p_supervisor_id);

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
      'current', v_cur_drop_size,
      'target', v_tgt_drop_size,
      'previous', v_prev_drop_size,
      'current_vs_target', fn_ratio(v_cur_drop_size, v_tgt_drop_size),
      'previous_vs_target', fn_ratio(v_prev_drop_size, v_tgt_drop_size)
    ),
    'avg_price', jsonb_build_object(
      'current', v_cur_avg_price,
      'target', v_tgt_avg_price,
      'previous', v_prev_avg_price,
      'current_vs_target', fn_ratio(v_cur_avg_price, v_tgt_avg_price),
      'previous_vs_target', fn_ratio(v_prev_avg_price, v_tgt_avg_price)
    ),
    'markup_pct', jsonb_build_object(
      'current', v_cur_markup,
      'target', v_tgt_markup,
      'previous', v_prev_markup,
      'current_vs_target', fn_ratio(v_cur_markup, v_tgt_markup),
      'previous_vs_target', fn_ratio(v_prev_markup, v_tgt_markup)
    ),
    'margin_pct', jsonb_build_object(
      'current', v_cur_margin,
      'target', v_tgt_margin,
      'previous', v_prev_margin,
      'current_vs_target', fn_ratio(v_cur_margin, v_tgt_margin),
      'previous_vs_target', fn_ratio(v_prev_margin, v_tgt_margin)
    ),
    'avg_turnover', jsonb_build_object(
      'current', v_cur_turnover,
      'target', v_tgt_turnover,
      'previous', v_prev_turnover,
      'current_vs_target', fn_ratio(v_cur_turnover, v_tgt_turnover),
      'previous_vs_target', fn_ratio(v_prev_turnover, v_tgt_turnover)
    ),
    'avg_coverage', jsonb_build_object(
      'current', fn_safe_div(v_cur_si.total_quantity - v_cur.total_quantity, v_cur.total_quantity),
      'previous', fn_safe_div(v_prev_si.total_quantity - v_prev.total_quantity, v_prev.total_quantity)
    ),
    'trend_value', jsonb_build_object(
      'projected', v_projected_value,
      'projected_vs_target', fn_ratio(v_projected_value, v_tgt.total_value)
    ),
    'probability_value', fn_capped_probability(v_cur.total_value, v_tgt.total_value),
    'probability_coverage', fn_capped_probability(v_cur.coverage::numeric, v_tgt.coverage::numeric),
    'probability_ticket', fn_capped_probability(v_cur_ticket, v_tgt_ticket),
    'period', jsonb_build_object(
      'total_days', v_total_days,
      'elapsed_days', v_elapsed_days,
      'pdv_count', v_pdv_count
    )
  );
end;
$$;

revoke execute on function validate_sell_in_target_relationships() from public, anon, authenticated;
revoke execute on function process_sell_in_targets_staging(uuid) from public, anon, authenticated;
revoke execute on function fn_sell_in_target_metrics_filtered(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  from public, anon, authenticated;
revoke execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  from public, anon;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  to authenticated;
