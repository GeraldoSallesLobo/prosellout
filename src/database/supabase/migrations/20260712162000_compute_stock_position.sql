-- Stock is not imported from a dedicated spreadsheet. The position is derived
-- from accumulated Sell In volume minus accumulated Sell Out volume up to the
-- selected reference date, keeping negative balances visible as data alerts.

drop function if exists fetch_stock_position(date, uuid, text, text, text, text, integer, integer);

create function fetch_stock_position(
  p_snapshot_date date default current_date,
  p_distributor_id uuid default null,
  p_search_key text default null,
  p_search_text text default null,
  p_sort_key text default null,
  p_sort_direction text default 'asc',
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  row_id text,
  distributor_id uuid,
  distributor_name text,
  product_id uuid,
  ean text,
  product_name text,
  snapshot_date date,
  quantity numeric,
  gross_value numeric,
  total_count bigint
)
language sql
stable
set search_path = public
as $$
  with params as (
    select
      coalesce(p_snapshot_date, current_date) as snapshot_date,
      p_distributor_id as distributor_id,
      lower(coalesce(p_search_key, '')) as search_key,
      lower(trim(coalesce(p_search_text, ''))) as search_text,
      lower(coalesce(p_sort_key, 'product')) as sort_key,
      case when lower(coalesce(p_sort_direction, 'asc')) = 'desc' then 'desc' else 'asc' end
        as sort_direction,
      least(greatest(coalesce(p_limit, 25), 1), 100) as limit_value,
      greatest(coalesce(p_offset, 0), 0) as offset_value
  ),
  sell_in_totals as (
    select
      si.distributor_id,
      si.product_id,
      sum(si.quantity) as quantity,
      sum(si.gross_value) as gross_value
    from sell_in si
    cross join params p
    where si.invoice_date <= p.snapshot_date
      and (p.distributor_id is null or si.distributor_id = p.distributor_id)
    group by si.distributor_id, si.product_id
  ),
  sell_out_totals as (
    select
      so.distributor_id,
      so.product_id,
      sum(so.quantity) as quantity
    from sell_out so
    cross join params p
    where so.invoice_date <= p.snapshot_date
      and (p.distributor_id is null or so.distributor_id = p.distributor_id)
    group by so.distributor_id, so.product_id
  ),
  stock_positions as (
    select
      coalesce(si.distributor_id, so.distributor_id) as distributor_id,
      coalesce(si.product_id, so.product_id) as product_id,
      coalesce(si.quantity, 0) - coalesce(so.quantity, 0) as quantity,
      coalesce(si.gross_value, 0) as gross_value
    from sell_in_totals si
    full join sell_out_totals so
      on so.distributor_id = si.distributor_id
     and so.product_id = si.product_id
  ),
  enriched as (
    select
      (sp.distributor_id::text || ':' || sp.product_id::text) as row_id,
      sp.distributor_id,
      d.name as distributor_name,
      sp.product_id,
      pr.ean,
      pr.name as product_name,
      (select snapshot_date from params) as snapshot_date,
      sp.quantity,
      sp.gross_value
    from stock_positions sp
    join distributors d on d.id = sp.distributor_id
    join products pr on pr.id = sp.product_id
  ),
  filtered as (
    select e.*
    from enriched e
    cross join params p
    where p.search_text = ''
      or (
        p.search_key = 'distributor'
        and lower(e.distributor_name) like '%' || p.search_text || '%'
      )
      or (
        p.search_key = 'ean'
        and lower(e.ean) like '%' || p.search_text || '%'
      )
      or (
        p.search_key = 'product'
        and lower(e.product_name) like '%' || p.search_text || '%'
      )
      or (
        p.search_key not in ('distributor', 'ean', 'product')
        and (
          lower(e.distributor_name) like '%' || p.search_text || '%'
          or lower(e.ean) like '%' || p.search_text || '%'
          or lower(e.product_name) like '%' || p.search_text || '%'
        )
      )
  ),
  counted as (
    select f.*, count(*) over() as total_count
    from filtered f
  )
  select
    c.row_id,
    c.distributor_id,
    c.distributor_name,
    c.product_id,
    c.ean,
    c.product_name,
    c.snapshot_date,
    c.quantity,
    c.gross_value,
    c.total_count
  from counted c
  cross join params p
  order by
    case when p.sort_key = 'distributor' and p.sort_direction = 'asc' then c.distributor_name end asc nulls last,
    case when p.sort_key = 'distributor' and p.sort_direction = 'desc' then c.distributor_name end desc nulls last,
    case when p.sort_key = 'ean' and p.sort_direction = 'asc' then c.ean end asc nulls last,
    case when p.sort_key = 'ean' and p.sort_direction = 'desc' then c.ean end desc nulls last,
    case when p.sort_key = 'product' and p.sort_direction = 'asc' then c.product_name end asc nulls last,
    case when p.sort_key = 'product' and p.sort_direction = 'desc' then c.product_name end desc nulls last,
    case when p.sort_key = 'date' and p.sort_direction = 'asc' then c.snapshot_date end asc nulls last,
    case when p.sort_key = 'date' and p.sort_direction = 'desc' then c.snapshot_date end desc nulls last,
    case when p.sort_key = 'quantity' and p.sort_direction = 'asc' then c.quantity end asc nulls last,
    case when p.sort_key = 'quantity' and p.sort_direction = 'desc' then c.quantity end desc nulls last,
    case when p.sort_key = 'value' and p.sort_direction = 'asc' then c.gross_value end asc nulls last,
    case when p.sort_key = 'value' and p.sort_direction = 'desc' then c.gross_value end desc nulls last,
    c.distributor_name,
    c.product_name,
    c.ean
  limit (select limit_value from params)
  offset (select offset_value from params);
$$;

revoke execute on function fetch_stock_position(date, uuid, text, text, text, text, integer, integer)
  from public, anon;
grant execute on function fetch_stock_position(date, uuid, text, text, text, text, integer, integer)
  to authenticated;
