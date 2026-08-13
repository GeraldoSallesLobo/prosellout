"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { ExportButton, type ExportSection } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { ComboChart, type ComboChartDatum } from "@/components/charts/combo-chart";
import {
  REPORT_QUERY_FRESHNESS,
  toReportFilters,
  useReportFilters,
} from "@/hooks/use-report-filters";
import { fetchEvolutionWeekly, fetchFilterOptions } from "@/lib/data/reports";
import {
  formatCompactCurrency,
  formatCurrency,
  formatInteger,
} from "@/lib/format";
import { buildReportFilterExportRows } from "@/lib/report-export";
import { getSundayWeekNumber } from "@/lib/periods";
import type { WeeklyBucket } from "@/types/reports";

function weekLabel(bucketStart: string): string {
  const weekNumber = getSundayWeekNumber(bucketStart);
  return weekNumber ? `Semana ${weekNumber}` : bucketStart;
}

function buildSeries(
  buckets: WeeklyBucket[],
  pickBar: (bucket: WeeklyBucket) => number,
  pickLine: (bucket: WeeklyBucket) => number,
): ComboChartDatum[] {
  return buckets.map((bucket) => ({
    name: weekLabel(bucket.bucketStart),
    barValue: pickBar(bucket),
    lineValue: pickLine(bucket),
  }));
}

function safeDivide(numerator: number, denominator: number): number | null {
  return denominator === 0 ? null : numerator / denominator;
}

function buildWeeklyExportRows(buckets: WeeklyBucket[]): Record<string, string>[] {
  return buckets.map((bucket) => ({
    Semana: weekLabel(bucket.bucketStart),
    "Sell Out R$": formatCurrency(bucket.totalValue),
    Positivação: formatInteger(bucket.coverage),
    "Ticket Médio": formatCurrency(safeDivide(bucket.totalValue, bucket.coverage)),
    Volume: formatInteger(bucket.totalQuantity),
    "Drop Size": formatCurrency(safeDivide(bucket.totalValue, bucket.orderCount)),
    "Preço Médio": formatCurrency(safeDivide(bucket.totalValue, bucket.totalQuantity)),
  }));
}

export default function MonthlyEvolutionPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: buckets = [], isLoading } = useQuery({
    queryKey: ["evolution-weekly", reportFilters],
    queryFn: () => fetchEvolutionWeekly(reportFilters),
    enabled: isHydrated,
    ...REPORT_QUERY_FRESHNESS,
  });

  const { data: filterOptions } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
    enabled: isHydrated,
  });

  return (
    <div>
      <PageHeader
        title="Análise Mensal"
        description="Evolução semanal do período — barras e linha com escala dupla"
        actions={
          <ExportButton
            fileName="evolucao-mensal"
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
                  title: "Evolução semanal",
                  rows: buildWeeklyExportRows(buckets),
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
        <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          {Array.from({ length: 4 }).map((_, index) => (
            <Skeleton key={index} className="h-72 w-full rounded-card" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          <ComboChart
            title="Sell Out R$ × Positivação"
            barLabel="Sell Out R$"
            lineLabel="Positivação"
            data={buildSeries(buckets, (bucket) => bucket.totalValue, (bucket) => bucket.coverage)}
            formatBar={formatCompactCurrency}
            formatLine={formatInteger}
          />
          <ComboChart
            title="Sell Out R$ × Ticket Médio"
            barLabel="Sell Out R$"
            lineLabel="Ticket Médio"
            data={buildSeries(
              buckets,
              (bucket) => bucket.totalValue,
              (bucket) => safeDivide(bucket.totalValue, bucket.coverage) ?? 0,
            )}
            formatBar={formatCompactCurrency}
            formatLine={formatCurrency}
          />
          <ComboChart
            title="Sell Out R$ × Drop Size"
            barLabel="Sell Out R$"
            lineLabel="Drop Size"
            data={buildSeries(
              buckets,
              (bucket) => bucket.totalValue,
              (bucket) => safeDivide(bucket.totalValue, bucket.orderCount) ?? 0,
            )}
            formatBar={formatCompactCurrency}
            formatLine={formatCurrency}
          />
          <ComboChart
            title="Sell Out Unidade × Preço Médio"
            barLabel="Sell Out Un"
            lineLabel="Preço Médio"
            data={buildSeries(
              buckets,
              (bucket) => bucket.totalQuantity,
              (bucket) => safeDivide(bucket.totalValue, bucket.totalQuantity) ?? 0,
            )}
            formatBar={formatInteger}
            formatLine={formatCurrency}
          />
        </div>
      )}
    </div>
  );
}
