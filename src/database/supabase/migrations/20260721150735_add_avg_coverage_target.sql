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
  v_cur_avg_coverage numeric;
  v_prev_avg_coverage numeric;
  v_tgt_avg_coverage numeric;
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
  v_cur_avg_coverage := fn_safe_div(v_cur_si.total_quantity - v_cur.total_quantity, v_cur.total_quantity);
  v_prev_avg_coverage := fn_safe_div(v_prev_si.total_quantity - v_prev.total_quantity, v_prev.total_quantity);
  v_tgt_avg_coverage := fn_safe_div(v_tgt_si.total_quantity - v_tgt.total_quantity, v_tgt.total_quantity);

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
      'current', v_cur_avg_coverage,
      'target', v_tgt_avg_coverage,
      'previous', v_prev_avg_coverage,
      'current_vs_target', fn_ratio(v_cur_avg_coverage, v_tgt_avg_coverage),
      'previous_vs_target', fn_ratio(v_prev_avg_coverage, v_tgt_avg_coverage)
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

revoke execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  from public, anon;

grant execute on function report_status_mtd(date, date, date, date, date, date, uuid, uuid, uuid[], uuid[], uuid[], uuid[], uuid[], uuid, uuid)
  to authenticated;
