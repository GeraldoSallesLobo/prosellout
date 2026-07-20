/** One KPI block: current period vs target vs previous period. */
export interface KpiBlock {
  current: number | null;
  target: number | null;
  previous: number | null;
  currentVsTarget: number | null;
  previousVsTarget: number | null;
}

export interface StatusMtdReport {
  sellOutValue: KpiBlock;
  sellOutQuantity: KpiBlock;
  coverage: KpiBlock;
  avgTicket: KpiBlock;
  dropSize: KpiBlock;
  avgPrice: KpiBlock;
  markupPct: KpiBlock;
  marginPct: KpiBlock;
  avgTurnover: KpiBlock;
  avgCoverage: KpiBlock;
  trendValue: { projected: number | null; projectedVsTarget: number | null };
  probabilityValue: number;
  probabilityCoverage: number;
  probabilityTicket: number;
}

export type StatusGroupBy = "seller" | "category" | "channel";
export type EvolutionGroupBy = "category" | "channel" | "customer";

export interface AnalysisRow {
  groupId: string;
  groupName: string;
  currentValue: number;
  targetValue: number | null;
  currentVsTarget: number | null;
  previousValue: number;
  previousVsTarget: number | null;
  coverage: number;
  avgTicket: number | null;
  dropSize: number | null;
  avgPrice: number | null;
  markupPct: number | null;
  marginPct: number | null;
  avgTurnover: number | null;
  avgCoverage: number | null;
}

export interface WeeklyBucket {
  bucketStart: string;
  totalValue: number;
  totalQuantity: number;
  coverage: number;
  invoiceCount: number;
}

export interface MonthHistoryRow {
  monthStart: string;
  totalValue: number;
  totalQuantity: number;
  totalCost: number;
  coverage: number;
  invoiceCount: number;
}

export interface EvolutionAnalysisRow {
  groupId: string;
  groupName: string;
  currentValue: number;
  previousValue: number;
  valueChangePct: number | null;
  currentQuantity: number;
  previousQuantity: number;
  quantityChangePct: number | null;
  currentTicket: number | null;
  previousTicket: number | null;
  ticketChangePct: number | null;
}

export interface FastFactsHighlight {
  name: string;
  achievement: number | null;
}

export interface FastFactsDimension {
  dimension: string;
  eligibleCount: number;
  achievedCount: number;
  achievedPct: number | null;
  avgProbability: number | null;
  best: FastFactsHighlight | null;
  worst: FastFactsHighlight | null;
}

export type FastFactsReport = Record<string, FastFactsDimension>;

/** Shared report filters (mirrors the RPC signatures). */
export interface ReportFilters {
  currentStart: string;
  currentEnd: string;
  previousStart: string;
  previousEnd: string;
  targetStart?: string;
  targetEnd?: string;
  distributorId?: string;
  categoryIds?: string[];
  subcategoryIds?: string[];
  productIds?: string[];
  channelIds?: string[];
  clusterIds?: string[];
  salesRepId?: string;
}

export interface FilterOption {
  id: string;
  name: string;
}

export interface FilterOptions {
  distributors: FilterOption[];
  categories: FilterOption[];
  subcategories: FilterOption[];
  products: FilterOption[];
  channels: FilterOption[];
  clusters: FilterOption[];
  sellers: FilterOption[];
  supervisors: FilterOption[];
}
