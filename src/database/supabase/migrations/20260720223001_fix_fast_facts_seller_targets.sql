-- Fast Facts now shows achieved vs missed counts and best/worst performers
-- with Sell Out value, variation vs target and variation vs previous year.
-- Seller and supervisor targets must use sales_targets.sales_rep_id, because
-- the target layout is seller-scoped.

drop function if exists report_fast_facts(date, date, date, date, uuid);
drop function if exists report_fast_facts(date, date, date, date, uuid, date, date);
drop function if exists report_fast_facts(date, date, date, date, date, date, uuid);
drop function if exists fn_fast_facts_dimension(text, date, date, date, date, uuid);
drop function if exists fn_fast_facts_dimension(text, date, date, date, date, uuid, date, date);
drop function if exists fn_fast_facts_dimension(text, date, date, date, date, date, date, uuid);

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
      tgt.gid,
      coalesce(cur.total_value, 0) as current_value,
      tgt.total_value as target_value,
      coalesce(prev.total_value, 0) as previous_value,
      fn_safe_div(coalesce(cur.total_value, 0), tgt.total_value) as achievement,
      fn_ratio(coalesce(cur.total_value, 0), tgt.total_value) as current_vs_target,
      fn_ratio(coalesce(cur.total_value, 0), prev.total_value) as current_vs_previous,
      least(1, coalesce(
        fn_safe_div(fn_safe_div(coalesce(cur.total_value, 0), v_elapsed_days) * v_total_days, tgt.total_value),
        0
      )) as probability
    from tgt
    left join cur on cur.gid = tgt.gid
    left join prev on prev.gid = tgt.gid
    where tgt.gid is not null
      and tgt.total_value > 0
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
    'achieved_count', count(*) filter (where current_value >= target_value),
    'not_achieved_count', count(*) filter (where current_value < target_value),
    'achieved_pct', fn_safe_div(count(*) filter (where current_value >= target_value), count(*)::numeric),
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
      order by n.achievement desc nulls last, n.current_value desc
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
      order by n.achievement asc nulls last, n.current_value asc
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

create or replace function report_fast_facts(
  p_current_start date,
  p_current_end date,
  p_previous_start date default null,
  p_previous_end date default null,
  p_target_start date default null,
  p_target_end date default null,
  p_distributor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_dimension text;
  v_previous_start date := coalesce(p_previous_start, (p_current_start - interval '1 year')::date);
  v_previous_end date := coalesce(p_previous_end, (p_current_end - interval '1 year')::date);
  v_target_start date := coalesce(p_target_start, p_current_start);
  v_target_end date := coalesce(p_target_end, p_current_end);
  v_result jsonb := '{}'::jsonb;
begin
  perform assert_authorized_distributor_scope(p_distributor_id);

  foreach v_dimension in array array['seller', 'supervisor', 'product', 'category', 'channel', 'customer']
  loop
    v_result := v_result || jsonb_build_object(
      v_dimension,
      fn_fast_facts_dimension(
        v_dimension,
        p_current_start,
        p_current_end,
        v_target_start,
        v_target_end,
        v_previous_start,
        v_previous_end,
        p_distributor_id
      )
    );
  end loop;

  return v_result;
end;
$$;

revoke execute on function fn_fast_facts_dimension(text, date, date, date, date, date, date, uuid)
  from public, anon, authenticated;
revoke execute on function report_fast_facts(date, date, date, date, date, date, uuid)
  from public, anon;
grant execute on function report_fast_facts(date, date, date, date, date, date, uuid)
  to authenticated;
