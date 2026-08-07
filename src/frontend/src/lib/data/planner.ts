import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type {
  PlannerCoverageTargetKind,
  PlannerDashboard,
  PlannerDashboardGroupRow,
  PlannerGenerationResult,
  PlannerLowMarginPreview,
  PlannerPlanLine,
  PlannerPlanLinesPage,
  PlannerPlanSummary,
  PlannerRouteSummary,
  PlannerSkuParticipationPreview,
  PlannerTargetMonth,
  PlannerTopSku,
  PlannerTopSkuMetric,
  PlannerUncoveredPreview,
  PlannerWeekInput,
} from "@/types/planner";
import {
  generateDemoPlan,
  getDemoDashboard,
  getDemoLowMarginCustomers,
  getDemoPlanLines,
  getDemoPlans,
  getDemoRouteSummary,
  getDemoSkuParticipation,
  getDemoTargetMonths,
  getDemoTopSkus,
  getDemoUncoveredCustomers,
} from "./demo/planner";
import { simulateLatency } from "./demo/random";

function nullableArray(values?: string[]): string[] | null {
  return values && values.length > 0 ? values : null;
}

function nullableNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const numericValue = Number(value);
  return Number.isNaN(numericValue) ? null : numericValue;
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

/** Serializes week inputs into the p_weeks jsonb contract of the RPCs. */
function buildWeeksParam(weeks: PlannerWeekInput[]): Record<string, unknown>[] {
  return weeks.map((week) => ({
    week_number: week.weekNumber,
    start_date: week.startDate,
    end_date: week.endDate,
  }));
}

function mapGenerationResult(raw: Record<string, unknown>): PlannerGenerationResult {
  return {
    planId: String(raw.plan_id),
    code: Number(raw.code),
    version: Number(raw.version ?? 1),
    lineCount: Number(raw.line_count ?? 0),
    allocatedQuantity: nullableNumber(raw.allocated_quantity),
    weekTargetQuantity: nullableNumber(raw.week_target_quantity),
    amountPerCustomer: nullableNumber(raw.amount_per_customer),
    totalRevenueGap: nullableNumber(raw.total_revenue_gap),
    recalculatedFromWeek: nullableNumber(raw.recalculated_from_week),
  };
}

function mapDashboardGroupRow(raw: Record<string, unknown>): PlannerDashboardGroupRow {
  return {
    groupId: nullableString(raw.group_id),
    groupName: nullableString(raw.group_name),
    totalLines: Number(raw.total_lines ?? 0),
    achievedLines: Number(raw.achieved_lines ?? 0),
    achievementRate: nullableNumber(raw.achievement_rate),
    plannedQuantity: nullableNumber(raw.planned_quantity),
    realizedQuantity: nullableNumber(raw.realized_quantity),
    plannedValue: nullableNumber(raw.planned_value),
    realizedValue: nullableNumber(raw.realized_value),
    quantityVariation: nullableNumber(raw.quantity_variation),
    valueVariation: nullableNumber(raw.value_variation),
  };
}

export async function fetchPlannerTargetMonths(
  distributorId?: string,
): Promise<PlannerTargetMonth[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoTargetMonths());

  const { data, error } = await supabase.rpc("planner_list_target_months", {
    p_distributor_id: distributorId ?? null,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    monthStart: String(row.month_start),
    totalQuantity: Number(row.total_quantity ?? 0),
    totalValue: Number(row.total_value ?? 0),
  }));
}

export async function fetchPlannerRouteSummary(
  distributorId?: string,
): Promise<PlannerRouteSummary | null> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoRouteSummary());

  const { data, error } = await supabase.rpc("planner_route_plan_summary", {
    p_distributor_id: distributorId ?? null,
  });
  if (error) throw error;
  if (!data) return null;

  return {
    routePlanId: String(data.route_plan_id),
    weekCount: Number(data.week_count ?? 0),
    importedAt: String(data.imported_at),
    fileName: nullableString(data.file_name),
    totalVisits: Number(data.total_visits ?? 0),
    totalCustomers: Number(data.total_customers ?? 0),
    totalSellers: Number(data.total_sellers ?? 0),
    weeks: ((data.weeks ?? []) as Record<string, unknown>[]).map((week) => ({
      weekNumber: Number(week.week_number),
      visitCount: Number(week.visit_count ?? 0),
    })),
  };
}

export async function fetchPlannerTopSkus(
  referenceMonth: string,
  metric: PlannerTopSkuMetric,
  channelIds?: string[],
  extraProductIds?: string[],
  distributorId?: string,
): Promise<PlannerTopSku[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoTopSkus(metric, extraProductIds ?? []));

  const { data, error } = await supabase.rpc("planner_top_skus", {
    p_reference_month: referenceMonth,
    p_metric: metric,
    p_channel_ids: nullableArray(channelIds),
    p_extra_product_ids: nullableArray(extraProductIds),
    p_distributor_id: distributorId ?? null,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    productId: String(row.product_id),
    productName: String(row.product_name),
    ean: String(row.ean),
    positivation: Number(row.positivation ?? 0),
    totalQuantity: Number(row.total_quantity ?? 0),
    isExtra: Boolean(row.is_extra),
  }));
}

export async function fetchPlannerSkuParticipation(
  referenceMonth: string,
  referenceProductId: string,
  limit: number,
  offset: number,
  channelIds?: string[],
  distributorId?: string,
): Promise<PlannerSkuParticipationPreview> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const rows = getDemoSkuParticipation();
    return simulateLatency({ total: rows.length, rows: rows.slice(offset, offset + limit) });
  }

  const { data, error } = await supabase.rpc("planner_sku_participation", {
    p_reference_month: referenceMonth,
    p_reference_product_id: referenceProductId,
    p_channel_ids: nullableArray(channelIds),
    p_distributor_id: distributorId ?? null,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;

  const rows = (data ?? []).map((row: Record<string, unknown>) => ({
    customerId: String(row.customer_id),
    pdvCode: nullableString(row.pdv_code),
    customerName: String(row.customer_name),
    channelId: nullableString(row.channel_id),
    channelName: nullableString(row.channel_name),
    totalQuantity: Number(row.total_quantity ?? 0),
    volumeShare: nullableNumber(row.volume_share),
  }));
  const total = data && data.length > 0 ? Number(data[0].total_count ?? rows.length) : 0;
  return { total, rows };
}

export async function fetchPlannerUncoveredCustomers(
  productId: string,
  startDate: string,
  endDate: string,
  limit: number,
  offset: number,
  channelIds?: string[],
  distributorId?: string,
): Promise<PlannerUncoveredPreview> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const rows = getDemoUncoveredCustomers();
    return simulateLatency({ total: rows.length, rows: rows.slice(offset, offset + limit) });
  }

  const { data, error } = await supabase.rpc("planner_uncovered_customers", {
    p_product_id: productId,
    p_start_date: startDate,
    p_end_date: endDate,
    p_channel_ids: nullableArray(channelIds),
    p_distributor_id: distributorId ?? null,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;

  const rows = (data ?? []).map((row: Record<string, unknown>) => ({
    customerId: String(row.customer_id),
    pdvCode: nullableString(row.pdv_code),
    customerName: String(row.customer_name),
    channelId: nullableString(row.channel_id),
    channelName: nullableString(row.channel_name),
    salesRepId: nullableString(row.sales_rep_id),
  }));
  const total = data && data.length > 0 ? Number(data[0].total_count ?? rows.length) : 0;
  return { total, rows };
}

/** Loads the whole uncovered list (paged internally) for the preview export. */
export async function fetchAllPlannerUncoveredCustomers(
  productId: string,
  startDate: string,
  endDate: string,
  channelIds?: string[],
  distributorId?: string,
): Promise<PlannerUncoveredPreview["rows"]> {
  const rows: PlannerUncoveredPreview["rows"] = [];
  let offset = 0;
  for (;;) {
    const page = await fetchPlannerUncoveredCustomers(
      productId, startDate, endDate, EXPORT_PAGE_SIZE, offset, channelIds, distributorId,
    );
    rows.push(...page.rows);
    if (rows.length >= page.total || page.rows.length === 0) break;
    offset += EXPORT_PAGE_SIZE;
  }
  return rows;
}

export async function fetchPlannerLowMarginCustomers(
  productId: string,
  startDate: string,
  endDate: string,
  targetMargin: number,
  limit: number,
  offset: number,
  channelIds?: string[],
  distributorId?: string,
): Promise<PlannerLowMarginPreview> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const rows = getDemoLowMarginCustomers(targetMargin);
    return simulateLatency({ total: rows.length, rows: rows.slice(offset, offset + limit) });
  }

  const { data, error } = await supabase.rpc("planner_low_margin_customers", {
    p_product_id: productId,
    p_start_date: startDate,
    p_end_date: endDate,
    p_target_margin: targetMargin,
    p_channel_ids: nullableArray(channelIds),
    p_distributor_id: distributorId ?? null,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;

  const rows = (data ?? []).map((row: Record<string, unknown>) => ({
    customerId: String(row.customer_id),
    pdvCode: nullableString(row.pdv_code),
    customerName: String(row.customer_name),
    channelId: nullableString(row.channel_id),
    channelName: nullableString(row.channel_name),
    realizedValue: Number(row.realized_value ?? 0),
    realizedQuantity: Number(row.realized_quantity ?? 0),
    realizedMargin: Number(row.realized_margin ?? 0),
    marginGap: Number(row.margin_gap ?? 0),
    revenueGap: Number(row.revenue_gap ?? 0),
  }));
  const total = data && data.length > 0 ? Number(data[0].total_count ?? rows.length) : 0;
  return { total, rows };
}

/** Loads the whole low-margin list (paged internally) for the preview export. */
export async function fetchAllPlannerLowMarginCustomers(
  productId: string,
  startDate: string,
  endDate: string,
  targetMargin: number,
  channelIds?: string[],
  distributorId?: string,
): Promise<PlannerLowMarginPreview["rows"]> {
  const rows: PlannerLowMarginPreview["rows"] = [];
  let offset = 0;
  for (;;) {
    const page = await fetchPlannerLowMarginCustomers(
      productId, startDate, endDate, targetMargin,
      EXPORT_PAGE_SIZE, offset, channelIds, distributorId,
    );
    rows.push(...page.rows);
    if (rows.length >= page.total || page.rows.length === 0) break;
    offset += EXPORT_PAGE_SIZE;
  }
  return rows;
}

export interface GenerateAutomaticPlanInput {
  targetMonth: string;
  weeks: PlannerWeekInput[];
  distributorId?: string;
}

export async function generateAutomaticPlan(
  input: GenerateAutomaticPlanInput,
): Promise<PlannerGenerationResult> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    return simulateLatency(
      generateDemoPlan({
        model: "automatic",
        params: { target_month: input.targetMonth, weight_mode: "history" },
        weeks: input.weeks,
        targetKind: "quantity",
        totalAmount:
          getDemoTargetMonths().find((month) => month.monthStart === input.targetMonth)
            ?.totalQuantity ?? 0,
      }),
    );
  }

  const { data, error } = await supabase.rpc("planner_generate_automatic", {
    p_target_month: input.targetMonth,
    p_weeks: buildWeeksParam(input.weeks),
    p_distributor_id: input.distributorId ?? null,
  });
  if (error) throw error;
  return mapGenerationResult(data);
}

export interface GenerateBattleshipPlanInput {
  mode: "volume" | "positivation";
  referenceMonth: string;
  referenceProductId: string;
  targetMonth: string;
  weeks: PlannerWeekInput[];
  channelIds?: string[];
  distributorId?: string;
}

export async function generateBattleshipPlan(
  input: GenerateBattleshipPlanInput,
): Promise<PlannerGenerationResult> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    return simulateLatency(
      generateDemoPlan({
        model: input.mode === "volume" ? "battleship_volume" : "battleship_positivation",
        params: {
          target_month: input.targetMonth,
          reference_month: input.referenceMonth,
          reference_product_id: input.referenceProductId,
        },
        weeks: input.weeks,
        targetKind: "quantity",
        totalAmount:
          getDemoTargetMonths().find((month) => month.monthStart === input.targetMonth)
            ?.totalQuantity ?? 0,
      }),
    );
  }

  const { data, error } = await supabase.rpc("planner_generate_battleship", {
    p_mode: input.mode,
    p_reference_month: input.referenceMonth,
    p_reference_product_id: input.referenceProductId,
    p_target_month: input.targetMonth,
    p_weeks: buildWeeksParam(input.weeks),
    p_channel_ids: nullableArray(input.channelIds),
    p_distributor_id: input.distributorId ?? null,
  });
  if (error) throw error;
  return mapGenerationResult(data);
}

export async function recalculatePlanRoute(planId: string): Promise<PlannerGenerationResult> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    // Demo generations always have every week open, matching NO_CLOSED_WEEKS.
    await simulateLatency(null);
    throw new Error("NO_CLOSED_WEEKS");
  }

  const { data, error } = await supabase.rpc("planner_recalculate_route", {
    p_plan_id: planId,
  });
  if (error) throw error;
  return mapGenerationResult(data);
}

export interface GenerateCoveragePlanInput {
  productId: string;
  startDate: string;
  endDate: string;
  targetKind: PlannerCoverageTargetKind;
  targetAmount: number;
  executionStart: string;
  executionEnd: string;
  channelIds?: string[];
  distributorId?: string;
}

export async function generateCoveragePlan(
  input: GenerateCoveragePlanInput,
): Promise<PlannerGenerationResult> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    return simulateLatency(
      generateDemoPlan({
        model: "coverage",
        params: {
          target_kind: input.targetKind,
          target_amount: input.targetAmount,
          execution_start: input.executionStart,
          execution_end: input.executionEnd,
        },
        weeks: null,
        targetKind: input.targetKind,
        totalAmount: input.targetAmount,
      }),
    );
  }

  const { data, error } = await supabase.rpc("planner_generate_coverage", {
    p_product_id: input.productId,
    p_start_date: input.startDate,
    p_end_date: input.endDate,
    p_target_kind: input.targetKind,
    p_target_amount: input.targetAmount,
    p_execution_start: input.executionStart,
    p_execution_end: input.executionEnd,
    p_channel_ids: nullableArray(input.channelIds),
    p_distributor_id: input.distributorId ?? null,
  });
  if (error) throw error;
  return mapGenerationResult(data);
}

export interface GenerateProfitabilityPlanInput {
  productId: string;
  startDate: string;
  endDate: string;
  targetMargin: number;
  executionStart: string;
  executionEnd: string;
  channelIds?: string[];
  distributorId?: string;
}

export async function generateProfitabilityPlan(
  input: GenerateProfitabilityPlanInput,
): Promise<PlannerGenerationResult> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    return simulateLatency(
      generateDemoPlan({
        model: "profitability",
        params: {
          target_margin: input.targetMargin,
          execution_start: input.executionStart,
          execution_end: input.executionEnd,
        },
        weeks: null,
        targetKind: "value",
        totalAmount: getDemoLowMarginCustomers(input.targetMargin).reduce(
          (sum, row) => sum + row.revenueGap,
          0,
        ),
      }),
    );
  }

  const { data, error } = await supabase.rpc("planner_generate_profitability", {
    p_product_id: input.productId,
    p_start_date: input.startDate,
    p_end_date: input.endDate,
    p_target_margin: input.targetMargin,
    p_execution_start: input.executionStart,
    p_execution_end: input.executionEnd,
    p_channel_ids: nullableArray(input.channelIds),
    p_distributor_id: input.distributorId ?? null,
  });
  if (error) throw error;
  return mapGenerationResult(data);
}

export async function fetchPlannerPlans(
  distributorId?: string,
): Promise<PlannerPlanSummary[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoPlans());

  const { data, error } = await supabase.rpc("planner_list_plans", {
    p_distributor_id: distributorId ?? null,
  });
  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id),
    code: Number(row.code),
    model: String(row.model) as PlannerPlanSummary["model"],
    version: Number(row.version ?? 1),
    status: String(row.status) as PlannerPlanSummary["status"],
    params: (row.params ?? {}) as Record<string, unknown>,
    routePlanId: nullableString(row.route_plan_id),
    routeFileName: nullableString(row.route_file_name),
    lineCount: Number(row.line_count ?? 0),
    totalQuantity: nullableNumber(row.total_quantity),
    totalValue: nullableNumber(row.total_value),
    createdAt: String(row.created_at),
  }));
}

export async function fetchPlannerPlanLines(
  planId: string,
  limit: number,
  offset: number,
): Promise<PlannerPlanLinesPage> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoPlanLines(planId, limit, offset));

  const { data, error } = await supabase.rpc("planner_plan_lines_page", {
    p_plan_id: planId,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;

  const rows = (data ?? []).map((row: Record<string, unknown>) => ({
    lineId: Number(row.line_id),
    weekNumber: nullableNumber(row.week_number),
    ean: String(row.ean),
    productName: String(row.product_name),
    pdvCode: nullableString(row.pdv_code),
    customerName: String(row.customer_name),
    salesRepName: nullableString(row.sales_rep_name),
    channelName: nullableString(row.channel_name),
    quantity: nullableNumber(row.quantity),
    grossValue: nullableNumber(row.gross_value),
    distributorCnpj: nullableString(row.distributor_cnpj),
  }));
  const total = data && data.length > 0 ? Number(data[0].total_count ?? rows.length) : 0;
  return { total, rows };
}

const EXPORT_PAGE_SIZE = 500;

/** Loads every line of a plan (paged internally) for CSV exports. */
export async function fetchAllPlannerPlanLines(planId: string): Promise<PlannerPlanLine[]> {
  const rows: PlannerPlanLine[] = [];
  let offset = 0;
  for (;;) {
    const page = await fetchPlannerPlanLines(planId, EXPORT_PAGE_SIZE, offset);
    rows.push(...page.rows);
    if (rows.length >= page.total || page.rows.length === 0) break;
    offset += EXPORT_PAGE_SIZE;
  }
  return rows;
}

export async function fetchPlannerDashboard(
  planId: string,
  evalStart?: string,
  evalEnd?: string,
): Promise<PlannerDashboard | null> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(getDemoDashboard(planId));

  const { data, error } = await supabase.rpc("planner_dashboard", {
    p_plan_id: planId,
    p_eval_start: evalStart ?? null,
    p_eval_end: evalEnd ?? null,
  });
  if (error) throw error;
  if (!data) return null;

  const plan = data.plan as Record<string, unknown>;
  const summary = data.summary as Record<string, unknown>;
  return {
    plan: {
      id: String(plan.id),
      code: Number(plan.code),
      model: String(plan.model) as PlannerDashboard["plan"]["model"],
      version: Number(plan.version ?? 1),
      status: String(plan.status) as PlannerDashboard["plan"]["status"],
      params: (plan.params ?? {}) as Record<string, unknown>,
      createdAt: String(plan.created_at),
    },
    evalPeriod: {
      startDate: String((data.eval_period as Record<string, unknown>)?.start_date ?? ""),
      endDate: String((data.eval_period as Record<string, unknown>)?.end_date ?? ""),
    },
    summary: {
      totalLines: Number(summary.total_lines ?? 0),
      achievedLines: Number(summary.achieved_lines ?? 0),
      achievementRate: nullableNumber(summary.achievement_rate),
      plannedQuantity: nullableNumber(summary.planned_quantity),
      realizedQuantity: nullableNumber(summary.realized_quantity),
      plannedValue: nullableNumber(summary.planned_value),
      realizedValue: nullableNumber(summary.realized_value),
      missedQuantity: nullableNumber(summary.missed_quantity),
      missedValue: nullableNumber(summary.missed_value),
    },
    bestSeller: data.best_seller
      ? mapDashboardGroupRow(data.best_seller as Record<string, unknown>)
      : null,
    worstSeller: data.worst_seller
      ? mapDashboardGroupRow(data.worst_seller as Record<string, unknown>)
      : null,
    bySeller: ((data.by_seller ?? []) as Record<string, unknown>[]).map(mapDashboardGroupRow),
    byCustomer: ((data.by_customer ?? []) as Record<string, unknown>[]).map(mapDashboardGroupRow),
    byChannel: ((data.by_channel ?? []) as Record<string, unknown>[]).map(mapDashboardGroupRow),
    byProduct: ((data.by_product ?? []) as Record<string, unknown>[]).map(mapDashboardGroupRow),
  };
}
