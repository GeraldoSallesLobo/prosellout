"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { ExportButton, type ExportSection } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import {
  REPORT_QUERY_FRESHNESS,
  toReportFilters,
  useReportFilters,
} from "@/hooks/use-report-filters";
import { fetchFilterOptions, fetchThreeMonthHistory } from "@/lib/data/reports";
import {
  formatCompactCurrency,
  formatCurrency,
  formatInteger,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import { formatMonthLabel, getMonthStartFromIsoDate } from "@/lib/periods";
import { buildReportFilterExportRows } from "@/lib/report-export";
import type { MonthHistoryRow } from "@/types/reports";

interface MetricSpec {
  key: string;
  label: string;
  pick: (row: MonthHistoryRow) => number | null;
  format: (value: number | null) => string;
  exportFormat?: (value: number | null) => string;
}

function safeDivide(numerator: number, denominator: number): number | null {
  return denominator === 0 ? null : numerator / denominator;
}

function getVariation(currentValue: number | null, comparisonValue: number | null): number | null {
  return currentValue !== null && comparisonValue !== null && comparisonValue !== 0
    ? currentValue / comparisonValue - 1
    : null;
}

function getMarkupPct(row: MonthHistoryRow): number | null {
  if (row.totalCost === null || row.totalCost === 0) return null;
  return (row.totalValue - row.totalCost) / row.totalCost;
}

function getMarginPct(row: MonthHistoryRow): number | null {
  if (row.totalCost === null) return null;
  return safeDivide(row.totalValue - row.totalCost, row.totalValue);
}

function VariationBadge({
  label,
  value,
}: {
  label: string;
  value: number | null;
}) {
  if (value === null) return <span className="h-[18px]" />;

  return (
    <span
      className={clsx(
        "rounded-md px-1.5 py-0.5 text-[10px] font-bold",
        value >= 0 ? "bg-green/10 text-green" : "bg-red/10 text-red",
      )}
    >
      {label} {formatVariation(value)}
    </span>
  );
}

function getComparisonLabel(isPreviousPeriod: boolean, isTwoMonthsBackPeriod: boolean): string {
  if (isTwoMonthsBackPeriod) return "M x M-2";
  if (isPreviousPeriod) return "M x M-1";
  return "";
}

function getBarColorClass(isCurrent: boolean, isTwoMonthsBackPeriod: boolean): string {
  if (isCurrent) return "bg-chartCurrent";
  if (isTwoMonthsBackPeriod) return "bg-orange";
  return "bg-chartPrevious";
}

const METRIC_SPECS: MetricSpec[] = [
  {
    key: "value",
    label: "Sell Out R$",
    pick: (row) => row.totalValue,
    format: formatCompactCurrency,
    exportFormat: formatCurrency,
  },
  { key: "quantity", label: "Sell Out Volume", pick: (row) => row.totalQuantity, format: formatInteger },
  { key: "coverage", label: "Cobertura", pick: (row) => row.coverage, format: formatInteger },
  {
    key: "ticket",
    label: "Ticket Médio",
    pick: (row) => safeDivide(row.totalValue, row.coverage),
    format: formatCurrency,
  },
  {
    key: "price",
    label: "Preço Médio",
    pick: (row) => safeDivide(row.totalValue, row.totalQuantity),
    format: formatCurrency,
  },
  {
    key: "drop",
    label: "Drop Size",
    pick: (row) => safeDivide(row.totalValue, row.orderCount),
    format: formatCurrency,
  },
  {
    key: "markup",
    label: "Mark Up %",
    pick: getMarkupPct,
    format: formatPercent,
  },
  {
    key: "margin",
    label: "Margem %",
    pick: getMarginPct,
    format: formatPercent,
  },
];

function MetricHistoryCard({
  spec,
  months,
}: {
  spec: MetricSpec;
  months: MonthHistoryRow[];
}) {
  const values = months.map((month) => spec.pick(month));
  const currentValue = values[values.length - 1] ?? null;
  const maxValue = Math.max(...values.map((value) => Math.abs(value ?? 0)), 1);

  return (
    <div className="card p-4">
      <div>
        <h3 className="text-[13px] font-bold text-text1">{spec.label}</h3>
      </div>

      <div className="mt-3 flex items-end justify-between gap-3">
        {months.map((month, index) => {
          const value = values[index];
          const isCurrent = index === months.length - 1;
          const isPreviousPeriod = index === months.length - 2;
          const isTwoMonthsBackPeriod = index === months.length - 3;
          const comparisonLabel = getComparisonLabel(isPreviousPeriod, isTwoMonthsBackPeriod);
          const variation = comparisonLabel ? getVariation(currentValue, value) : null;
          const barHeight = Math.max(8, Math.round(((value ?? 0) / maxValue) * 56));
          const barColorClass = getBarColorClass(isCurrent, isTwoMonthsBackPeriod);
          return (
            <div key={month.monthStart} className="flex flex-1 flex-col items-center gap-1.5">
              {comparisonLabel ? (
                <VariationBadge label={comparisonLabel} value={variation} />
              ) : (
                <span className="h-[18px]" />
              )}
              <span
                className={clsx(
                  "text-xs font-bold",
                  isCurrent ? "text-text1" : "text-text2",
                )}
              >
                {spec.format(value)}
              </span>
              <div
                className={clsx(
                  "w-full max-w-12 rounded-t",
                  barColorClass,
                )}
                style={{ height: `${barHeight}px` }}
              />
              <span className="text-[10px] uppercase tracking-wide text-text2">
                {formatMonthLabel(month.monthStart)}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function buildThreeMonthHistoryExportRows(months: MonthHistoryRow[]): Record<string, string>[] {
  return METRIC_SPECS.map((spec) => {
    const values = months.map((month) => spec.pick(month));
    const currentValue = values[values.length - 1] ?? null;
    const mTwoValue = values[values.length - 3] ?? null;
    const mOneValue = values[values.length - 2] ?? null;
    const formatExportValue = spec.exportFormat ?? spec.format;
    const mTwoLabel = months[months.length - 3]?.monthStart
      ? formatMonthLabel(months[months.length - 3].monthStart)
      : "M-2";
    const mOneLabel = months[months.length - 2]?.monthStart
      ? formatMonthLabel(months[months.length - 2].monthStart)
      : "M-1";
    const currentLabel = months[months.length - 1]?.monthStart
      ? formatMonthLabel(months[months.length - 1].monthStart)
      : "M";

    return {
      Indicador: spec.label,
      [mTwoLabel]: formatExportValue(mTwoValue),
      "M x M-2": formatVariation(getVariation(currentValue, mTwoValue)),
      [mOneLabel]: formatExportValue(mOneValue),
      "M x M-1": formatVariation(getVariation(currentValue, mOneValue)),
      [currentLabel]: formatExportValue(currentValue),
    };
  });
}

export default function ThreeMonthHistoryPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);
  const referenceMonth = getMonthStartFromIsoDate(filters.currentEnd || filters.currentStart);

  const { data: filterOptions } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
    enabled: isHydrated,
  });

  const { data: months = [], isLoading } = useQuery({
    queryKey: ["three-month-history", referenceMonth, reportFilters],
    queryFn: () => fetchThreeMonthHistory(referenceMonth, reportFilters),
    enabled: isHydrated,
    ...REPORT_QUERY_FRESHNESS,
  });

  return (
    <div>
      <PageHeader
        title="Análise Histórico 3 Meses"
        description="Cada métrica com M-2, M-1 e mês atual + variação"
        actions={
          <ExportButton
            fileName="historico-3m"
            getSections={() => {
              const sections: ExportSection[] = [
                {
                  title: "Filtros",
                  rows: buildReportFilterExportRows(filters, filterOptions, {
                    showTargetPeriod: false,
                    showPreviousPeriod: false,
                  }),
                },
                {
                  title: "Histórico 3 Meses",
                  rows: buildThreeMonthHistoryExportRows(months),
                },
              ];

              return sections;
            }}
          />
        }
      />

      <ReportFilterBar
        filters={filters}
        onChange={setFilters}
        showTargetPeriod={false}
        showPreviousPeriod={false}
      />

      {isLoading ? (
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 8 }).map((_, index) => (
            <Skeleton key={index} className="h-40 w-full rounded-card" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
          {METRIC_SPECS.map((spec) => (
            <MetricHistoryCard key={spec.key} spec={spec} months={months} />
          ))}
        </div>
      )}
    </div>
  );
}
