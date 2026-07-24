import { formatIsoDate } from "@/lib/format";
import type { ReportFilterState } from "@/hooks/use-report-filters";
import type { FilterOption, FilterOptions } from "@/types/reports";

const ALL_FILTERS_LABEL = "Todos";
const CURRENCY_UNIT_LABEL = "R$";
const UNITS_UNIT_LABEL = "Caixa";

function getOptionLabel(options: FilterOption[], id: string): string {
  return options.find((option) => option.id === id)?.name ?? id;
}

function formatSelectedOptions(options: FilterOption[], ids: string[]): string {
  if (ids.length === 0) return ALL_FILTERS_LABEL;
  return ids.map((id) => getOptionLabel(options, id)).join(", ");
}

export function buildReportFilterExportRows(
  filters: ReportFilterState,
  options?: FilterOptions,
  showDimensionFilters = true,
): Record<string, string>[] {
  const rows: Record<string, string>[] = [
    {
      Filtro: "Período atual",
      Valor: `${formatIsoDate(filters.currentStart)} a ${formatIsoDate(filters.currentEnd)}`,
    },
    {
      Filtro: "Meta",
      Valor: `${formatIsoDate(filters.targetStart)} a ${formatIsoDate(filters.targetEnd)}`,
    },
    {
      Filtro: "Ano anterior",
      Valor: `${formatIsoDate(filters.previousStart)} a ${formatIsoDate(filters.previousEnd)}`,
    },
  ];

  if (filters.distributorId) {
    rows.push({
      Filtro: "Distribuidora",
      Valor: options ? getOptionLabel(options.distributors, filters.distributorId) : filters.distributorId,
    });
  }

  if (!showDimensionFilters) return rows;

  rows.push(
    {
      Filtro: "Categoria",
      Valor: options
        ? formatSelectedOptions(options.categories, filters.categoryIds)
        : filters.categoryIds.join(", ") || ALL_FILTERS_LABEL,
    },
    {
      Filtro: "Subcategoria",
      Valor: options
        ? formatSelectedOptions(options.subcategories, filters.subcategoryIds)
        : filters.subcategoryIds.join(", ") || ALL_FILTERS_LABEL,
    },
    {
      Filtro: "SKU",
      Valor: options
        ? formatSelectedOptions(options.products, filters.productIds)
        : filters.productIds.join(", ") || ALL_FILTERS_LABEL,
    },
    {
      Filtro: "Unidade medida",
      Valor: filters.unit === "units" ? UNITS_UNIT_LABEL : CURRENCY_UNIT_LABEL,
    },
    {
      Filtro: "Canal",
      Valor: options
        ? formatSelectedOptions(options.channels, filters.channelIds)
        : filters.channelIds.join(", ") || ALL_FILTERS_LABEL,
    },
    {
      Filtro: "Cluster",
      Valor: options
        ? formatSelectedOptions(options.clusters, filters.clusterIds)
        : filters.clusterIds.join(", ") || ALL_FILTERS_LABEL,
    },
  );

  return rows;
}
