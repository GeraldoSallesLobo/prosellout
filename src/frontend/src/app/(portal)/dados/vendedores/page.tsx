"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/ui/page-header";
import { SelectField } from "@/components/ui/field";
import { StatusBadge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ExportButton } from "@/components/ui/export-button";
import { fetchSellersBySupervisor } from "@/lib/data/consolidated";
import { fetchFilterOptions } from "@/lib/data/reports";
import type { SalesRep } from "@/types/domain";

export default function SellersPage() {
  const [supervisorId, setSupervisorId] = useState("");

  const { data: options } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  const { data: sellers = [], isLoading } = useQuery({
    queryKey: ["sellers", supervisorId],
    queryFn: () => fetchSellersBySupervisor(supervisorId || undefined),
  });

  const supervisorNameById = new Map(
    (options?.supervisors ?? []).map((supervisor) => [supervisor.id, supervisor.name]),
  );

  const columns: DataTableColumn<SalesRep>[] = [
    { key: "name", header: "Vendedor", render: (row) => row.name, sortValue: (row) => row.name },
    {
      key: "supervisor",
      header: "Supervisor",
      render: (row) =>
        row.supervisorId ? supervisorNameById.get(row.supervisorId) ?? "—" : "—",
      sortValue: (row) =>
        row.supervisorId ? supervisorNameById.get(row.supervisorId) ?? null : null,
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
          <ExportButton
            fileName="vendedores"
            getRows={() =>
              sellers.map((row) => ({
                vendedor: row.name,
                supervisor: row.supervisorId
                  ? supervisorNameById.get(row.supervisorId)
                  : null,
                status: row.status,
              }))
            }
          />
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
          onChange={(event) => setSupervisorId(event.target.value)}
        />
      </div>

      <DataTable columns={columns} rows={sellers} rowKey={(row) => row.id} isLoading={isLoading} />
    </div>
  );
}
