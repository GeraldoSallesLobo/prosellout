"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { useReportFilters, toReportFilters } from "@/hooks/use-report-filters";
import { fetchThreeMonthHistory } from "@/lib/data/reports";
import {
  formatCompactCurrency,
  formatCurrency,
  formatInteger,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import { formatMonthLabel, getMonthStart } from "@/lib/periods";
import type { MonthHistoryRow } from "@/types/reports";

interface MetricSpec {
  key: string;
  label: string;
  pick: (row: MonthHistoryRow) => number | null;
  format: (value: number | null) => string;
}

function safeDivide(numerator: number, denominator: number): number | null {
  return denominator === 0 ? null : numerator / denominator;
}

const METRIC_SPECS: MetricSpec[] = [
  { key: "value", label: "Sell Out R$", pick: (row) => row.totalValue, format: formatCompactCurrency },
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
    pick: (row) => safeDivide(row.totalQuantity, row.invoiceCount),
    format: formatInteger,
  },
  {
    key: "markup",
    label: "Mark Up %",
    pick: (row) => (row.totalCost === 0 ? null : (row.totalValue - row.totalCost) / row.totalCost),
    format: formatPercent,
  },
  {
    key: "margin",
    label: "Margem %",
    pick: (row) => safeDivide(row.totalValue - row.totalCost, row.totalValue),
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
  const previousValue = values.length > 1 ? values[values.length - 2] : null;
  const variation =
    currentValue !== null && previousValue !== null && previousValue !== 0
      ? currentValue / previousValue - 1
      : null;
  const maxValue = Math.max(...values.map((value) => Math.abs(value ?? 0)), 1);

  return (
    <div className="card p-4">
      <div className="flex items-center justify-between">
        <h3 className="text-[13px] font-bold text-text1">{spec.label}</h3>
        {variation !== null ? (
          <span
            className={clsx(
              "rounded-md px-1.5 py-0.5 text-[11px] font-bold",
              variation >= 0 ? "bg-green/10 text-green" : "bg-red/10 text-red",
            )}
          >
            {formatVariation(variation)}
          </span>
        ) : null}
      </div>

      <div className="mt-3 flex items-end justify-between gap-3">
        {months.map((month, index) => {
          const value = values[index];
          const isCurrent = index === months.length - 1;
          const barHeight = Math.max(8, Math.round(((value ?? 0) / maxValue) * 56));
          return (
            <div key={month.monthStart} className="flex flex-1 flex-col items-center gap-1.5">
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
                  isCurrent ? "bg-chartCurrent" : "bg-chartPrevious",
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

export default function ThreeMonthHistoryPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);
  const referenceMonth = getMonthStart();

  const { data: months = [], isLoading } = useQuery({
    queryKey: ["three-month-history", referenceMonth, reportFilters],
    queryFn: () => fetchThreeMonthHistory(referenceMonth, reportFilters),
    enabled: isHydrated,
  });

  return (
    <div>
      <PageHeader
        title="Análise Histórico 3 Meses"
        description="Cada métrica com M-2, M-1 e mês atual + variação"
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
