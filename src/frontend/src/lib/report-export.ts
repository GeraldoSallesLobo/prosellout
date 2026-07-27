import {
  formatCurrency,
  formatDecimal,
  formatInteger,
  formatIsoDate,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import type { ReportFilterState } from "@/hooks/use-report-filters";
import type { SearchState } from "@/lib/search";
import type { AnalysisRow, FilterOption, FilterOptions } from "@/types/reports";

const ALL_FILTERS_LABEL = "Todos";
const CURRENCY_UNIT_LABEL = "R$";
const UNITS_UNIT_LABEL = "Caixa";
const NO_SEARCH_LABEL = "Sem busca";
const CURRENT_PAGE_SCOPE_LABEL = "Página atual";

interface ReportFilterExportConfig {
  showDimensionFilters?: boolean;
  showTargetPeriod?: boolean;
  showPreviousPeriod?: boolean;
}

interface PeriodFilterExportState {
  start: string;
  end: string;
  distributorId: string;
}

interface PeriodFilterExportConfig {
  showStartDate?: boolean;
  endDateLabel?: string;
}

interface DataExportContext {
  search?: SearchState | null;
  searchLabels?: Record<string, string>;
  page?: number;
  pageSize?: number;
  total?: number;
  exportedCount?: number;
  scopeLabel?: string;
}

type ReportFilterExportConfigInput = boolean | ReportFilterExportConfig;

export function getFilterOptionLabel(
  options: FilterOption[] | undefined,
  id: string,
): string {
  if (!id) return ALL_FILTERS_LABEL;
  return options?.find((option) => option.id === id)?.name ?? id;
}

export function formatSelectedFilterOptions(
  options: FilterOption[] | undefined,
  ids: string[],
): string {
  if (ids.length === 0) return ALL_FILTERS_LABEL;
  return ids.map((id) => getFilterOptionLabel(options, id)).join(", ");
}

function normalizeReportFilterExportConfig(
  input: ReportFilterExportConfigInput = {},
): Required<ReportFilterExportConfig> {
  if (typeof input === "boolean") {
    return {
      showDimensionFilters: input,
      showTargetPeriod: true,
      showPreviousPeriod: true,
    };
  }

  return {
    showDimensionFilters: input.showDimensionFilters ?? true,
    showTargetPeriod: input.showTargetPeriod ?? true,
    showPreviousPeriod: input.showPreviousPeriod ?? true,
  };
}

export function buildReportFilterExportRows(
  filters: ReportFilterState,
  options?: FilterOptions,
  configInput: ReportFilterExportConfigInput = {},
): Record<string, string>[] {
  const config = normalizeReportFilterExportConfig(configInput);
  const rows: Record<string, string>[] = [
    {
      Filtro: "Período atual",
      Valor: `${formatIsoDate(filters.currentStart)} a ${formatIsoDate(filters.currentEnd)}`,
    },
  ];

  if (config.showTargetPeriod) {
    rows.push({
      Filtro: "Meta",
      Valor: `${formatIsoDate(filters.targetStart)} a ${formatIsoDate(filters.targetEnd)}`,
    });
  }

  if (config.showPreviousPeriod) {
    rows.push({
      Filtro: "Ano anterior",
      Valor: `${formatIsoDate(filters.previousStart)} a ${formatIsoDate(filters.previousEnd)}`,
    });
  }

  if (filters.distributorId) {
    rows.push({
      Filtro: "Distribuidora",
      Valor: getFilterOptionLabel(options?.distributors, filters.distributorId),
    });
  }

  if (!config.showDimensionFilters) return rows;

  rows.push(
    {
      Filtro: "Categoria",
      Valor: formatSelectedFilterOptions(options?.categories, filters.categoryIds),
    },
    {
      Filtro: "Subcategoria",
      Valor: formatSelectedFilterOptions(options?.subcategories, filters.subcategoryIds),
    },
    {
      Filtro: "SKU",
      Valor: formatSelectedFilterOptions(options?.products, filters.productIds),
    },
    {
      Filtro: "Unidade medida",
      Valor: filters.unit === "units" ? UNITS_UNIT_LABEL : CURRENCY_UNIT_LABEL,
    },
    {
      Filtro: "Canal",
      Valor: formatSelectedFilterOptions(options?.channels, filters.channelIds),
    },
    {
      Filtro: "Cluster",
      Valor: formatSelectedFilterOptions(options?.clusters, filters.clusterIds),
    },
  );

  return rows;
}

export function buildPeriodFilterExportRows(
  filters: PeriodFilterExportState,
  options?: FilterOptions,
  config: PeriodFilterExportConfig = {},
): Record<string, string>[] {
  const showStartDate = config.showStartDate ?? true;
  const endDateLabel = config.endDateLabel ?? "Período Fim";
  const rows: Record<string, string>[] = [];

  if (filters.distributorId) {
    rows.push({
      Filtro: "Distribuidora",
      Valor: getFilterOptionLabel(options?.distributors, filters.distributorId),
    });
  }

  if (showStartDate) {
    rows.push({
      Filtro: "Período Início",
      Valor: formatIsoDate(filters.start),
    });
  }

  rows.push({
    Filtro: endDateLabel,
    Valor: formatIsoDate(filters.end),
  });

  return rows;
}

export function buildSearchExportRows(
  search?: SearchState | null,
  searchLabels: Record<string, string> = {},
): Record<string, string>[] {
  if (!search?.text) {
    return [{ Filtro: "Busca", Valor: NO_SEARCH_LABEL }];
  }

  return [
    {
      Filtro: "Busca",
      Valor: `${searchLabels[search.key] ?? search.key}: ${search.text}`,
    },
  ];
}

export function buildDataExportContextRows(context: DataExportContext): Record<string, string>[] {
  const rows = buildSearchExportRows(context.search, context.searchLabels);

  rows.push({
    Filtro: "Escopo exportado",
    Valor: context.scopeLabel ?? CURRENT_PAGE_SCOPE_LABEL,
  });

  if (context.page !== undefined) {
    rows.push({
      Filtro: "Página",
      Valor: String(context.page),
    });
  }

  if (context.pageSize !== undefined) {
    rows.push({
      Filtro: "Registros por página",
      Valor: String(context.pageSize),
    });
  }

  if (context.exportedCount !== undefined) {
    rows.push({
      Filtro: "Registros exportados",
      Valor: String(context.exportedCount),
    });
  }

  if (context.total !== undefined) {
    rows.push({
      Filtro: "Total filtrado",
      Valor: String(context.total),
    });
  }

  return rows;
}

export function buildStatusAnalysisExportRows(rows: AnalysisRow[]): Record<string, string>[] {
  return rows.map((row) => ({
    Grupo: row.groupName,
    "Sell Out R$ Atual": formatCurrency(row.currentValue),
    Meta: formatCurrency(row.targetValue),
    "Atual x Meta": formatVariation(row.currentVsTarget),
    "Ano anterior": formatCurrency(row.previousValue),
    "Atual x Ano anterior": formatVariation(
      row.previousValue !== 0 ? row.currentValue / row.previousValue - 1 : null,
    ),
    "Anterior x Meta": formatVariation(row.previousVsTarget),
    "Cobertura UN": formatInteger(row.coverage),
    "Ticket Médio": formatCurrency(row.avgTicket),
    "Drop Size": formatDecimal(row.dropSize),
    "Preço Médio": formatCurrency(row.avgPrice),
    "Mark Up %": formatPercent(row.markupPct),
    "Margem %": formatPercent(row.marginPct),
    "Giro Médio": formatDecimal(row.avgTurnover),
    "Cobertura Média": formatDecimal(row.avgCoverage),
  }));
}
