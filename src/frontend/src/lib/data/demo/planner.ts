import type {
  PlannerCoverageTargetKind,
  PlannerDashboard,
  PlannerDashboardGroupRow,
  PlannerGenerationResult,
  PlannerLowMarginCustomer,
  PlannerModel,
  PlannerPlanLine,
  PlannerPlanLinesPage,
  PlannerPlanSummary,
  PlannerRouteSummary,
  PlannerSkuParticipationRow,
  PlannerTargetMonth,
  PlannerTopSku,
  PlannerTopSkuMetric,
  PlannerUncoveredCustomer,
  PlannerWeekInput,
} from "@/types/planner";
import {
  DEMO_CHANNELS,
  DEMO_CUSTOMERS,
  DEMO_DISTRIBUTORS,
  DEMO_PRODUCTS,
  DEMO_SELLERS,
} from "./catalog";
import { createSeededRandom } from "./random";

const DEMO_WEEK_COUNT = 4;
const DEMO_ROUTE_CUSTOMER_COUNT = 24;
const DEMO_LINE_CUSTOMER_COUNT = 8;
const DEMO_TARGET_MONTH_COUNT = 3;
const DEMO_MONTH_BASE_QUANTITY = 9500;

const activeCustomers = DEMO_CUSTOMERS.filter((customer) => customer.status === "active");
const activeSellers = DEMO_SELLERS.filter((seller) => seller.status === "active");

function currentMonthStart(offset: number): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + offset, 1))
    .toISOString()
    .slice(0, 10);
}

export function getDemoTargetMonths(): PlannerTargetMonth[] {
  const random = createSeededRandom(910);
  return Array.from({ length: DEMO_TARGET_MONTH_COUNT }, (_, index) => ({
    monthStart: currentMonthStart(index),
    totalQuantity: Math.round(DEMO_MONTH_BASE_QUANTITY * (1 + random() * 0.35)),
    totalValue: Math.round(DEMO_MONTH_BASE_QUANTITY * 68 * (1 + random() * 0.35)),
  }));
}

export function getDemoRouteSummary(): PlannerRouteSummary {
  const visitsPerWeek = Math.ceil(DEMO_ROUTE_CUSTOMER_COUNT / DEMO_WEEK_COUNT);
  return {
    routePlanId: "demo-route-plan",
    weekCount: DEMO_WEEK_COUNT,
    importedAt: new Date().toISOString(),
    fileName: "roteiro-visitas-demo.xlsx",
    totalVisits: DEMO_ROUTE_CUSTOMER_COUNT + 8,
    totalCustomers: DEMO_ROUTE_CUSTOMER_COUNT,
    totalSellers: activeSellers.length,
    weeks: Array.from({ length: DEMO_WEEK_COUNT }, (_, index) => ({
      weekNumber: index + 1,
      visitCount: visitsPerWeek + (index === 0 ? 8 : 0),
    })),
  };
}

export function getDemoTopSkus(
  metric: PlannerTopSkuMetric,
  extraProductIds: string[],
): PlannerTopSku[] {
  const random = createSeededRandom(metric === "volume" ? 300 : 301);
  const ranked = DEMO_PRODUCTS.map((product) => ({
    productId: product.id,
    productName: product.name,
    ean: product.ean,
    positivation: Math.round(40 + random() * 120),
    totalQuantity: Math.round(800 + random() * 5200),
    isExtra: false,
  })).sort((a, b) =>
    metric === "volume" ? b.totalQuantity - a.totalQuantity : b.positivation - a.positivation,
  );

  const top = ranked.slice(0, 5);
  const extras = ranked
    .slice(5)
    .filter((sku) => extraProductIds.includes(sku.productId))
    .map((sku) => ({ ...sku, isExtra: true }));
  return [...top, ...extras];
}

export function getDemoSkuParticipation(): PlannerSkuParticipationRow[] {
  const random = createSeededRandom(400);
  const sample = activeCustomers.slice(0, DEMO_ROUTE_CUSTOMER_COUNT);
  const quantities = sample.map(() => 20 + random() * 480);
  const total = quantities.reduce((sum, quantity) => sum + quantity, 0);
  return sample
    .map((customer, index) => ({
      customerId: customer.id,
      pdvCode: customer.cnpj,
      customerName: customer.legalName,
      channelId: null,
      channelName: customer.channelName,
      totalQuantity: Math.round(quantities[index] * 10) / 10,
      volumeShare: quantities[index] / total,
    }))
    .sort((a, b) => b.totalQuantity - a.totalQuantity);
}

export function getDemoUncoveredCustomers(): PlannerUncoveredCustomer[] {
  return activeCustomers.slice(DEMO_LINE_CUSTOMER_COUNT, DEMO_ROUTE_CUSTOMER_COUNT).map(
    (customer) => ({
      customerId: customer.id,
      pdvCode: customer.cnpj,
      customerName: customer.legalName,
      channelId: null,
      channelName: customer.channelName,
      salesRepId: null,
    }),
  );
}

export function getDemoLowMarginCustomers(targetMargin: number): PlannerLowMarginCustomer[] {
  const random = createSeededRandom(500);
  return activeCustomers
    .slice(0, DEMO_ROUTE_CUSTOMER_COUNT)
    .map((customer) => {
      const realizedMargin = 0.02 + random() * 0.3;
      const realizedValue = Math.round((900 + random() * 8000) * 100) / 100;
      return {
        customerId: customer.id,
        pdvCode: customer.cnpj,
        customerName: customer.legalName,
        channelId: null,
        channelName: customer.channelName,
        realizedValue,
        realizedQuantity: Math.round(realizedValue / 7),
        realizedMargin,
        marginGap: targetMargin - realizedMargin,
        revenueGap: Math.round((targetMargin - realizedMargin) * realizedValue * 100) / 100,
      };
    })
    .filter((row) => row.realizedMargin < targetMargin)
    .sort((a, b) => b.revenueGap - a.revenueGap);
}

interface DemoPlanRecord {
  summary: PlannerPlanSummary;
  lines: PlannerPlanLine[];
}

/** In-memory store: demo generations persist for the browser session only. */
const demoPlanStore: DemoPlanRecord[] = [];

function nextDemoCode(): number {
  return demoPlanStore.reduce((max, record) => Math.max(max, record.summary.code), 0) + 1;
}

function buildDemoLines(
  seed: number,
  weeks: PlannerWeekInput[] | null,
  targetKind: PlannerCoverageTargetKind,
  totalAmount: number,
): PlannerPlanLine[] {
  const random = createSeededRandom(seed);
  const customers = activeCustomers.slice(0, DEMO_LINE_CUSTOMER_COUNT);
  const products = DEMO_PRODUCTS.slice(0, 4);
  const weekNumbers = weeks?.map((week) => week.weekNumber) ?? [null];
  const lines: PlannerPlanLine[] = [];
  let lineId = 1;

  const cellCount = customers.length * products.length * weekNumbers.length;
  for (const weekNumber of weekNumbers) {
    for (const product of products) {
      customers.forEach((customer, index) => {
        const amount = Math.round(((totalAmount / cellCount) * (0.5 + random())) * 100) / 100;
        lines.push({
          lineId: lineId++,
          weekNumber,
          ean: product.ean,
          productName: product.name,
          pdvCode: customer.cnpj,
          customerName: customer.legalName,
          salesRepName: activeSellers[index % activeSellers.length].name,
          channelName: customer.channelName,
          quantity: targetKind === "quantity" ? amount : null,
          grossValue: targetKind === "value" ? amount : null,
          distributorCnpj: DEMO_DISTRIBUTORS[0].cnpj,
        });
      });
    }
  }
  return lines;
}

interface DemoGenerationInput {
  model: PlannerModel;
  params: Record<string, unknown>;
  weeks: PlannerWeekInput[] | null;
  targetKind: PlannerCoverageTargetKind;
  totalAmount: number;
}

export function generateDemoPlan(input: DemoGenerationInput): PlannerGenerationResult {
  const code = nextDemoCode();
  const lines = buildDemoLines(700 + code, input.weeks, input.targetKind, input.totalAmount);
  const totalQuantity = lines.reduce((sum, line) => sum + (line.quantity ?? 0), 0);
  const totalValue = lines.reduce((sum, line) => sum + (line.grossValue ?? 0), 0);

  const summary: PlannerPlanSummary = {
    id: `demo-plan-${code}`,
    code,
    model: input.model,
    version: 1,
    status: "generated",
    params: input.params,
    routePlanId: input.weeks ? "demo-route-plan" : null,
    routeFileName: input.weeks ? "roteiro-visitas-demo.xlsx" : null,
    lineCount: lines.length,
    totalQuantity: input.targetKind === "quantity" ? totalQuantity : null,
    totalValue: input.targetKind === "value" ? totalValue : null,
    createdAt: new Date().toISOString(),
  };
  demoPlanStore.unshift({ summary, lines });

  return {
    planId: summary.id,
    code,
    version: 1,
    lineCount: lines.length,
    allocatedQuantity: input.targetKind === "quantity" ? totalQuantity : null,
    weekTargetQuantity: input.targetKind === "quantity" ? input.totalAmount : null,
    amountPerCustomer: null,
    totalRevenueGap: input.targetKind === "value" ? totalValue : null,
    recalculatedFromWeek: null,
  };
}

function ensureSeedPlans(): void {
  if (demoPlanStore.length > 0) return;
  generateDemoPlan({
    model: "automatic",
    params: { target_month: currentMonthStart(1), weight_mode: "history" },
    weeks: [
      { weekNumber: 1, startDate: currentMonthStart(1), endDate: currentMonthStart(1) },
      { weekNumber: 2, startDate: currentMonthStart(1), endDate: currentMonthStart(1) },
    ],
    targetKind: "quantity",
    totalAmount: DEMO_MONTH_BASE_QUANTITY,
  });
  generateDemoPlan({
    model: "coverage",
    params: { target_kind: "value", target_amount: 250000 },
    weeks: null,
    targetKind: "value",
    totalAmount: 250000,
  });
}

export function getDemoPlans(): PlannerPlanSummary[] {
  ensureSeedPlans();
  return demoPlanStore.map((record) => record.summary);
}

export function getDemoPlanLines(
  planId: string,
  limit: number,
  offset: number,
): PlannerPlanLinesPage {
  ensureSeedPlans();
  const record = demoPlanStore.find((item) => item.summary.id === planId);
  if (!record) return { total: 0, rows: [] };
  return { total: record.lines.length, rows: record.lines.slice(offset, offset + limit) };
}

function buildDemoGroupRows(
  lines: PlannerPlanLine[],
  keyOf: (line: PlannerPlanLine) => string | null,
  seed: number,
): PlannerDashboardGroupRow[] {
  const random = createSeededRandom(seed);
  const groups = new Map<string, PlannerPlanLine[]>();
  for (const line of lines) {
    const key = keyOf(line) ?? "—";
    groups.set(key, [...(groups.get(key) ?? []), line]);
  }
  return Array.from(groups.entries()).map(([name, groupLines]) => {
    const plannedQuantity = groupLines.reduce((sum, line) => sum + (line.quantity ?? 0), 0);
    const plannedValue = groupLines.reduce((sum, line) => sum + (line.grossValue ?? 0), 0);
    const achievementSeedRatio = 0.4 + random() * 0.55;
    const achievedLines = Math.round(groupLines.length * achievementSeedRatio);
    const realizedQuantity = Math.round(plannedQuantity * achievementSeedRatio * 100) / 100;
    const realizedValue = Math.round(plannedValue * achievementSeedRatio * 100) / 100;
    return {
      groupId: name,
      groupName: name,
      totalLines: groupLines.length,
      achievedLines,
      achievementRate: groupLines.length > 0 ? achievedLines / groupLines.length : null,
      plannedQuantity: plannedQuantity || null,
      realizedQuantity: plannedQuantity ? realizedQuantity : null,
      plannedValue: plannedValue || null,
      realizedValue: plannedValue ? realizedValue : null,
      quantityVariation: plannedQuantity ? achievementSeedRatio - 1 : null,
      valueVariation: plannedValue ? achievementSeedRatio - 1 : null,
    };
  });
}

export function getDemoDashboard(planId: string): PlannerDashboard | null {
  ensureSeedPlans();
  const record = demoPlanStore.find((item) => item.summary.id === planId);
  if (!record) return null;

  const bySeller = buildDemoGroupRows(record.lines, (line) => line.salesRepName, 810);
  const byCustomer = buildDemoGroupRows(record.lines, (line) => line.customerName, 811);
  const byChannel = buildDemoGroupRows(record.lines, (line) => line.channelName, 812);
  const byProduct = buildDemoGroupRows(record.lines, (line) => line.productName, 813);

  const totalLines = record.lines.length;
  const achievedLines = bySeller.reduce((sum, row) => sum + row.achievedLines, 0);
  const plannedQuantity = record.summary.totalQuantity;
  const plannedValue = record.summary.totalValue;
  const sortedSellers = [...bySeller].sort(
    (a, b) => (b.achievementRate ?? 0) - (a.achievementRate ?? 0),
  );

  return {
    plan: {
      id: record.summary.id,
      code: record.summary.code,
      model: record.summary.model,
      version: record.summary.version,
      status: record.summary.status,
      params: record.summary.params,
      createdAt: record.summary.createdAt,
    },
    evalPeriod: { startDate: currentMonthStart(0), endDate: currentMonthStart(1) },
    summary: {
      totalLines,
      achievedLines: Math.min(achievedLines, totalLines),
      achievementRate: totalLines > 0 ? Math.min(achievedLines, totalLines) / totalLines : null,
      plannedQuantity,
      realizedQuantity: plannedQuantity === null ? null : Math.round(plannedQuantity * 0.72),
      plannedValue,
      realizedValue: plannedValue === null ? null : Math.round(plannedValue * 0.68),
      missedQuantity: plannedQuantity === null ? null : Math.round(plannedQuantity * 0.28),
      missedValue: plannedValue === null ? null : Math.round(plannedValue * 0.32),
    },
    bestSeller: sortedSellers[0] ?? null,
    worstSeller: sortedSellers[sortedSellers.length - 1] ?? null,
    bySeller,
    byCustomer,
    byChannel,
    byProduct,
  };
}

export const DEMO_PLANNER_CHANNEL_OPTIONS = DEMO_CHANNELS.map((channel) => ({
  id: channel.id,
  name: channel.name,
}));
