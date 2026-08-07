"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ExportButton } from "@/components/ui/export-button";
import { fetchAllPlannerPlanLines, fetchPlannerPlanLines } from "@/lib/data/planner";
import { formatCurrency, formatDecimal } from "@/lib/format";
import { formatPlanCode } from "@/lib/planner";
import type { PlannerPlanLine } from "@/types/planner";

const DEFAULT_PAGE_SIZE = 25;

const LINE_COLUMNS: DataTableColumn<PlannerPlanLine>[] = [
  {
    key: "week",
    header: "Semana",
    render: (row) => (row.weekNumber === null ? "—" : `Semana ${row.weekNumber}`),
    sortable: false,
  },
  { key: "ean", header: "EAN", render: (row) => row.ean, sortable: false },
  { key: "product", header: "Produto", render: (row) => row.productName, sortable: false },
  { key: "pdv", header: "Cód. PDV", render: (row) => row.pdvCode ?? "—", sortable: false },
  { key: "customer", header: "Cliente", render: (row) => row.customerName, sortable: false },
  { key: "seller", header: "Vendedor", render: (row) => row.salesRepName ?? "—", sortable: false },
  { key: "channel", header: "Canal", render: (row) => row.channelName ?? "—", sortable: false },
  {
    key: "quantity",
    header: "Volume",
    align: "right",
    render: (row) => (row.quantity === null ? "—" : formatDecimal(row.quantity)),
    sortable: false,
  },
  {
    key: "value",
    header: "Valor R$",
    align: "right",
    render: (row) => (row.grossValue === null ? "—" : formatCurrency(row.grossValue)),
    sortable: false,
  },
];

interface PlanResultSectionProps {
  planId: string;
  planCode: number;
  /** Parameters echoed in the export, per the "show the filters used" rule. */
  exportParams: Record<string, unknown>;
  exportFileName: string;
}

/** Generated plan lines: paginated grid + full CSV export with parameters. */
export function PlanResultSection({
  planId,
  planCode,
  exportParams,
  exportFileName,
}: PlanResultSectionProps) {
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(DEFAULT_PAGE_SIZE);

  const { data, isLoading } = useQuery({
    queryKey: ["planner-plan-lines", planId, page, pageSize],
    queryFn: () => fetchPlannerPlanLines(planId, pageSize, (page - 1) * pageSize),
  });

  const { data: allLines } = useQuery({
    queryKey: ["planner-plan-all-lines", planId],
    queryFn: () => fetchAllPlannerPlanLines(planId),
  });

  function buildExportSections() {
    return [
      {
        title: `Planificador ${formatPlanCode(planCode)}`,
        rows: [exportParams],
      },
      {
        title: "Linhas do plano",
        rows: (allLines ?? []).map((line) => ({
          Semana: line.weekNumber === null ? "" : `Semana ${line.weekNumber}`,
          EAN: line.ean,
          Produto: line.productName,
          "Cód. PDV": line.pdvCode ?? "",
          Cliente: line.customerName,
          Vendedor: line.salesRepName ?? "",
          Canal: line.channelName ?? "",
          Volume: line.quantity ?? "",
          "Valor R$": line.grossValue ?? "",
        })),
      },
    ];
  }

  // Strict layout from Planificador.xlsx, without extra columns, so the file
  // imports cleanly into the distributor's routing system.
  function buildRoutingExportRows() {
    const hasWeeks = (allLines ?? []).some((line) => line.weekNumber !== null);
    return (allLines ?? []).map((line) => {
      const base = {
        "CNPJ Distribuidor": line.distributorCnpj ?? "",
        EAN: line.ean,
        "Cód. PDV": line.pdvCode ?? "",
      };
      return hasWeeks
        ? { ...base, Semana: line.weekNumber ?? "", Volume: line.quantity ?? "" }
        : { ...base, "Volume / R$": line.quantity ?? line.grossValue ?? "" };
    });
  }

  return (
    <div className="grid gap-3">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-bold text-text1">
          Linhas do planificador {formatPlanCode(planCode)}
        </h2>
        {allLines ? (
          <div className="flex flex-wrap gap-2">
            <ExportButton
              fileName={`${exportFileName}-roteirizacao`}
              getRows={buildRoutingExportRows}
              label="Exportar p/ roteirização"
            />
            <ExportButton
              fileName={exportFileName}
              getSections={buildExportSections}
              label="Exportar detalhado"
            />
          </div>
        ) : (
          <Button variant="secondary" disabled>
            <Download size={14} />
            Preparando exportação...
          </Button>
        )}
      </div>
      <DataTable
        columns={LINE_COLUMNS}
        rows={data?.rows ?? []}
        rowKey={(row) => row.lineId}
        isLoading={isLoading}
        emptyMessage="Nenhuma linha gerada"
        pagination={{
          page,
          pageSize,
          total: data?.total ?? 0,
          onPageChange: setPage,
          onPageSizeChange: (size) => {
            setPageSize(size);
            setPage(1);
          },
        }}
      />
    </div>
  );
}
