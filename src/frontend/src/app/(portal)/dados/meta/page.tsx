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
import { DATA_PAGE_SIZE, fetchTargetRows } from "@/lib/data/consolidated";
import { formatCurrency, formatInteger, formatIsoDate } from "@/lib/format";
import { getCurrentMonthToDate } from "@/lib/periods";
import type { SearchState } from "@/lib/search";
import type { SortState } from "@/lib/sort";
import type { TargetRow } from "@/types/domain";

export default function TargetsPage() {
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
    queryKey: ["target-rows", page, pageSize, sort, search, filters],
    queryFn: () =>
      fetchTargetRows(
        { page, pageSize, sort, search },
        {
          start: filters.start || undefined,
          end: filters.end || undefined,
          distributorId: filters.distributorId || undefined,
        },
      ),
  });

  const columns: DataTableColumn<TargetRow>[] = [
    {
      key: "distributor",
      header: "Distribuidora",
      render: (row) => row.distributorName,
      searchable: true,
    },
    { key: "customer", header: "Cliente", render: (row) => row.customerName, searchable: true },
    { key: "ean", header: "EAN", render: (row) => row.ean, searchable: true },
    { key: "product", header: "Produto", render: (row) => row.productName, searchable: true },
    { key: "date", header: "Competência", render: (row) => formatIsoDate(row.targetDate) },
    { key: "quantity", header: "Volume", align: "right", render: (row) => formatInteger(row.quantity) },
    { key: "value", header: "Valor", align: "right", render: (row) => formatCurrency(row.grossValue) },
  ];

  return (
    <div>
      <PageHeader
        title="Meta Consolidada"
        description="Metas por cliente, produto e competência"
        actions={
          <>
            <ExportButton
              fileName="metas"
              getRows={() =>
                (data?.rows ?? []).map((row) => ({
                  distribuidora: row.distributorName,
                  cliente: row.customerName,
                  ean: row.ean,
                  produto: row.productName,
                  competencia: row.targetDate,
                  volume: row.quantity,
                  valor: row.grossValue,
                }))
              }
            />
            <AdminDeleteFilteredDataButton
              dataset="sales_targets"
              label="metas"
              scopeDescription="A exclusão remove todas as metas de Sell Out que correspondem ao período, distribuidora e busca atuais."
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
