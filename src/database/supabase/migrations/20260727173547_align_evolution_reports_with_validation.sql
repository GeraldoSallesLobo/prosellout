-- Align evolution reports with the validated monthly/history calculations.

create or replace function report_evolution_weekly(
  p_start date,
  p_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null
)
returns table (
  bucket_start date,
  total_value numeric,
  total_quantity numeric,
  coverage bigint,
  invoice_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (date_trunc('week', so.invoice_date + interval '1 day') - interval '1 day')::date,
    sum(so.gross_value)::numeric,
    sum(so.quantity)::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from sell_out so
  join products p on p.id = so.product_id
  join product_hierarchy sub on sub.id = p.subcategory_id
  join product_hierarchy cat on cat.id = sub.parent_id
  join customers c on c.id = so.customer_id
  where so.invoice_date between p_start and p_end
    and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
    and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
    and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
    and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
    and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
    and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  group by 1
  order by 1
$$;

create or replace function report_three_month_history(
  p_reference_month date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null
)
returns table (
  month_start date,
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
  with months as (
    select generate_series(
      (date_trunc('month', p_reference_month) - interval '2 months')::date,
      date_trunc('month', p_reference_month)::date,
      interval '1 month'
    )::date as month_start
  ),
  filtered_sell_out as (
    select so.*
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where so.invoice_date >= (date_trunc('month', p_reference_month) - interval '2 months')::date
      and so.invoice_date < (date_trunc('month', p_reference_month) + interval '1 month')::date
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
      and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
  )
  select
    m.month_start,
    coalesce(sum(so.gross_value), 0)::numeric,
    coalesce(sum(so.quantity), 0)::numeric,
    coalesce(sum(so.quantity * coalesce(so.unit_cost, 0)), 0)::numeric,
    count(distinct so.customer_id),
    count(distinct so.invoice_number)
  from months m
  left join filtered_sell_out so
    on date_trunc('month', so.invoice_date)::date = m.month_start
  group by m.month_start
  order by m.month_start
$$;

create or replace function report_evolution_analysis(
  p_group_by text,
  p_current_start date,
  p_current_end date,
  p_previous_start date,
  p_previous_end date,
  p_distributor_id uuid default null,
  p_macro_category_id uuid default null,
  p_category_ids uuid[] default null,
  p_subcategory_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_channel_ids uuid[] default null,
  p_cluster_ids uuid[] default null,
  p_sales_rep_id uuid default null
)
returns table (
  group_id uuid,
  group_name text,
  current_value numeric,
  previous_value numeric,
  value_change_pct numeric,
  current_quantity numeric,
  previous_quantity numeric,
  quantity_change_pct numeric,
  current_ticket numeric,
  previous_ticket numeric,
  ticket_change_pct numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_group_by not in ('category', 'channel', 'customer') then
    raise exception 'report_evolution_analysis: invalid p_group_by %', p_group_by;
  end if;

  perform assert_authorized_distributor_scope(p_distributor_id);

  return query
  with base as (
    select
      case p_group_by
        when 'category' then sub.parent_id
        when 'channel' then coalesce(so.channel_id, c.channel_id)
        when 'customer' then so.customer_id
      end as gid,
      so.invoice_date between p_current_start and p_current_end as is_current,
      so.gross_value,
      so.quantity,
      so.customer_id,
      so.invoice_number
    from sell_out so
    join products p on p.id = so.product_id
    join product_hierarchy sub on sub.id = p.subcategory_id
    join product_hierarchy cat on cat.id = sub.parent_id
    join customers c on c.id = so.customer_id
    where (
        so.invoice_date between p_current_start and p_current_end
        or so.invoice_date between p_previous_start and p_previous_end
      )
      and so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and (p_macro_category_id is null or cat.parent_id = p_macro_category_id)
      and fn_report_uuid_filter_matches(sub.parent_id, p_category_ids)
      and fn_report_uuid_filter_matches(p.subcategory_id, p_subcategory_ids)
      and fn_report_uuid_filter_matches(so.product_id, p_product_ids)
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
      and fn_report_uuid_filter_matches(coalesce(so.cluster_id, c.cluster_id), p_cluster_ids)
      and (p_sales_rep_id is null or so.sales_rep_id = p_sales_rep_id)
  ),
  grouped as (
    select
      b.gid,
      sum(b.gross_value) filter (where b.is_current) as cur_value,
      sum(b.gross_value) filter (where not b.is_current) as prev_value,
      sum(b.quantity) filter (where b.is_current) as cur_quantity,
      sum(b.quantity) filter (where not b.is_current) as prev_quantity,
      count(distinct b.customer_id) filter (where b.is_current) as cur_coverage,
      count(distinct b.customer_id) filter (where not b.is_current) as prev_coverage,
      count(distinct b.invoice_number) filter (where b.is_current) as cur_invoices,
      count(distinct b.invoice_number) filter (where not b.is_current) as prev_invoices
    from base b
    where b.gid is not null
    group by b.gid
  )
  select
    g.gid,
    coalesce(ph.name, ch.name, cust.legal_name, '-'),
    coalesce(g.cur_value, 0),
    coalesce(g.prev_value, 0),
    fn_ratio(coalesce(g.cur_value, 0), g.prev_value),
    coalesce(g.cur_quantity, 0),
    coalesce(g.prev_quantity, 0),
    fn_ratio(coalesce(g.cur_quantity, 0), g.prev_quantity),
    case when p_group_by = 'customer'
      then fn_safe_div(g.cur_value, g.cur_invoices::numeric)
      else fn_safe_div(g.cur_value, g.cur_coverage::numeric)
    end,
    case when p_group_by = 'customer'
      then fn_safe_div(g.prev_value, g.prev_invoices::numeric)
      else fn_safe_div(g.prev_value, g.prev_coverage::numeric)
    end,
    case when p_group_by = 'customer'
      then fn_ratio(fn_safe_div(g.cur_value, g.cur_invoices::numeric), fn_safe_div(g.prev_value, g.prev_invoices::numeric))
      else fn_ratio(fn_safe_div(g.cur_value, g.cur_coverage::numeric), fn_safe_div(g.prev_value, g.prev_coverage::numeric))
    end
  from grouped g
  left join product_hierarchy ph on p_group_by = 'category' and ph.id = g.gid
  left join channels ch on p_group_by = 'channel' and ch.id = g.gid
  left join customers cust on p_group_by = 'customer' and cust.id = g.gid
  order by 3 desc;
end;
$$;

revoke execute on function report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid)
  from public, anon;
revoke execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  from public, anon;
revoke execute on function report_evolution_analysis(text, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid)
  from public, anon;

grant execute on function report_evolution_weekly(date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid)
  to authenticated;
grant execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  to authenticated;
grant execute on function report_evolution_analysis(text, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid)
  to authenticated;
