"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { ExportButton, type ExportSection } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { StatusAnalysisTable } from "@/components/reports/status-analysis-table";
import {
  REPORT_QUERY_FRESHNESS,
  toReportFilters,
  useReportFilters,
} from "@/hooks/use-report-filters";
import { useFilterOptions } from "@/hooks/use-filter-options";
import { fetchStatusAnalysis } from "@/lib/data/reports";
import {
  buildReportFilterExportRows,
  buildStatusAnalysisExportRows,
} from "@/lib/report-export";
import type { StatusGroupBy } from "@/types/reports";

const GROUP_OPTIONS: { value: StatusGroupBy; label: string }[] = [
  { value: "seller", label: "Vendedores" },
  { value: "category", label: "Categorias" },
  { value: "channel", label: "Canais" },
];

const GROUP_LABELS = Object.fromEntries(
  GROUP_OPTIONS.map((option) => [option.value, option.label]),
) as Record<StatusGroupBy, string>;

export default function StatusAnalysisPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const [groupBy, setGroupBy] = useState<StatusGroupBy>("seller");

  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: filterOptions } = useFilterOptions();

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ["status-analysis-full", groupBy, reportFilters],
    queryFn: () => fetchStatusAnalysis(groupBy, reportFilters),
    enabled: isHydrated,
    ...REPORT_QUERY_FRESHNESS,
  });

  return (
    <div>
      <PageHeader
        title="Análise Detalhada"
        description="Vendas, categorias e canais em uma única tela — alterne o agrupamento"
        actions={
          <ExportButton
            fileName={`analise-status-${groupBy}`}
            getSections={() => {
              const sections: ExportSection[] = [
                {
                  title: "Filtros",
                  rows: [
                    ...buildReportFilterExportRows(filters, filterOptions),
                    { Filtro: "Agrupamento", Valor: GROUP_LABELS[groupBy] },
                  ],
                },
                {
                  title: "Análise por agrupamento",
                  rows: buildStatusAnalysisExportRows(rows),
                },
              ];

              return sections;
            }}
          />
        }
      />

      <ReportFilterBar filters={filters} onChange={setFilters} />

      <div className="mb-3 flex justify-end">
        <ToggleBadges options={GROUP_OPTIONS} value={groupBy} onChange={setGroupBy} />
      </div>

      <StatusAnalysisTable groupBy={groupBy} rows={rows} isLoading={isLoading} />
    </div>
  );
}
