"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { SelectField } from "@/components/ui/field";
import { MultiSelectField } from "@/components/ui/multi-select-field";
import { StatusBadge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ExportButton } from "@/components/ui/export-button";
import { DATA_PAGE_SIZE, fetchCustomers } from "@/lib/data/consolidated";
import { fetchFilterOptions } from "@/lib/data/reports";
import { formatCnpj } from "@/lib/format";
import type { SearchState } from "@/lib/search";
import type { SortState } from "@/lib/sort";
import type { Customer } from "@/types/domain";

export default function CustomersPage() {
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(DATA_PAGE_SIZE);
  const [sort, setSort] = useState<SortState | null>(null);
  const [search, setSearch] = useState<SearchState | null>(null);
  const [channelIds, setChannelIds] = useState<string[]>([]);
  const [clusterId, setClusterId] = useState("");

  const { data: options } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  const { data, isLoading } = useQuery({
    queryKey: ["customers", page, pageSize, sort, search, channelIds, clusterId],
    queryFn: () =>
      fetchCustomers(
        { page, pageSize, sort, search },
        {
          channelIds: channelIds.length > 0 ? channelIds : undefined,
          clusterId: clusterId || undefined,
        },
      ),
  });

  const columns: DataTableColumn<Customer>[] = [
    { key: "cnpj", header: "CNPJ", render: (row) => formatCnpj(row.cnpj), searchable: true },
    { key: "name", header: "Razão Social", render: (row) => row.legalName, searchable: true },
    { key: "district", header: "Bairro", render: (row) => row.district ?? "—", searchable: true },
    { key: "city", header: "Cidade", render: (row) => row.city ?? "—", searchable: true },
    { key: "state", header: "UF", render: (row) => row.state ?? "—", searchable: true },
    { key: "zip", header: "CEP", render: (row) => row.zipCode ?? "—", searchable: true },
    { key: "channel", header: "Canal", render: (row) => row.channelName ?? "—", searchable: true },
    { key: "cluster", header: "Cluster", render: (row) => row.clusterName ?? "—", searchable: true },
    {
      key: "status",
      header: "Status",
      align: "center",
      render: (row) => <StatusBadge isActive={row.status === "active"} />,
    },
  ];

  return (
    <div>
      <PageHeader
        title="Clientes Consolidado"
        description="Base de clientes com canal e cluster"
        actions={
          <ExportButton
            fileName="clientes"
            getRows={() =>
              (data?.rows ?? []).map((row) => ({
                cnpj: row.cnpj,
                razao_social: row.legalName,
                bairro: row.district,
                cidade: row.city,
                uf: row.state,
                cep: row.zipCode,
                canal: row.channelName,
                cluster: row.clusterName,
              }))
            }
          />
        }
      />

      <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
        <MultiSelectField
          label="Canal"
          options={(options?.channels ?? []).map((option) => ({
            value: option.id,
            label: option.name,
          }))}
          values={channelIds}
          onChange={(next) => {
            setChannelIds(next);
            setPage(1);
          }}
        />
        <SelectField
          label="Cluster"
          options={(options?.clusters ?? []).map((option) => ({
            value: option.id,
            label: option.name,
          }))}
          value={clusterId}
          onChange={(event) => {
            setClusterId(event.target.value);
            setPage(1);
          }}
        />
      </div>

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
