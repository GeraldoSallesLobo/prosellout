"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { KpiBlockCard, KpiCard } from "@/components/ui/kpi-card";
import { KpiCardSkeleton } from "@/components/ui/skeleton";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { ExportButton } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { StatusAnalysisTable } from "@/components/reports/status-analysis-table";
import { ComparisonBarChart } from "@/components/charts/comparison-bar-chart";
import { ProbabilityGauge } from "@/components/charts/probability-gauge";
import { useReportFilters, toReportFilters } from "@/hooks/use-report-filters";
import { fetchStatusAnalysis, fetchStatusMtd } from "@/lib/data/reports";
import {
  formatCurrency,
  formatInteger,
  formatPercent,
} from "@/lib/format";
import type { StatusGroupBy } from "@/types/reports";

const GROUP_OPTIONS: { value: StatusGroupBy; label: string }[] = [
  { value: "seller", label: "Vendedores" },
  { value: "category", label: "Categorias" },
  { value: "channel", label: "Canais" },
];

const KPI_SKELETON_COUNT = 9;

export default function StatusMtdPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const [groupBy, setGroupBy] = useState<StatusGroupBy>("seller");

  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: report, isLoading: isReportLoading } = useQuery({
    queryKey: ["status-mtd", reportFilters],
    queryFn: () => fetchStatusMtd(reportFilters),
    enabled: isHydrated,
  });

  const { data: analysisRows = [], isLoading: isAnalysisLoading } = useQuery({
    queryKey: ["status-analysis", groupBy, reportFilters],
    queryFn: () => fetchStatusAnalysis(groupBy, reportFilters),
    enabled: isHydrated,
  });

  const chartData = useMemo(
    () =>
      analysisRows.map((row) => ({
        name: row.groupName,
        current: row.currentValue,
        target: row.targetValue,
        previous: row.previousValue,
      })),
    [analysisRows],
  );

  return (
    <div>
      <PageHeader
        title="Status Mês Até Data"
        description="KPIs do período vs. meta e período anterior"
        actions={
          <ExportButton
            fileName="status-mtd"
            getRows={() =>
              analysisRows.map((row) => ({
                grupo: row.groupName,
                sell_out_atual: row.currentValue,
                meta: row.targetValue,
                atual_x_meta: row.currentVsTarget,
                periodo_anterior: row.previousValue,
                cobertura: row.coverage,
                ticket_medio: row.avgTicket,
              }))
            }
          />
        }
      />

      <ReportFilterBar filters={filters} onChange={setFilters} />

      {isReportLoading || !report ? (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: KPI_SKELETON_COUNT }).map((_, index) => (
            <KpiCardSkeleton key={index} />
          ))}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4">
            <KpiBlockCard
              label="Sell Out R$"
              block={report.sellOutValue}
              formatValue={formatCurrency}
            />
            <KpiBlockCard
              label="Sell Out Un"
              block={report.sellOutQuantity}
              formatValue={formatInteger}
            />
            <KpiBlockCard
              label="Cobertura UN"
              block={report.coverage}
              formatValue={formatInteger}
            />
            <KpiBlockCard
              label="Ticket Médio R$"
              block={report.avgTicket}
              formatValue={formatCurrency}
            />
            <KpiBlockCard
              label="Drop Size"
              block={report.dropSize}
              formatValue={formatInteger}
            />
            <KpiBlockCard
              label="Preço Médio"
              block={report.avgPrice}
              formatValue={formatCurrency}
            />
            <KpiBlockCard
              label="Mark Up %"
              block={report.markupPct}
              formatValue={formatPercent}
            />
            <KpiBlockCard
              label="Margem %"
              block={report.marginPct}
              formatValue={formatPercent}
            />
            <KpiCard
              label="Tendência Sell Out R$"
              value={formatCurrency(report.trendValue.projected)}
              vsTarget={report.trendValue.projectedVsTarget}
              footer="Projeção linear até o fim do período"
            />
          </div>

          <div className="card mt-3 flex flex-wrap items-center justify-around gap-4 p-4">
            <ProbabilityGauge
              value={report.probabilityValue}
              label="Probabilidade Sell Out R$"
            />
            <ProbabilityGauge
              value={report.probabilityCoverage}
              label="Probabilidade Cobertura"
            />
            <ProbabilityGauge
              value={report.probabilityTicket}
              label="Probabilidade Ticket Médio"
            />
          </div>
        </>
      )}

      <div className="mt-6">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-sm font-bold uppercase tracking-wide text-text2">
            Análise por agrupamento
          </h2>
          <ToggleBadges options={GROUP_OPTIONS} value={groupBy} onChange={setGroupBy} />
        </div>
        <StatusAnalysisTable
          groupBy={groupBy}
          rows={analysisRows}
          isLoading={isAnalysisLoading}
          isCompact
        />
      </div>

      <div className="card mt-6 p-4">
        <h2 className="mb-3 text-sm font-bold uppercase tracking-wide text-text2">
          Sell Out R$ — Atual × Meta × Anterior
        </h2>
        <ComparisonBarChart data={chartData} />
      </div>
    </div>
  );
}
