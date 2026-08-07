/** Planner module contracts — mirror the planner_* RPCs (docs/PLANNER_SPEC.md §14). */

export type PlannerModel =
  | "automatic"
  | "battleship_volume"
  | "battleship_positivation"
  | "coverage"
  | "profitability";

export type PlannerPlanStatus = "generated" | "replaced";

export type PlannerTopSkuMetric = "volume" | "positivation";

export type PlannerCoverageTargetKind = "value" | "quantity";

export interface PlannerWeekInput {
  weekNumber: number;
  startDate: string;
  endDate: string;
}

export interface PlannerTargetMonth {
  monthStart: string;
  totalQuantity: number;
  totalValue: number;
}

export interface PlannerRouteWeekSummary {
  weekNumber: number;
  visitCount: number;
}

export interface PlannerRouteSummary {
  routePlanId: string;
  weekCount: number;
  importedAt: string;
  fileName: string | null;
  totalVisits: number;
  totalCustomers: number;
  totalSellers: number;
  weeks: PlannerRouteWeekSummary[];
}

export interface PlannerTopSku {
  productId: string;
  productName: string;
  ean: string;
  positivation: number;
  totalQuantity: number;
  isExtra: boolean;
}

export interface PlannerSkuParticipationRow {
  customerId: string;
  pdvCode: string | null;
  customerName: string;
  channelId: string | null;
  channelName: string | null;
  totalQuantity: number;
  volumeShare: number | null;
}

export interface PlannerUncoveredCustomer {
  customerId: string;
  pdvCode: string | null;
  customerName: string;
  channelId: string | null;
  channelName: string | null;
  salesRepId: string | null;
}

export interface PlannerUncoveredPreview {
  /** Real total of uncovered PDVs (the list below may be capped for display). */
  total: number;
  rows: PlannerUncoveredCustomer[];
}

export interface PlannerSkuParticipationPreview {
  total: number;
  rows: PlannerSkuParticipationRow[];
}

export interface PlannerLowMarginPreview {
  total: number;
  rows: PlannerLowMarginCustomer[];
}

export interface PlannerLowMarginCustomer {
  customerId: string;
  pdvCode: string | null;
  customerName: string;
  channelId: string | null;
  channelName: string | null;
  realizedValue: number;
  realizedQuantity: number;
  realizedMargin: number;
  marginGap: number;
  revenueGap: number;
}

export interface PlannerGenerationResult {
  planId: string;
  code: number;
  version: number;
  lineCount: number;
  allocatedQuantity: number | null;
  weekTargetQuantity: number | null;
  amountPerCustomer: number | null;
  totalRevenueGap: number | null;
  recalculatedFromWeek: number | null;
}

export interface PlannerPlanSummary {
  id: string;
  code: number;
  model: PlannerModel;
  version: number;
  status: PlannerPlanStatus;
  params: Record<string, unknown>;
  routePlanId: string | null;
  /** Imported route file that fed the weekly models; null for Cobertura/Rentabilidade. */
  routeFileName: string | null;
  lineCount: number;
  totalQuantity: number | null;
  totalValue: number | null;
  createdAt: string;
}

export interface PlannerPlanLine {
  lineId: number;
  weekNumber: number | null;
  ean: string;
  productName: string;
  pdvCode: string | null;
  customerName: string;
  salesRepName: string | null;
  channelName: string | null;
  quantity: number | null;
  grossValue: number | null;
  distributorCnpj: string | null;
}

export interface PlannerPlanLinesPage {
  total: number;
  rows: PlannerPlanLine[];
}

export interface PlannerDashboardGroupRow {
  groupId: string | null;
  groupName: string | null;
  totalLines: number;
  achievedLines: number;
  achievementRate: number | null;
  plannedQuantity: number | null;
  realizedQuantity: number | null;
  plannedValue: number | null;
  realizedValue: number | null;
  quantityVariation: number | null;
  valueVariation: number | null;
}

export interface PlannerDashboardSummary {
  totalLines: number;
  achievedLines: number;
  achievementRate: number | null;
  plannedQuantity: number | null;
  realizedQuantity: number | null;
  plannedValue: number | null;
  realizedValue: number | null;
  missedQuantity: number | null;
  missedValue: number | null;
}

export interface PlannerDashboardPlanInfo {
  id: string;
  code: number;
  model: PlannerModel;
  version: number;
  status: PlannerPlanStatus;
  params: Record<string, unknown>;
  createdAt: string;
}

export interface PlannerDashboard {
  plan: PlannerDashboardPlanInfo;
  evalPeriod: { startDate: string; endDate: string };
  summary: PlannerDashboardSummary;
  bestSeller: PlannerDashboardGroupRow | null;
  worstSeller: PlannerDashboardGroupRow | null;
  bySeller: PlannerDashboardGroupRow[];
  byCustomer: PlannerDashboardGroupRow[];
  byChannel: PlannerDashboardGroupRow[];
  byProduct: PlannerDashboardGroupRow[];
}

export type PlannerDashboardDimension = "seller" | "customer" | "channel" | "product";
