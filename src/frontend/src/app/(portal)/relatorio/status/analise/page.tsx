"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { ExportButton } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { StatusAnalysisTable } from "@/components/reports/status-analysis-table";
import { useReportFilters, toReportFilters } from "@/hooks/use-report-filters";
import { fetchStatusAnalysis } from "@/lib/data/reports";
import type { StatusGroupBy } from "@/types/reports";

const GROUP_OPTIONS: { value: StatusGroupBy; label: string }[] = [
  { value: "seller", label: "Vendedores" },
  { value: "category", label: "Categorias" },
  { value: "channel", label: "Canais" },
];

export default function StatusAnalysisPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const [groupBy, setGroupBy] = useState<StatusGroupBy>("seller");

  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ["status-analysis-full", groupBy, reportFilters],
    queryFn: () => fetchStatusAnalysis(groupBy, reportFilters),
    enabled: isHydrated,
  });

  return (
    <div>
      <PageHeader
        title="Análise Consolidada"
        description="Vendas, categorias e canais em uma única tela — alterne o agrupamento"
        actions={
          <ExportButton
            fileName={`analise-status-${groupBy}`}
            getRows={() =>
              rows.map((row) => ({
                grupo: row.groupName,
                sell_out_atual: row.currentValue,
                meta: row.targetValue,
                atual_x_meta: row.currentVsTarget,
                periodo_anterior: row.previousValue,
                anterior_x_meta: row.previousVsTarget,
                cobertura_un: row.coverage,
                ticket_medio: row.avgTicket,
                drop_size: row.dropSize,
                preco_medio: row.avgPrice,
                mark_up_pct: row.markupPct,
                margem_pct: row.marginPct,
              }))
            }
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
