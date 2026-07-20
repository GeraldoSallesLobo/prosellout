import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type {
  AnalysisRow,
  EvolutionAnalysisRow,
  EvolutionGroupBy,
  FastFactsReport,
  FilterOptions,
  KpiBlock,
  MonthHistoryRow,
  ReportFilters,
  StatusGroupBy,
  StatusMtdReport,
  WeeklyBucket,
} from "@/types/reports";
import { DEMO_FILTER_OPTIONS } from "./demo/catalog";
import {
  DEMO_STATUS_MTD,
  getDemoEvolutionAnalysis,
  getDemoFastFacts,
  getDemoStatusAnalysis,
  getDemoThreeMonthHistory,
  getDemoWeeklyBuckets,
} from "./demo/reports";
import { simulateLatency } from "./demo/random";

type RpcParams = Record<string, string | string[] | null>;

function nullableArray(values?: string[]): string[] | null {
  return values && values.length > 0 ? values : null;
}

function buildFilterParams(filters: ReportFilters): RpcParams {
  return {
    p_current_start: filters.currentStart,
    p_current_end: filters.currentEnd,
    p_previous_start: filters.previousStart,
    p_previous_end: filters.previousEnd,
    p_target_start: filters.targetStart ?? null,
    p_target_end: filters.targetEnd ?? null,
    p_distributor_id: filters.distributorId ?? null,
    p_category_ids: nullableArray(filters.categoryIds),
    p_subcategory_ids: nullableArray(filters.subcategoryIds),
    p_product_ids: nullableArray(filters.productIds),
    p_channel_ids: nullableArray(filters.channelIds),
    p_cluster_ids: nullableArray(filters.clusterIds),
  };
}

function mapKpiBlock(raw: Record<string, number | null>): KpiBlock {
  return {
    current: raw.current ?? null,
    target: raw.target ?? null,
    previous: raw.previous ?? null,
    currentVsTarget: raw.current_vs_target ?? null,
    previousVsTarget: raw.previous_vs_target ?? null,
  };
}

export async function fetchStatusMtd(filters: ReportFilters): Promise<StatusMtdReport> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(DEMO_STATUS_MTD);

  const { data, error } = await supabase.rpc("report_status_mtd", {
    ...buildFilterParams(filters),
    p_sales_rep_id: filters.salesRepId ?? null,
  });
  if (error) throw error;

  return {
    sellOutValue: mapKpiBlock(data.sell_out_value),
    sellOutQuantity: mapKpiBlock(data.sell_out_quantity),
    coverage: mapKpiBlock(data.coverage),
    avgTicket: mapKpiBlock(data.avg_ticket),
    dropSize: mapKpiBlock(data.drop_size),
    avgPrice: mapKpiBlock(data.avg_price),
    markupPct: mapKpiBlock(data.markup_pct),
    marginPct: mapKpiBlock(data.margin_pct),
    avgTurnover: mapKpiBlock(data.avg_turnover),
    avgCoverage: mapKpiBlock(data.avg_coverage),
    trendValue: {
      projected: data.trend_value?.projected ?? null,
      projectedVsTarget: data.trend_value?.projected_vs_target ?? null,
    },
    probabilityValue: data.probability_value ?? 0,
    probabilityCoverage: data.probability_coverage ?? 0,
    probabilityTicket: data.probability_ticket ?? 0,
  };
}

export async function fetchStatusAnalysis(
  groupBy: StatusGroupBy,
  filters: ReportFilters,
): Promise<AnalysisRow[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoStatusAnalysis(groupBy));

  const { data, error } = await supabase.rpc("report_status_analysis", {
    p_group_by: groupBy,
    ...buildFilterParams(filters),
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    groupId: String(row.group_id),
    groupName: String(row.group_name),
    currentValue: Number(row.current_value ?? 0),
    targetValue: row.target_value === null ? null : Number(row.target_value),
    currentVsTarget: row.current_vs_target === null ? null : Number(row.current_vs_target),
    previousValue: Number(row.previous_value ?? 0),
    previousVsTarget: row.previous_vs_target === null ? null : Number(row.previous_vs_target),
    coverage: Number(row.coverage ?? 0),
    avgTicket: row.avg_ticket === null ? null : Number(row.avg_ticket),
    dropSize: row.drop_size === null ? null : Number(row.drop_size),
    avgPrice: row.avg_price === null ? null : Number(row.avg_price),
    markupPct: row.markup_pct === null ? null : Number(row.markup_pct),
    marginPct: row.margin_pct === null ? null : Number(row.margin_pct),
    avgTurnover: row.avg_turnover === null ? null : Number(row.avg_turnover),
    avgCoverage: row.avg_coverage === null ? null : Number(row.avg_coverage),
  }));
}

export async function fetchFastFacts(filters: ReportFilters): Promise<FastFactsReport> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoFastFacts());

  const { data, error } = await supabase.rpc("report_fast_facts", {
    p_current_start: filters.currentStart,
    p_current_end: filters.currentEnd,
    p_target_start: filters.targetStart ?? null,
    p_target_end: filters.targetEnd ?? null,
    p_distributor_id: filters.distributorId ?? null,
  });
  if (error) throw error;

  const report: FastFactsReport = {};
  for (const [dimension, raw] of Object.entries(data ?? {})) {
    const value = raw as Record<string, unknown>;
    report[dimension] = {
      dimension,
      eligibleCount: Number(value.eligible_count ?? 0),
      achievedCount: Number(value.achieved_count ?? 0),
      achievedPct: value.achieved_pct === null || value.achieved_pct === undefined ? null : Number(value.achieved_pct),
      avgProbability: value.avg_probability === null || value.avg_probability === undefined ? null : Number(value.avg_probability),
      best: (value.best as FastFactsReport[string]["best"]) ?? null,
      worst: (value.worst as FastFactsReport[string]["worst"]) ?? null,
    };
  }
  return report;
}

export async function fetchEvolutionWeekly(filters: ReportFilters): Promise<WeeklyBucket[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoWeeklyBuckets());

  const { data, error } = await supabase.rpc("report_evolution_weekly", {
    p_start: filters.currentStart,
    p_end: filters.currentEnd,
    p_distributor_id: filters.distributorId ?? null,
    p_category_ids: nullableArray(filters.categoryIds),
    p_subcategory_ids: nullableArray(filters.subcategoryIds),
    p_product_ids: nullableArray(filters.productIds),
    p_channel_ids: nullableArray(filters.channelIds),
    p_cluster_ids: nullableArray(filters.clusterIds),
    p_sales_rep_id: filters.salesRepId ?? null,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    bucketStart: String(row.bucket_start),
    totalValue: Number(row.total_value ?? 0),
    totalQuantity: Number(row.total_quantity ?? 0),
    coverage: Number(row.coverage ?? 0),
    invoiceCount: Number(row.invoice_count ?? 0),
  }));
}

export async function fetchThreeMonthHistory(
  referenceMonth: string,
  filters: ReportFilters,
): Promise<MonthHistoryRow[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoThreeMonthHistory());

  const { data, error } = await supabase.rpc("report_three_month_history", {
    p_reference_month: referenceMonth,
    p_distributor_id: filters.distributorId ?? null,
    p_category_ids: nullableArray(filters.categoryIds),
    p_subcategory_ids: nullableArray(filters.subcategoryIds),
    p_product_ids: nullableArray(filters.productIds),
    p_channel_ids: nullableArray(filters.channelIds),
    p_cluster_ids: nullableArray(filters.clusterIds),
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    monthStart: String(row.month_start),
    totalValue: Number(row.total_value ?? 0),
    totalQuantity: Number(row.total_quantity ?? 0),
    totalCost: Number(row.total_cost ?? 0),
    coverage: Number(row.coverage ?? 0),
    invoiceCount: Number(row.invoice_count ?? 0),
  }));
}

export async function fetchEvolutionAnalysis(
  groupBy: EvolutionGroupBy,
  filters: ReportFilters,
): Promise<EvolutionAnalysisRow[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoEvolutionAnalysis(groupBy));

  const { data, error } = await supabase.rpc("report_evolution_analysis", {
    p_group_by: groupBy,
    p_current_start: filters.currentStart,
    p_current_end: filters.currentEnd,
    p_previous_start: filters.previousStart,
    p_previous_end: filters.previousEnd,
    p_distributor_id: filters.distributorId ?? null,
    p_category_ids: nullableArray(filters.categoryIds),
    p_subcategory_ids: nullableArray(filters.subcategoryIds),
    p_product_ids: nullableArray(filters.productIds),
    p_channel_ids: nullableArray(filters.channelIds),
    p_cluster_ids: nullableArray(filters.clusterIds),
    p_sales_rep_id: filters.salesRepId ?? null,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    groupId: String(row.group_id),
    groupName: String(row.group_name),
    currentValue: Number(row.current_value ?? 0),
    previousValue: Number(row.previous_value ?? 0),
    valueChangePct: row.value_change_pct === null ? null : Number(row.value_change_pct),
    currentQuantity: Number(row.current_quantity ?? 0),
    previousQuantity: Number(row.previous_quantity ?? 0),
    quantityChangePct: row.quantity_change_pct === null ? null : Number(row.quantity_change_pct),
    currentTicket: row.current_ticket === null ? null : Number(row.current_ticket),
    previousTicket: row.previous_ticket === null ? null : Number(row.previous_ticket),
    ticketChangePct: row.ticket_change_pct === null ? null : Number(row.ticket_change_pct),
  }));
}

export async function fetchFilterOptions(): Promise<FilterOptions> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(DEMO_FILTER_OPTIONS);

  const [distributors, hierarchy, products, channels, clusters, reps] = await Promise.all([
    supabase.from("distributors").select("id, name").eq("status", "active").order("name"),
    supabase.from("product_hierarchy").select("id, name, level").eq("status", "active").order("name"),
    supabase.from("products").select("id, name").eq("status", "active").order("name"),
    supabase.from("channels").select("id, name").eq("status", "active").order("name"),
    supabase.from("clusters").select("id, name").eq("status", "active").order("name"),
    supabase.from("sales_reps").select("id, name, role").eq("status", "active").order("name"),
  ]);

  const firstError =
    distributors.error ?? hierarchy.error ?? products.error ?? channels.error ??
    clusters.error ?? reps.error;
  if (firstError) throw firstError;

  const hierarchyRows = hierarchy.data ?? [];
  const repRows = reps.data ?? [];

  return {
    distributors: distributors.data ?? [],
    categories: hierarchyRows.filter((node) => node.level === "category"),
    subcategories: hierarchyRows.filter((node) => node.level === "subcategory"),
    products: products.data ?? [],
    channels: channels.data ?? [],
    clusters: clusters.data ?? [],
    sellers: repRows.filter((rep) => rep.role === "seller"),
    supervisors: repRows.filter((rep) => rep.role === "supervisor"),
  };
}
