import { formatMonthLabel } from "@/lib/periods";
import type { PlannerModel, PlannerWeekInput } from "@/types/planner";

/**
 * Model labels are provisional (meeting 05/08/2026): Marcelo will rename them
 * later, so every screen must read from this single map.
 */
export const PLANNER_MODEL_LABELS: Record<PlannerModel, string> = {
  automatic: "Automático",
  battleship_volume: "Batalha Naval Volume",
  battleship_positivation: "Batalha Naval Positivação",
  coverage: "Cobertura",
  profitability: "Rentabilidade",
};

export const PLANNER_WEEK_COUNT_OPTIONS = [3, 4, 5] as const;

const PLAN_CODE_DIGITS = 3;

/** Sequential plan identifier shown in the UI (PLN-001). */
export function formatPlanCode(code: number): string {
  return `PLN-${String(code).padStart(PLAN_CODE_DIGITS, "0")}`;
}

/** Error codes raised by the planner_* RPCs mapped to pt-BR feedback. */
export const PLANNER_ERROR_MESSAGES: Record<string, string> = {
  NO_ROUTE_PLAN:
    "Nenhum roteiro de visitas importado. Importe o roteiro na Parametrização antes de gerar.",
  NO_TARGETS_FOR_MONTH: "Não há meta de Sell Out cadastrada para o mês selecionado.",
  INVALID_WEEKS: "Configuração de semanas inválida. Revise os números e as datas.",
  INVALID_MODE: "Modo de geração inválido.",
  INVALID_TARGET: "Informe uma meta válida (maior que zero).",
  MISSING_PRODUCT: "Selecione o SKU antes de gerar.",
  INVALID_MARGIN: "Informe uma margem objetivo entre 0% e 100%.",
  INVALID_PERIOD: "Período inválido: a data inicial deve ser anterior à final.",
  NO_REFERENCE_SALES: "O SKU de referência não teve vendas no mês/canal selecionado.",
  NO_UNCOVERED_CUSTOMERS: "Nenhum PDV descoberto no período selecionado.",
  NO_COST_DATA:
    "Sem Sell In do SKU no período analisado (nem nos 3 meses anteriores) para calcular o custo.",
  NO_CUSTOMERS_BELOW_MARGIN: "Nenhum PDV ficou abaixo da margem objetivo no período.",
  PLAN_NOT_FOUND: "Planificador não encontrado.",
  PLAN_ALREADY_REPLACED: "Este planificador já foi substituído por uma versão mais nova.",
  PLAN_NOT_WEEKLY: "Recalcular Rota só se aplica a planificadores com abertura semanal.",
  NO_CLOSED_WEEKS: "Nenhuma semana fechada ainda: o recálculo é liberado após o fim da 1ª semana.",
  NO_REMAINING_WEEKS: "Todas as semanas já terminaram: não há semanas restantes para redistribuir.",
};

const DEFAULT_PLANNER_ERROR = "Falha ao processar. Tente novamente.";

/** Resolves an RPC error into user-facing feedback (codes come from the DB). */
export function resolvePlannerErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error ?? "");
  const code = Object.keys(PLANNER_ERROR_MESSAGES).find((key) => raw.includes(key));
  return code ? PLANNER_ERROR_MESSAGES[code] : DEFAULT_PLANNER_ERROR;
}

function toIsoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

const SATURDAY_WEEKDAY_INDEX = 6;
const DAY_IN_MS = 86_400_000;

/** Last day of the month, for constraining week date pickers. */
export function getMonthEndIso(monthStart: string): string {
  const start = new Date(`${monthStart.slice(0, 8)}01T00:00:00Z`);
  const nextMonth = new Date(start);
  nextMonth.setUTCMonth(nextMonth.getUTCMonth() + 1);
  return toIsoDate(new Date(nextMonth.getTime() - DAY_IN_MS));
}

/**
 * Suggests calendar week ranges (Sunday to Saturday, same convention as the
 * reports' week number) clipped to the target month — week dates never leave
 * the month (Eduardo, 06/08/2026: for September, the first week is Tue 1 to
 * Sat 5). When the month has more calendar weeks than weekCount, the extra
 * days stay unplanned (the distributor concentrates sales in fewer weeks) and
 * the user adjusts the dates as needed.
 */
export function buildDefaultWeeks(monthStart: string, weekCount: number): PlannerWeekInput[] {
  const start = new Date(`${monthStart.slice(0, 8)}01T00:00:00Z`);
  const monthEnd = new Date(`${getMonthEndIso(monthStart)}T00:00:00Z`);

  const weeks: PlannerWeekInput[] = [];
  let cursor = start;
  while (cursor <= monthEnd && weeks.length < weekCount) {
    const daysUntilSaturday = SATURDAY_WEEKDAY_INDEX - cursor.getUTCDay();
    const saturday = new Date(cursor.getTime() + daysUntilSaturday * DAY_IN_MS);
    const weekEnd = saturday < monthEnd ? saturday : monthEnd;
    weeks.push({
      weekNumber: weeks.length + 1,
      startDate: toIsoDate(cursor),
      endDate: toIsoDate(weekEnd),
    });
    cursor = new Date(weekEnd.getTime() + DAY_IN_MS);
  }
  return weeks;
}

const ROUTE_TEMPLATE_BASE_HEADERS = [
  "Marca",
  "CNPJ Distribuidor",
  "CNPJ/CPF Cliente",
  "Cód. Vendedor",
];

/** CSV template for the visit route import ("Baixar modelo" button). */
export function buildRouteTemplateCsv(weekCount: number): string {
  const weekHeaders = Array.from({ length: weekCount }, (_, index) => `Semana ${index + 1}`);
  const headers = [...ROUTE_TEMPLATE_BASE_HEADERS, ...weekHeaders];
  const exampleRow = ["Marca Exemplo", "00000000000000", "11111111000111", "1", "x"];
  return [headers.join(";"), exampleRow.join(";")].join("\n");
}

/**
 * Month options for reference selectors: previous year plus the already
 * completed months of the current year (spec §4.1 — the current month is
 * still in progress and cannot be a reference).
 */
export function buildReferenceMonthOptions(today: Date): { value: string; label: string }[] {
  const options: { value: string; label: string }[] = [];
  const currentYear = today.getFullYear();
  const lastCompletedMonth = today.getMonth() - 1;
  for (let year = currentYear - 1; year <= currentYear; year += 1) {
    const lastMonth = year === currentYear ? lastCompletedMonth : 11;
    for (let month = 0; month <= lastMonth; month += 1) {
      const value = `${year}-${String(month + 1).padStart(2, "0")}-01`;
      options.push({ value, label: formatMonthLabel(value) });
    }
  }
  return options.reverse();
}
