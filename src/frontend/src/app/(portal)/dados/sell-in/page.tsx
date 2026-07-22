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
import { ExportButton } from "@/components/ui/export-button";
import {
  PeriodFilterBar,
  type PeriodFilterState,
} from "@/components/data/period-filter-bar";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { DATA_PAGE_SIZE, fetchSellInRows } from "@/lib/data/consolidated";
import { formatCurrency, formatInteger, formatIsoDate } from "@/lib/format";
import { getCurrentMonthToDate } from "@/lib/periods";
import type { SearchState } from "@/lib/search";
import type { SortState } from "@/lib/sort";
import type { SellInRow } from "@/types/domain";

export default function SellInPage() {
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

  const { data, isLoading } = useQuery({
    queryKey: ["sell-in-rows", page, pageSize, sort, search, filters],
    queryFn: () =>
      fetchSellInRows(
        { page, pageSize, sort, search },
        {
          start: filters.start || undefined,
          end: filters.end || undefined,
          distributorId: filters.distributorId || undefined,
        },
      ),
  });

  const columns: DataTableColumn<SellInRow>[] = [
    {
      key: "distributor",
      header: "Distribuidora",
      render: (row) => row.distributorName,
      searchable: true,
    },
    { key: "ean", header: "EAN", render: (row) => row.ean, searchable: true },
    { key: "product", header: "Produto", render: (row) => row.productName, searchable: true },
    { key: "date", header: "Data Fat.", render: (row) => formatIsoDate(row.invoiceDate) },
    { key: "quantity", header: "Volume", align: "right", render: (row) => formatInteger(row.quantity) },
    { key: "value", header: "Valor", align: "right", render: (row) => formatCurrency(row.grossValue) },
  ];

  return (
    <div>
      <PageHeader
        title="Sell In Consolidado"
        description="Compras dos distribuidores junto à indústria"
        actions={
          <>
            <ExportButton
              fileName="sell-in"
              getRows={() =>
                (data?.rows ?? []).map((row) => ({
                  distribuidora: row.distributorName,
                  ean: row.ean,
                  produto: row.productName,
                  data_faturamento: row.invoiceDate,
                  volume: row.quantity,
                  valor: row.grossValue,
                }))
              }
            />
            <AdminDeleteFilteredDataButton
              dataset="sell_in"
              label="sell in"
              scopeDescription="A exclusão remove todos os lançamentos de Sell In que correspondem ao período, distribuidora e busca atuais."
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
