import type {
  AnalysisRow,
  EvolutionAnalysisRow,
  EvolutionGroupBy,
  FastFactsReport,
  MonthHistoryRow,
  StatusGroupBy,
  StatusMtdReport,
  WeeklyBucket,
} from "@/types/reports";
import { getMonthStart } from "@/lib/periods";
import { createSeededRandom } from "./random";

// KPI figures taken from the STATUS sheet of the reference workbook.
export const DEMO_STATUS_MTD: StatusMtdReport = {
  sellOutValue: buildBlock(1_500_000, 1_450_000, 1_250_000),
  sellOutQuantity: buildBlock(50_000, 48_000, 45_000),
  coverage: buildBlock(1_582, 1_500, 1_300),
  avgTicket: buildBlock(948.17, 966.67, 961.54),
  dropSize: buildBlock(500, 455, 425),
  avgPrice: buildBlock(500, 400, 350),
  markupPct: buildBlock(0.25, 0.24, 0.23),
  marginPct: buildBlock(0.15, 0.14, 0.135),
  avgTurnover: buildBlock(2.8, 2.6, 2.4),
  avgCoverage: buildBlock(0.42, 0.4, 0.38),
  trendValue: { projected: 1_620_000, projectedVsTarget: 1_620_000 / 1_450_000 - 1 },
  probabilityValue: 0.73,
  probabilityCoverage: 0.83,
  probabilityTicket: 0.58,
};

function buildBlock(current: number, target: number | null, previous: number) {
  return {
    current,
    target,
    previous,
    currentVsTarget: target ? current / target - 1 : null,
    previousVsTarget: target ? previous / target - 1 : null,
  };
}

interface AnalysisSeed {
  id: string;
  name: string;
  current: number;
  target: number;
  previous: number;
  coverage: number;
}

// Rows mirror the approved mockup table (Vendedores | Categorias | Canais).
const SELLER_ROWS: AnalysisSeed[] = [
  { id: "seller-1", name: "Vendedor 1", current: 44_202, target: 432_870, previous: 62_057, coverage: 45 },
  { id: "seller-2", name: "Vendedor 2", current: 34_112, target: 218_698, previous: 40_697, coverage: 46 },
  { id: "seller-3", name: "Vendedor 3", current: 82_823, target: 426_690, previous: 56_007, coverage: 51 },
  { id: "seller-4", name: "Vendedor 4", current: 202_068, target: 371_000, previous: 148_220, coverage: 52 },
  { id: "seller-5", name: "Vendedor 5", current: 187_310, target: 402_512, previous: 159_607, coverage: 118 },
  { id: "seller-6", name: "Vendedor 6", current: 214_889, target: 388_204, previous: 175_113, coverage: 92 },
  { id: "seller-7", name: "Vendedor 7", current: 158_400, target: 405_930, previous: 121_540, coverage: 68 },
  { id: "seller-8", name: "Vendedor 8", current: 126_700, target: 829_618, previous: 104_331, coverage: 70 },
];

const CATEGORY_ROWS: AnalysisSeed[] = [
  { id: "cat-1", name: "Snacks de Batatas", current: 84_169, target: 374_306, previous: 98_410, coverage: 120 },
  { id: "cat-2", name: "Yok Extrusados", current: 682_607, target: 1_126_700, previous: 512_004, coverage: 341 },
  { id: "cat-3", name: "Popcorn Microondas", current: 497_124, target: 622_500, previous: 401_356, coverage: 97 },
  { id: "cat-4", name: "Batata Palha", current: 367_897, target: 2_349_214, previous: 296_818, coverage: 250 },
];

const CHANNEL_ROWS: AnalysisSeed[] = [
  { id: "channel-6", name: "Acima 10 Check", current: 693_905, target: 2_621_500, previous: 501_230, coverage: 69 },
  { id: "channel-2", name: "Padaria", current: 567_485, target: 2_810_600, previous: 488_112, coverage: 74 },
  { id: "channel-7", name: "Confeitaria", current: 1_152_230, target: 4_925_400, previous: 903_540, coverage: 71 },
  { id: "channel-8", name: "Conveniência", current: 1_242_045, target: 2_630_400, previous: 990_224, coverage: 61 },
  { id: "channel-4", name: "Até 4 Check", current: 858_320, target: 1_922_800, previous: 745_910, coverage: 88 },
];

const AVG_INVOICES_PER_CUSTOMER = 2.1;
const DEMO_AVG_PRICE = 27.4;
const DEMO_MARKUP = 0.25;
const DEMO_MARGIN = 0.15;
const DEMO_TURNOVER = 2.8;
const DEMO_AVG_COVERAGE = 0.42;

function toAnalysisRow(seed: AnalysisSeed, index: number): AnalysisRow {
  const random = createSeededRandom(index + 7);
  const avgTicket = seed.current / seed.coverage;
  const quantity = seed.current / DEMO_AVG_PRICE;
  const invoiceCount = seed.coverage * AVG_INVOICES_PER_CUSTOMER;
  return {
    groupId: seed.id,
    groupName: seed.name,
    currentValue: seed.current,
    targetValue: seed.target,
    currentVsTarget: seed.current / seed.target - 1,
    previousValue: seed.previous,
    previousVsTarget: seed.previous / seed.target - 1,
    coverage: seed.coverage,
    avgTicket,
    dropSize: quantity / invoiceCount,
    avgPrice: DEMO_AVG_PRICE * (0.9 + random() * 0.25),
    markupPct: DEMO_MARKUP * (0.9 + random() * 0.3),
    marginPct: DEMO_MARGIN * (0.9 + random() * 0.3),
    avgTurnover: DEMO_TURNOVER * (0.85 + random() * 0.35),
    avgCoverage: DEMO_AVG_COVERAGE * (0.8 + random() * 0.4),
  };
}

const ANALYSIS_BY_GROUP: Record<StatusGroupBy, AnalysisSeed[]> = {
  seller: SELLER_ROWS,
  category: CATEGORY_ROWS,
  channel: CHANNEL_ROWS,
};

export function getDemoStatusAnalysis(groupBy: StatusGroupBy): AnalysisRow[] {
  return ANALYSIS_BY_GROUP[groupBy].map(toAnalysisRow);
}

export function getDemoFastFacts(): FastFactsReport {
  return {
    seller: dimension("seller", 9, 4, 0.62, "Vendedor 6", 1.18, "Vendedor 8", 0.15),
    supervisor: dimension("supervisor", 3, 1, 0.58, "Supervisor 2", 1.05, "Supervisor 3", 0.41),
    product: dimension("product", 12, 5, 0.55, "EXTRAFINA 20X100G", 1.31, "ONDULADA 36/45G", 0.22),
    category: dimension("category", 4, 1, 0.51, "Popcorn Microondas", 1.02, "Batata Palha", 0.16),
    channel: dimension("channel", 8, 3, 0.47, "Conveniência", 1.08, "Padaria", 0.2),
    customer: dimension("customer", 40, 14, 0.44, "Cliente 012 Comércio de Alimentos Ltda", 1.65, "Cliente 031 Comércio de Alimentos Ltda", 0.05),
  };
}

function dimension(
  name: string,
  eligible: number,
  achieved: number,
  probability: number,
  bestName: string,
  bestAchievement: number,
  worstName: string,
  worstAchievement: number,
) {
  const bestCurrentValue = 180_000 * bestAchievement;
  const bestTargetValue = 180_000;
  const bestPreviousValue = 165_000;
  const worstCurrentValue = 95_000 * worstAchievement;
  const worstTargetValue = 95_000;
  const worstPreviousValue = 110_000;

  return {
    dimension: name,
    eligibleCount: eligible,
    achievedCount: achieved,
    notAchievedCount: eligible - achieved,
    achievedPct: achieved / eligible,
    avgProbability: probability,
    best: {
      name: bestName,
      achievement: bestAchievement,
      currentValue: bestCurrentValue,
      targetValue: bestTargetValue,
      previousValue: bestPreviousValue,
      currentVsTarget: bestAchievement - 1,
      currentVsPrevious: bestCurrentValue / bestPreviousValue - 1,
    },
    worst: {
      name: worstName,
      achievement: worstAchievement,
      currentValue: worstCurrentValue,
      targetValue: worstTargetValue,
      previousValue: worstPreviousValue,
      currentVsTarget: worstAchievement - 1,
      currentVsPrevious: worstCurrentValue / worstPreviousValue - 1,
    },
  };
}

const WEEKS_IN_MONTH = 5;

export function getDemoWeeklyBuckets(): WeeklyBucket[] {
  const random = createSeededRandom(11);
  const monthStart = getMonthStart();
  const [year, month] = monthStart.split("-").map(Number);
  return Array.from({ length: WEEKS_IN_MONTH }, (_, index) => {
    const day = Math.min(1 + index * 7, 28);
    const totalValue = 240_000 + random() * 160_000;
    const coverage = Math.round(280 + random() * 140);
    return {
      bucketStart: `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
      totalValue,
      totalQuantity: totalValue / DEMO_AVG_PRICE,
      coverage,
      invoiceCount: Math.round(coverage * AVG_INVOICES_PER_CUSTOMER),
    };
  });
}

export function getDemoThreeMonthHistory(): MonthHistoryRow[] {
  const now = new Date();
  const random = createSeededRandom(23);
  return [2, 1, 0].map((offset) => {
    const reference = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    const totalValue = 1_150_000 + random() * 550_000;
    const coverage = Math.round(1_200 + random() * 500);
    return {
      monthStart: getMonthStart(reference),
      totalValue,
      totalQuantity: totalValue / DEMO_AVG_PRICE,
      totalCost: totalValue * (1 - DEMO_MARGIN),
      coverage,
      invoiceCount: Math.round(coverage * AVG_INVOICES_PER_CUSTOMER),
    };
  });
}

const EVOLUTION_SEEDS: Record<EvolutionGroupBy, { id: string; name: string }[]> = {
  category: CATEGORY_ROWS.map(({ id, name }) => ({ id, name })),
  channel: CHANNEL_ROWS.map(({ id, name }) => ({ id, name })),
  customer: Array.from({ length: 12 }, (_, index) => ({
    id: `cust-${index + 1}`,
    name: `Cliente ${String(index + 1).padStart(3, "0")} Comércio de Alimentos Ltda`,
  })),
};

export function getDemoEvolutionAnalysis(groupBy: EvolutionGroupBy): EvolutionAnalysisRow[] {
  const random = createSeededRandom(groupBy.length * 13);
  return EVOLUTION_SEEDS[groupBy].map(({ id, name }) => {
    const currentValue = 90_000 + random() * 700_000;
    const previousValue = currentValue * (0.7 + random() * 0.6);
    const currentQuantity = currentValue / DEMO_AVG_PRICE;
    const previousQuantity = previousValue / DEMO_AVG_PRICE;
    const currentTicket = 600 + random() * 900;
    const previousTicket = currentTicket * (0.8 + random() * 0.4);
    return {
      groupId: id,
      groupName: name,
      currentValue,
      previousValue,
      valueChangePct: currentValue / previousValue - 1,
      currentQuantity,
      previousQuantity,
      quantityChangePct: currentQuantity / previousQuantity - 1,
      currentTicket,
      previousTicket,
      ticketChangePct: currentTicket / previousTicket - 1,
    };
  });
}
