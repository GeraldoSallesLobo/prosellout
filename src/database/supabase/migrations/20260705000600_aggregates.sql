-- Daily aggregate of sell_out used by dashboards.
--
-- Reports read this materialized view for sums (value, quantity, cost,
-- invoices) instead of scanning raw rows. Distinct-customer metrics
-- (coverage) are computed on the partitioned table itself because distinct
-- counts cannot be pre-aggregated safely across dimensions.

create materialized view mv_sell_out_daily as
select
  so.invoice_date,
  so.distributor_id,
  so.product_id,
  p.subcategory_id,
  sub.parent_id as category_id,
  cat.parent_id as macro_category_id,
  c.channel_id,
  c.cluster_id,
  so.sales_rep_id,
  sum(so.gross_value)::numeric(16, 2) as total_value,
  sum(so.quantity)::numeric(16, 3) as total_quantity,
  sum(so.quantity * coalesce(so.unit_cost, 0))::numeric(16, 2) as total_cost,
  count(distinct so.customer_id)::bigint as customer_count,
  count(distinct so.invoice_number)::bigint as invoice_count
from sell_out so
join products p on p.id = so.product_id
join product_hierarchy sub on sub.id = p.subcategory_id
join product_hierarchy cat on cat.id = sub.parent_id
join customers c on c.id = so.customer_id
group by
  so.invoice_date, so.distributor_id, so.product_id, p.subcategory_id,
  sub.parent_id, cat.parent_id, c.channel_id, c.cluster_id, so.sales_rep_id;

-- Required for REFRESH MATERIALIZED VIEW CONCURRENTLY.
create unique index mv_sell_out_daily_key on mv_sell_out_daily
  (invoice_date, distributor_id, product_id, channel_id, cluster_id, sales_rep_id)
  nulls not distinct;

create index mv_sell_out_daily_date_idx on mv_sell_out_daily (invoice_date);

-- Called by the ETL after each completed load and by a nightly pg_cron job.
create or replace function refresh_report_views()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently mv_sell_out_daily;
end;
$$;

select cron.schedule(
  'refresh-report-views-nightly',
  '0 4 * * *',
  $$ select refresh_report_views(); $$
);
