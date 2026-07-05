"use client";

import clsx from "clsx";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { TargetBadge } from "@/components/ui/badge";
import {
  formatCurrency,
  formatInteger,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import type { AnalysisRow, StatusGroupBy } from "@/types/reports";

const GROUP_HEADERS: Record<StatusGroupBy, string> = {
  seller: "Vendedor",
  category: "Categoria",
  channel: "Canal",
};

const TOTAL_ROW_ID = "__total__";

function VariationCell({ value }: { value: number | null }) {
  if (value === null) return <span className="text-text2">—</span>;
  return (
    <span className={clsx("font-semibold", value >= 0 ? "text-green" : "text-red")}>
      {formatVariation(value)}
    </span>
  );
}

function buildTotalRow(rows: AnalysisRow[]): AnalysisRow {
  const currentValue = rows.reduce((sum, row) => sum + row.currentValue, 0);
  const targetValue = rows.reduce((sum, row) => sum + (row.targetValue ?? 0), 0);
  const previousValue = rows.reduce((sum, row) => sum + row.previousValue, 0);
  const coverage = rows.reduce((sum, row) => sum + row.coverage, 0);
  return {
    groupId: TOTAL_ROW_ID,
    groupName: "TOTAL",
    currentValue,
    targetValue: targetValue || null,
    currentVsTarget: targetValue ? currentValue / targetValue - 1 : null,
    previousValue,
    previousVsTarget: targetValue ? previousValue / targetValue - 1 : null,
    coverage,
    avgTicket: coverage ? currentValue / coverage : null,
    dropSize: null,
    avgPrice: null,
    markupPct: null,
    marginPct: null,
  };
}

interface StatusAnalysisTableProps {
  groupBy: StatusGroupBy;
  rows: AnalysisRow[];
  isLoading: boolean;
  /** Compact mode (MTD footer): fewer columns, like the mockup. */
  isCompact?: boolean;
}

export function StatusAnalysisTable({
  groupBy,
  rows,
  isLoading,
  isCompact = false,
}: StatusAnalysisTableProps) {
  const compactColumns: DataTableColumn<AnalysisRow>[] = [
    {
      key: "name",
      header: GROUP_HEADERS[groupBy],
      render: (row) => row.groupName,
      sortValue: (row) => row.groupName,
    },
    {
      key: "current",
      header: "Sell Out R$",
      align: "right",
      render: (row) => formatCurrency(row.currentValue),
      sortValue: (row) => row.currentValue,
    },
    {
      key: "vsTarget",
      header: "vs. Meta",
      align: "right",
      render: (row) => <VariationCell value={row.currentVsTarget} />,
      sortValue: (row) => row.currentVsTarget,
    },
    {
      key: "coverage",
      header: "Cobertura",
      align: "right",
      render: (row) => `${formatInteger(row.coverage)} un`,
      sortValue: (row) => row.coverage,
    },
    {
      key: "ticket",
      header: "Ticket Médio",
      align: "right",
      render: (row) => formatCurrency(row.avgTicket),
      sortValue: (row) => row.avgTicket,
    },
    {
      key: "status",
      header: "Status",
      align: "center",
      render: (row) => <TargetBadge hasReachedTarget={(row.currentVsTarget ?? -1) >= 0} />,
      sortValue: (row) => row.currentVsTarget,
      searchable: false,
    },
  ];

  const fullColumns: DataTableColumn<AnalysisRow>[] = [
    {
      key: "name",
      header: GROUP_HEADERS[groupBy],
      render: (row) => row.groupName,
      sortValue: (row) => row.groupName,
    },
    {
      key: "current",
      header: "Sell Out R$ Atual",
      align: "right",
      render: (row) => formatCurrency(row.currentValue),
      sortValue: (row) => row.currentValue,
    },
    {
      key: "target",
      header: "Meta",
      align: "right",
      render: (row) => formatCurrency(row.targetValue),
      sortValue: (row) => row.targetValue,
    },
    {
      key: "vsTarget",
      header: "Atual × Meta",
      align: "right",
      render: (row) => <VariationCell value={row.currentVsTarget} />,
      sortValue: (row) => row.currentVsTarget,
    },
    {
      key: "previous",
      header: "Período Anterior",
      align: "right",
      render: (row) => formatCurrency(row.previousValue),
      sortValue: (row) => row.previousValue,
    },
    {
      key: "prevVsTarget",
      header: "Ant × Meta",
      align: "right",
      render: (row) => <VariationCell value={row.previousVsTarget} />,
      sortValue: (row) => row.previousVsTarget,
    },
    {
      key: "coverage",
      header: "Cobertura UN",
      align: "right",
      render: (row) => formatInteger(row.coverage),
      sortValue: (row) => row.coverage,
    },
    {
      key: "ticket",
      header: "Ticket Médio",
      align: "right",
      render: (row) => formatCurrency(row.avgTicket),
      sortValue: (row) => row.avgTicket,
    },
    {
      key: "dropSize",
      header: "Drop Size",
      align: "right",
      render: (row) => (row.dropSize === null ? "—" : formatInteger(row.dropSize)),
      sortValue: (row) => row.dropSize,
    },
    {
      key: "avgPrice",
      header: "Preço Médio",
      align: "right",
      render: (row) => formatCurrency(row.avgPrice),
      sortValue: (row) => row.avgPrice,
    },
    {
      key: "markup",
      header: "Mark Up %",
      align: "right",
      render: (row) => formatPercent(row.markupPct),
      sortValue: (row) => row.markupPct,
    },
    {
      key: "margin",
      header: "Margem %",
      align: "right",
      render: (row) => formatPercent(row.marginPct),
      sortValue: (row) => row.marginPct,
    },
  ];

  const rowsWithTotal = rows.length > 0 ? [...rows, buildTotalRow(rows)] : rows;

  return (
    <DataTable
      columns={isCompact ? compactColumns : fullColumns}
      rows={rowsWithTotal}
      rowKey={(row) => row.groupId}
      isLoading={isLoading}
      isFooterRow={(row) => row.groupId === TOTAL_ROW_ID}
    />
  );
}
