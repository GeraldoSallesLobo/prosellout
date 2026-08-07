-- Paginate the planner preview lists. PostgREST caps set-returning responses
-- (db-max-rows = 1000 on hosted Supabase), so every preview that can exceed
-- 1000 rows needs limit/offset plus the real total_count: Cobertura
-- (uncovered PDVs), Rentabilidade (low-margin PDVs) and Batalha Naval (SKU
-- participation). Internal callers (planner_generate_coverage/profitability)
-- keep passing positional args: p_limit stays null there and the full set is
-- returned; the extra total_count column is ignored by name-based selects.

drop function if exists planner_uncovered_customers(uuid, date, date, uuid[], uuid);

create or replace function planner_uncovered_customers(
  p_product_id uuid,
  p_start_date date,
  p_end_date date,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null,
  p_limit integer default null,
  p_offset integer default 0
)
returns table (
  customer_id uuid,
  pdv_code text,
  customer_name text,
  channel_id uuid,
  channel_name text,
  sales_rep_id uuid,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    c.channel_id,
    ch.name,
    c.sales_rep_id,
    count(*) over ()
  from customers c
  left join channels ch on ch.id = c.channel_id
  where c.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and c.status = 'active'
    and fn_report_uuid_filter_matches(c.channel_id, p_channel_ids)
    and not exists (
      select 1
      from sell_out so
      where so.customer_id = c.id
        and so.product_id = p_product_id
        and so.invoice_date between p_start_date and p_end_date
        and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    )
  order by coalesce(c.trade_name, c.legal_name), c.id
  limit case when p_limit is null then null else greatest(p_limit, 1) end
  offset greatest(coalesce(p_offset, 0), 0)
$$;

revoke execute on function planner_uncovered_customers(uuid, date, date, uuid[], uuid, integer, integer)
  from public, anon;
grant execute on function planner_uncovered_customers(uuid, date, date, uuid[], uuid, integer, integer)
  to authenticated;

drop function if exists planner_low_margin_customers(uuid, date, date, numeric, uuid[], uuid);

create or replace function planner_low_margin_customers(
  p_product_id uuid,
  p_start_date date,
  p_end_date date,
  p_target_margin numeric,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null,
  p_limit integer default null,
  p_offset integer default 0
)
returns table (
  customer_id uuid,
  pdv_code text,
  customer_name text,
  channel_id uuid,
  channel_name text,
  realized_value numeric,
  realized_quantity numeric,
  realized_margin numeric,
  margin_gap numeric,
  revenue_gap numeric,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fallback_cost_months constant interval := interval '3 months';
  v_cost_price numeric;
begin
  if p_target_margin is null or p_target_margin <= 0 or p_target_margin >= 1 then
    raise exception 'INVALID_MARGIN';
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'INVALID_PERIOD';
  end if;

  select sum(si.gross_value) / nullif(sum(si.quantity), 0)
  into v_cost_price
  from sell_in si
  where si.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and si.product_id = p_product_id
    and si.invoice_date between p_start_date and p_end_date;

  if v_cost_price is null then
    select sum(si.gross_value) / nullif(sum(si.quantity), 0)
    into v_cost_price
    from sell_in si
    where si.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and si.product_id = p_product_id
      and si.invoice_date >= (p_start_date - fallback_cost_months)::date
      and si.invoice_date < p_start_date;
  end if;

  if v_cost_price is null then
    raise exception 'NO_COST_DATA';
  end if;

  return query
  with sold as (
    select
      so.customer_id as sold_customer_id,
      sum(so.gross_value) as total_value,
      sum(so.quantity) as total_quantity
    from sell_out so
    join customers c on c.id = so.customer_id
    where so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
      and so.product_id = p_product_id
      and so.invoice_date between p_start_date and p_end_date
      and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
    group by so.customer_id
  ),
  margins as (
    select
      sold.*,
      (sold.total_value / nullif(sold.total_quantity, 0) - v_cost_price)
        / nullif(sold.total_value / nullif(sold.total_quantity, 0), 0) as margin
    from sold
  )
  select
    c.id,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    c.channel_id,
    ch.name,
    m.total_value,
    m.total_quantity,
    m.margin,
    p_target_margin - m.margin,
    (p_target_margin - m.margin) * m.total_value,
    count(*) over ()
  from margins m
  join customers c on c.id = m.sold_customer_id
  left join channels ch on ch.id = c.channel_id
  where m.margin is not null
    and m.margin < p_target_margin
  order by (p_target_margin - m.margin) * m.total_value desc, c.id
  limit case when p_limit is null then null else greatest(p_limit, 1) end
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke execute on function planner_low_margin_customers(uuid, date, date, numeric, uuid[], uuid, integer, integer)
  from public, anon;
grant execute on function planner_low_margin_customers(uuid, date, date, numeric, uuid[], uuid, integer, integer)
  to authenticated;

drop function if exists planner_sku_participation(date, uuid, uuid[], uuid);

create or replace function planner_sku_participation(
  p_reference_month date,
  p_reference_product_id uuid,
  p_channel_ids uuid[] default null,
  p_distributor_id uuid default null,
  p_limit integer default null,
  p_offset integer default 0
)
returns table (
  customer_id uuid,
  pdv_code text,
  customer_name text,
  channel_id uuid,
  channel_name text,
  total_quantity numeric,
  volume_share numeric,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.pdv_code,
    coalesce(c.trade_name, c.legal_name),
    coalesce(so.channel_id, c.channel_id),
    ch.name,
    sum(so.quantity),
    sum(so.quantity) / nullif(sum(sum(so.quantity)) over (), 0),
    count(*) over ()
  from sell_out so
  join customers c on c.id = so.customer_id
  left join channels ch on ch.id = coalesce(so.channel_id, c.channel_id)
  where so.distributor_id in (select authorized_distributor_ids(p_distributor_id))
    and so.product_id = p_reference_product_id
    and so.invoice_date between date_trunc('month', p_reference_month)::date
      and (date_trunc('month', p_reference_month) + interval '1 month - 1 day')::date
    and fn_report_uuid_filter_matches(coalesce(so.channel_id, c.channel_id), p_channel_ids)
  group by c.id, c.pdv_code, c.trade_name, c.legal_name, coalesce(so.channel_id, c.channel_id), ch.name
  order by 6 desc, 1
  limit case when p_limit is null then null else greatest(p_limit, 1) end
  offset greatest(coalesce(p_offset, 0), 0)
$$;

revoke execute on function planner_sku_participation(date, uuid, uuid[], uuid, integer, integer)
  from public, anon;
grant execute on function planner_sku_participation(date, uuid, uuid[], uuid, integer, integer)
  to authenticated;
