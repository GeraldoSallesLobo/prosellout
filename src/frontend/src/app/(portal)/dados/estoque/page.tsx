"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ExportButton, type ExportSection } from "@/components/ui/export-button";
import {
  PeriodFilterBar,
  type PeriodFilterState,
} from "@/components/data/period-filter-bar";
import { DATA_PAGE_SIZE, fetchStockRows } from "@/lib/data/consolidated";
import { fetchFilterOptions } from "@/lib/data/reports";
import { formatCurrency, formatInteger, formatIsoDate } from "@/lib/format";
import { getCurrentMonthToDate } from "@/lib/periods";
import {
  buildDataExportContextRows,
  buildPeriodFilterExportRows,
} from "@/lib/report-export";
import type { SearchState } from "@/lib/search";
import type { SortState } from "@/lib/sort";
import type { StockRow } from "@/types/domain";

const SEARCH_LABELS: Record<string, string> = {
  distributor: "Distribuidora",
  ean: "EAN",
  product: "Produto",
};

export default function StockPage() {
  const initialPeriod = getCurrentMonthToDate();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(DATA_PAGE_SIZE);
  const [sort, setSort] = useState<SortState | null>(null);
  const [search, setSearch] = useState<SearchState | null>(null);
  const [filters, setFilters] = useState<PeriodFilterState>({
    start: initialPeriod.start,
    end: initialPeriod.end,
    distributorId: "",
  });
  const { data: filterOptions } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  const { data, isLoading } = useQuery({
    queryKey: ["stock-rows", page, pageSize, sort, search, filters],
    queryFn: () =>
      fetchStockRows(
        { page, pageSize, sort, search },
        {
          start: filters.start || undefined,
          end: filters.end || undefined,
          distributorId: filters.distributorId || undefined,
        },
      ),
  });

  const columns: DataTableColumn<StockRow>[] = [
    {
      key: "distributor",
      header: "Distribuidora",
      render: (row) => row.distributorName,
      searchable: true,
    },
    { key: "ean", header: "EAN", render: (row) => row.ean, searchable: true },
    { key: "product", header: "Produto", render: (row) => row.productName, searchable: true },
    { key: "date", header: "Posição em", render: (row) => formatIsoDate(row.snapshotDate) },
    {
      key: "quantity",
      header: "Quantidade",
      align: "right",
      render: (row) => (
        <span className={row.quantity < 0 ? "font-semibold text-red" : undefined}>
          {formatInteger(row.quantity)}
        </span>
      ),
    },
    {
      key: "value",
      header: "Valor Sell In",
      align: "right",
      render: (row) => formatCurrency(row.grossValue),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Estoque Consolidado"
        description="Posição calculada por Sell In acumulado menos Sell Out acumulado"
        actions={
          <ExportButton
            fileName="estoque"
            getSections={() => {
              const sections: ExportSection[] = [
                {
                  title: "Filtros",
                  rows: [
                    ...buildPeriodFilterExportRows(filters, filterOptions, {
                      showStartDate: false,
                      endDateLabel: "Posição até",
                    }),
                    ...buildDataExportContextRows({
                      search,
                      searchLabels: SEARCH_LABELS,
                      page,
                      pageSize,
                      total: data?.total ?? 0,
                      exportedCount: data?.rows.length ?? 0,
                    }),
                  ],
                },
                {
                  title: "Estoque",
                  rows: (data?.rows ?? []).map((row) => ({
                    Distribuidora: row.distributorName,
                    EAN: row.ean,
                    Produto: row.productName,
                    "Posição em": formatIsoDate(row.snapshotDate),
                    Quantidade: formatInteger(row.quantity),
                    "Valor Sell In": formatCurrency(row.grossValue),
                  })),
                },
              ];

              return sections;
            }}
          />
        }
      />

      <PeriodFilterBar
        filters={filters}
        onChange={(patch) => {
          setFilters((current) => ({ ...current, ...patch }));
          setPage(1);
        }}
        showStartDate={false}
        endDateLabel="Posição até"
      />

      <p className="mb-3 text-xs text-text2">
        Quantidades negativas indicam Sell Out maior que o Sell In acumulado até a data de
        referência e devem ser tratadas como alerta de inconsistência nos dados.
      </p>

      <DataTable
        columns={columns}
        rows={data?.rows ?? []}
        rowKey={(row) => row.id}
        isLoading={isLoading}
        sort={sort}
        onSortChange={(next) => {
          setSort(next);
          setPage(1);
        }}
        search={search}
        onSearchChange={(next) => {
          setSearch(next);
          setPage(1);
        }}
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
