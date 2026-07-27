"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { AdminDeleteFilteredDataButton } from "@/components/data/admin-delete-filtered-data-button";
import {
  DataTable,
  type DataTableColumn,
  type DataTableRowKey,
} from "@/components/ui/data-table";
import { ExportButton, type ExportSection } from "@/components/ui/export-button";
import {
  PeriodFilterBar,
  type PeriodFilterState,
} from "@/components/data/period-filter-bar";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { DATA_PAGE_SIZE, fetchSellOutRows } from "@/lib/data/consolidated";
import { fetchFilterOptions } from "@/lib/data/reports";
import { formatCurrency, formatInteger, formatIsoDate } from "@/lib/format";
import { getCurrentMonthToDate } from "@/lib/periods";
import {
  buildDataExportContextRows,
  buildPeriodFilterExportRows,
} from "@/lib/report-export";
import type { SearchState } from "@/lib/search";
import type { SortState } from "@/lib/sort";
import type { SellOutRow } from "@/types/domain";

const SEARCH_LABELS: Record<string, string> = {
  distributor: "Distribuidora",
  customer: "Cliente",
  ean: "EAN",
  product: "Produto",
};

export default function SellOutPage() {
  const initialPeriod = getCurrentMonthToDate();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(DATA_PAGE_SIZE);
  const [sort, setSort] = useState<SortState | null>(null);
  const [search, setSearch] = useState<SearchState | null>(null);
  const [selectedRowKeys, setSelectedRowKeys] = useState<Set<DataTableRowKey>>(new Set());
  const [filters, setFilters] = useState<PeriodFilterState>({
    start: initialPeriod.start,
    end: initialPeriod.end,
    distributorId: "",
  });
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const isAdmin = access?.isAdmin === true;
  const { data: filterOptions } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  const { data, isLoading } = useQuery({
    queryKey: ["sell-out-rows", page, pageSize, sort, search, filters],
    queryFn: () =>
      fetchSellOutRows(
        { page, pageSize, sort, search },
        {
          start: filters.start || undefined,
          end: filters.end || undefined,
          distributorId: filters.distributorId || undefined,
        },
      ),
  });

  const columns: DataTableColumn<SellOutRow>[] = [
    {
      key: "distributor",
      header: "Distribuidora",
      render: (row) => row.distributorName,
      searchable: true,
    },
    { key: "customer", header: "Cliente", render: (row) => row.customerName, searchable: true },
    { key: "ean", header: "EAN", render: (row) => row.ean, searchable: true },
    { key: "product", header: "Produto", render: (row) => row.productName, searchable: true },
    { key: "date", header: "Data Fat.", render: (row) => formatIsoDate(row.invoiceDate) },
    { key: "quantity", header: "Volume", align: "right", render: (row) => formatInteger(row.quantity) },
    { key: "value", header: "Valor", align: "right", render: (row) => formatCurrency(row.grossValue) },
  ];

  return (
    <div>
      <PageHeader
        title="Sell Out Consolidado"
        description="Vendas dos distribuidores para o varejo"
        actions={
          <>
            <ExportButton
              fileName="sell-out"
              getSections={() => {
                const sections: ExportSection[] = [
                  {
                    title: "Filtros",
                    rows: [
                      ...buildPeriodFilterExportRows(filters, filterOptions),
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
                    title: "Sell Out",
                    rows: (data?.rows ?? []).map((row) => ({
                      Distribuidora: row.distributorName,
                      Cliente: row.customerName,
                      EAN: row.ean,
                      Produto: row.productName,
                      "Data Fat.": formatIsoDate(row.invoiceDate),
                      Volume: formatInteger(row.quantity),
                      Valor: formatCurrency(row.grossValue),
                    })),
                  },
                ];

                return sections;
              }}
            />
            <AdminDeleteFilteredDataButton
              dataset="sell_out"
              label="sell out"
              scopeDescription="A exclusão remove todos os lançamentos de Sell Out que correspondem ao período, distribuidora e busca atuais."
              filters={{
                start: filters.start || undefined,
                end: filters.end || undefined,
                distributorId: filters.distributorId || undefined,
              }}
              selectedRowIds={Array.from(selectedRowKeys)}
              search={search}
              onDeleted={() => {
                setSelectedRowKeys(new Set());
                setPage(1);
              }}
            />
          </>
        }
      />

      <PeriodFilterBar
        filters={filters}
        onChange={(patch) => {
          setFilters((current) => ({ ...current, ...patch }));
          setSelectedRowKeys(new Set());
          setPage(1);
        }}
      />

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
          setSelectedRowKeys(new Set());
          setPage(1);
        }}
        rowSelection={
          isAdmin
            ? {
                selectedKeys: selectedRowKeys,
                onSelectedKeysChange: setSelectedRowKeys,
              }
            : undefined
        }
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
