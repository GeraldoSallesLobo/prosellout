"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { AdminDeleteFilteredDataButton } from "@/components/data/admin-delete-filtered-data-button";
import { SelectField } from "@/components/ui/field";
import { StatusBadge } from "@/components/ui/badge";
import {
  DataTable,
  type DataTableColumn,
  type DataTableRowKey,
} from "@/components/ui/data-table";
import { ExportButton } from "@/components/ui/export-button";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { fetchSellersBySupervisor } from "@/lib/data/consolidated";
import { fetchFilterOptions } from "@/lib/data/reports";
import { matchesSearch, type SearchState } from "@/lib/search";
import type { SalesRep } from "@/types/domain";

export default function SellersPage() {
  const [supervisorId, setSupervisorId] = useState("");
  const [search, setSearch] = useState<SearchState | null>(null);
  const [selectedRowKeys, setSelectedRowKeys] = useState<Set<DataTableRowKey>>(new Set());

  const { data: options } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const isAdmin = access?.isAdmin === true;

  const { data: sellers = [], isLoading } = useQuery({
    queryKey: ["sellers", supervisorId],
    queryFn: () => fetchSellersBySupervisor(supervisorId || undefined),
  });

  const supervisorNameById = useMemo(
    () =>
      new Map(
        (options?.supervisors ?? []).map((supervisor) => [supervisor.id, supervisor.name]),
      ),
    [options?.supervisors],
  );

  const visibleSellers = useMemo(() => {
    if (!search) return sellers;
    return sellers.filter((seller) => {
      if (search.key === "name") return matchesSearch(seller.name, search.text);
      if (search.key === "supervisor") {
        return matchesSearch(
          seller.supervisorId ? supervisorNameById.get(seller.supervisorId) ?? null : null,
          search.text,
        );
      }
      return false;
    });
  }, [search, sellers, supervisorNameById]);

  const columns: DataTableColumn<SalesRep>[] = [
    {
      key: "name",
      header: "Vendedor",
      render: (row) => row.name,
      sortValue: (row) => row.name,
      searchable: true,
    },
    {
      key: "supervisor",
      header: "Supervisor",
      render: (row) =>
        row.supervisorId ? supervisorNameById.get(row.supervisorId) ?? "—" : "—",
      sortValue: (row) =>
        row.supervisorId ? supervisorNameById.get(row.supervisorId) ?? null : null,
      searchable: true,
    },
    {
      key: "status",
      header: "Status",
      align: "center",
      render: (row) => <StatusBadge isActive={row.status === "active"} />,
      sortValue: (row) => row.status,
      searchable: false,
    },
  ];

  return (
    <div>
      <PageHeader
        title="Vendedores Consolidado"
        description="Vendedores vinculados à hierarquia comercial"
        actions={
          <>
            <ExportButton
              fileName="vendedores"
              getRows={() =>
                visibleSellers.map((row) => ({
                  vendedor: row.name,
                  supervisor: row.supervisorId
                    ? supervisorNameById.get(row.supervisorId)
                    : null,
                  status: row.status,
                }))
              }
            />
            <AdminDeleteFilteredDataButton
              dataset="sales_reps"
              label="vendedores"
              scopeDescription="A exclusão remove os vendedores filtrados e limpa o vínculo deles em clientes, Sell Out e metas."
              filters={{ supervisorId: supervisorId || undefined }}
              selectedRowIds={Array.from(selectedRowKeys)}
              search={search}
              onDeleted={() => setSelectedRowKeys(new Set())}
            />
          </>
        }
      />

      <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
        <SelectField
          label="Supervisor"
          options={(options?.supervisors ?? []).map((supervisor) => ({
            value: supervisor.id,
            label: supervisor.name,
          }))}
          value={supervisorId}
          onChange={(event) => {
            setSupervisorId(event.target.value);
            setSearch(null);
            setSelectedRowKeys(new Set());
          }}
        />
      </div>

      <DataTable
        columns={columns}
        rows={visibleSellers}
        rowKey={(row) => row.id}
        isLoading={isLoading}
        search={search}
        onSearchChange={(next) => {
          setSearch(next);
          setSelectedRowKeys(new Set());
        }}
        rowSelection={
          isAdmin
            ? {
                selectedKeys: selectedRowKeys,
                onSelectedKeysChange: setSelectedRowKeys,
              }
            : undefined
        }
      />
    </div>
  );
}
