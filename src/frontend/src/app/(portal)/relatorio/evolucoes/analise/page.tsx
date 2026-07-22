"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { PageHeader } from "@/components/ui/page-header";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { ExportButton } from "@/components/ui/export-button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import {
  REPORT_QUERY_FRESHNESS,
  toReportFilters,
  useReportFilters,
} from "@/hooks/use-report-filters";
import { fetchEvolutionAnalysis } from "@/lib/data/reports";
import { formatCurrency, formatInteger, formatVariation } from "@/lib/format";
import type { EvolutionAnalysisRow, EvolutionGroupBy } from "@/types/reports";

const GROUP_OPTIONS: { value: EvolutionGroupBy; label: string }[] = [
  { value: "category", label: "Categorias" },
  { value: "channel", label: "Canais" },
  { value: "customer", label: "Clientes" },
];

type MetricTab = "value" | "quantity" | "ticket";

const METRIC_TABS: { value: MetricTab; label: string }[] = [
  { value: "value", label: "Faturamento R$" },
  { value: "quantity", label: "Volume" },
  { value: "ticket", label: "Ticket Médio" },
];

const GROUP_HEADERS: Record<EvolutionGroupBy, string> = {
  category: "Categoria",
  channel: "Canal",
  customer: "Cliente",
};

interface MetricAccessors {
  current: (row: EvolutionAnalysisRow) => number | null;
  previous: (row: EvolutionAnalysisRow) => number | null;
  change: (row: EvolutionAnalysisRow) => number | null;
  format: (value: number | null) => string;
}

const METRIC_ACCESSORS: Record<MetricTab, MetricAccessors> = {
  value: {
    current: (row) => row.currentValue,
    previous: (row) => row.previousValue,
    change: (row) => row.valueChangePct,
    format: formatCurrency,
  },
  quantity: {
    current: (row) => row.currentQuantity,
    previous: (row) => row.previousQuantity,
    change: (row) => row.quantityChangePct,
    format: formatInteger,
  },
  ticket: {
    current: (row) => row.currentTicket,
    previous: (row) => row.previousTicket,
    change: (row) => row.ticketChangePct,
    format: formatCurrency,
  },
};

function ChangeCell({ value }: { value: number | null }) {
  if (value === null) return <span className="text-text2">—</span>;
  return (
    <span className={clsx("font-semibold", value >= 0 ? "text-green" : "text-red")}>
      {formatVariation(value)}
    </span>
  );
}

export default function EvolutionAnalysisPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const [groupBy, setGroupBy] = useState<EvolutionGroupBy>("category");
  const [metricTab, setMetricTab] = useState<MetricTab>("value");

  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ["evolution-analysis", groupBy, reportFilters],
    queryFn: () => fetchEvolutionAnalysis(groupBy, reportFilters),
    enabled: isHydrated,
    ...REPORT_QUERY_FRESHNESS,
  });

  const accessors = METRIC_ACCESSORS[metricTab];

  const columns: DataTableColumn<EvolutionAnalysisRow>[] = [
    {
      key: "name",
      header: GROUP_HEADERS[groupBy],
      render: (row) => row.groupName,
      sortValue: (row) => row.groupName,
    },
    {
      key: "current",
      header: "Período Atual",
      align: "right",
      render: (row) => accessors.format(accessors.current(row)),
      sortValue: (row) => accessors.current(row),
    },
    {
      key: "previous",
      header: "Período Anterior",
      align: "right",
      render: (row) => accessors.format(accessors.previous(row)),
      sortValue: (row) => accessors.previous(row),
    },
    {
      key: "change",
      header: "Variação",
      align: "right",
      render: (row) => <ChangeCell value={accessors.change(row)} />,
      sortValue: (row) => accessors.change(row),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Análise de Evolução"
        description="Comparativo Período Atual × Período Anterior por agrupamento"
        actions={
          <ExportButton
            fileName={`evolucao-${groupBy}-${metricTab}`}
            getRows={() =>
              rows.map((row) => ({
                grupo: row.groupName,
                atual: accessors.current(row),
                anterior: accessors.previous(row),
                variacao: accessors.change(row),
              }))
            }
          />
        }
      />

      <ReportFilterBar filters={filters} onChange={setFilters} showTargetPeriod={false} />

      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <div className="flex gap-1 rounded-lg border border-line bg-bg2 p-1">
          {METRIC_TABS.map((tab) => (
            <button
              key={tab.value}
              type="button"
              onClick={() => setMetricTab(tab.value)}
              className={clsx(
                "rounded-md px-3 py-1.5 text-[13px] font-semibold transition-colors",
                metricTab === tab.value
                  ? "bg-bg3 text-text1"
                  : "text-text2 hover:text-text1",
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>
        <ToggleBadges options={GROUP_OPTIONS} value={groupBy} onChange={setGroupBy} />
      </div>

      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(row) => row.groupId}
        isLoading={isLoading}
      />
    </div>
  );
}
