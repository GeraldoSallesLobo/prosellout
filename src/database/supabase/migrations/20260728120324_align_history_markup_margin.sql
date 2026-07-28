-- Align monthly history Mark Up and Margin with the validated Sell Out vs Sell In average price rationale.

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
  ),
  sell_out_months as (
    select
      date_trunc('month', so.invoice_date)::date as month_start,
      sum(so.gross_value)::numeric as total_value,
      sum(so.quantity)::numeric as total_quantity,
      count(distinct so.customer_id)::bigint as coverage,
      count(distinct so.invoice_number)::bigint as invoice_count
    from filtered_sell_out so
    group by 1
  ),
  sell_in_months as (
    select
      m.month_start,
      si.total_value,
      si.total_quantity
    from months m
    cross join lateral fn_sell_in_metrics_for_sell_out_filter_filtered(
      m.month_start,
      (m.month_start + interval '1 month - 1 day')::date,
      p_distributor_id,
      p_macro_category_id,
      p_category_ids,
      p_subcategory_ids,
      p_product_ids,
      p_channel_ids,
      p_cluster_ids,
      null,
      null
    ) si
  )
  select
    m.month_start,
    coalesce(so.total_value, 0)::numeric,
    coalesce(so.total_quantity, 0)::numeric,
    case
      when coalesce(si.total_quantity, 0) = 0 then null
      else coalesce(so.total_quantity, 0) * (si.total_value / nullif(si.total_quantity, 0))
    end::numeric,
    coalesce(so.coverage, 0)::bigint,
    coalesce(so.invoice_count, 0)::bigint
  from months m
  left join sell_out_months so using (month_start)
  left join sell_in_months si using (month_start)
  order by m.month_start
$$;

revoke execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  from public, anon;
grant execute on function report_three_month_history(date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[])
  to authenticated;
