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
        when 'channel' then c.channel_id
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
        when 'channel' then c.channel_id
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
        when 'channel' then c.channel_id
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

revoke execute on function fn_fast_facts_dimension(text, date, date, date, date, date, date, uuid)
  from public, anon, authenticated;
