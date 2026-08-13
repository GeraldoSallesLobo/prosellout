"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { KpiBlockCard, KpiCard } from "@/components/ui/kpi-card";
import { KpiCardSkeleton } from "@/components/ui/skeleton";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { ExportButton, type ExportSection } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { StatusAnalysisTable } from "@/components/reports/status-analysis-table";
import { ComparisonBarChart } from "@/components/charts/comparison-bar-chart";
import { ProbabilityGauge } from "@/components/charts/probability-gauge";
import {
  REPORT_QUERY_FRESHNESS,
  toReportFilters,
  useReportFilters,
} from "@/hooks/use-report-filters";
import { fetchFilterOptions, fetchStatusAnalysis, fetchStatusMtd } from "@/lib/data/reports";
import {
  formatCurrency,
  formatDecimal,
  formatInteger,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import {
  buildReportFilterExportRows,
  buildStatusAnalysisExportRows,
} from "@/lib/report-export";
import type { AnalysisRow, KpiBlock, StatusGroupBy, StatusMtdReport } from "@/types/reports";

const GROUP_OPTIONS: { value: StatusGroupBy; label: string }[] = [
  { value: "seller", label: "Vendedores" },
  { value: "category", label: "Categorias" },
  { value: "channel", label: "Canais" },
];

const KPI_GRID_CLASS_NAME =
  "grid grid-cols-[repeat(auto-fit,minmax(min(100%,13.5rem),1fr))] gap-3";

const KPI_SKELETON_COUNT = 11;

function getCurrentVsPrevious(block: KpiBlock): number | null {
  return block.current !== null && block.previous !== null && block.previous !== 0
    ? block.current / block.previous - 1
    : null;
}

function buildKpiExportRow(
  indicator: string,
  block: KpiBlock,
  formatValue: (value: number | null) => string,
): Record<string, string> {
  return {
    Indicador: indicator,
    Atual: formatValue(block.current),
    Meta: formatValue(block.target),
    "Vs Meta": formatVariation(block.currentVsTarget),
    "Ano anterior": formatValue(block.previous),
    "Vs Ano anterior": formatVariation(getCurrentVsPrevious(block)),
  };
}

function buildStatusMtdKpiExportRows(report: StatusMtdReport): Record<string, string>[] {
  return [
    buildKpiExportRow("Sell Out R$", report.sellOutValue, formatCurrency),
    buildKpiExportRow("Sell Out Un", report.sellOutQuantity, formatInteger),
    buildKpiExportRow("Cobertura UN", report.coverage, formatInteger),
    buildKpiExportRow("Ticket Médio R$", report.avgTicket, formatCurrency),
    buildKpiExportRow("Drop Size", report.dropSize, formatCurrency),
    buildKpiExportRow("Preço Médio", report.avgPrice, formatCurrency),
    buildKpiExportRow("Mark Up %", report.markupPct, formatPercent),
    buildKpiExportRow("Margem %", report.marginPct, formatPercent),
    buildKpiExportRow("Giro Médio", report.avgTurnover, formatDecimal),
    buildKpiExportRow("Cobertura Média", report.avgCoverage, formatDecimal),
    {
      Indicador: "Tendência Sell Out R$",
      Atual: formatCurrency(report.trendValue.projected),
      Meta: "",
      "Vs Meta": formatVariation(report.trendValue.projectedVsTarget),
      "Ano anterior": "",
      "Vs Ano anterior": "",
    },
  ];
}

export default function StatusMtdPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const [groupBy, setGroupBy] = useState<StatusGroupBy>("seller");

  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: filterOptions } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
    enabled: isHydrated,
  });

  const { data: report, isLoading: isReportLoading } = useQuery({
    queryKey: ["status-mtd", reportFilters],
    queryFn: () => fetchStatusMtd(reportFilters),
    enabled: isHydrated,
    ...REPORT_QUERY_FRESHNESS,
  });

  const { data: analysisRows = [], isLoading: isAnalysisLoading } = useQuery({
    queryKey: ["status-analysis", groupBy, reportFilters],
    queryFn: () => fetchStatusAnalysis(groupBy, reportFilters),
    enabled: isHydrated,
    ...REPORT_QUERY_FRESHNESS,
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

  const totalRow = useMemo<AnalysisRow | undefined>(() => {
    if (!report) return undefined;

    return {
      groupId: "__total__",
      groupName: "TOTAL",
      currentValue: report.sellOutValue.current ?? 0,
      targetValue: report.sellOutValue.target,
      currentVsTarget: report.sellOutValue.currentVsTarget,
      previousValue: report.sellOutValue.previous ?? 0,
      previousVsTarget: report.sellOutValue.previousVsTarget,
      coverage: report.coverage.current ?? 0,
      avgTicket: report.avgTicket.current,
      dropSize: report.dropSize.current,
      avgPrice: report.avgPrice.current,
      markupPct: report.markupPct.current,
      marginPct: report.marginPct.current,
      avgTurnover: report.avgTurnover.current,
      avgCoverage: report.avgCoverage.current,
    };
  }, [report]);

  return (
    <div>
      <PageHeader
        title="Status Mês Até Data"
        description="KPIs do período vs. meta e período anterior"
        actions={
          <ExportButton
            fileName="status-mtd"
            getSections={() => {
              const sections: ExportSection[] = [
                {
                  title: "Filtros",
                  rows: buildReportFilterExportRows(filters, filterOptions),
                },
              ];

              if (report) {
                sections.push({
                  title: "Indicadores",
                  rows: buildStatusMtdKpiExportRows(report),
                });
              }

              sections.push({
                title: "Análise por agrupamento",
                rows: buildStatusAnalysisExportRows(analysisRows),
              });

              return sections;
            }}
          />
        }
      />

      <ReportFilterBar filters={filters} onChange={setFilters} />

      {isReportLoading || !report ? (
        <div className={KPI_GRID_CLASS_NAME}>
          {Array.from({ length: KPI_SKELETON_COUNT }).map((_, index) => (
            <KpiCardSkeleton key={index} />
          ))}
        </div>
      ) : (
        <>
          <div className={KPI_GRID_CLASS_NAME}>
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
              formatValue={formatCurrency}
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
            <KpiBlockCard
              label="Giro Médio"
              block={report.avgTurnover}
              formatValue={formatDecimal}
            />
            <KpiBlockCard
              label="Cobertura Média"
              block={report.avgCoverage}
              formatValue={formatDecimal}
            />
            <KpiCard
              label="Tendência Sell Out R$"
              value={formatCurrency(report.trendValue.projected)}
              vsTarget={report.trendValue.projectedVsTarget}
              footer="Projeção pela meta até a data"
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
          totalRow={totalRow}
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
