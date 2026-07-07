"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { SelectField, TextField } from "@/components/ui/field";
import { StatusBadge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { useToast } from "@/components/ui/toast";
import {
  createDistributor,
  fetchDistributors,
  type StatusFilter,
} from "@/lib/data/master-data";
import { formatCnpj } from "@/lib/format";
import type { Distributor } from "@/types/domain";

const STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "inactive", label: "Inativo" },
];

const EMPTY_FORM = { code: "", name: "", cnpj: "", city: "", state: "" };

export default function DistributorPage() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: distributors = [], isLoading } = useQuery({
    queryKey: ["distributors", statusFilter],
    queryFn: () => fetchDistributors(statusFilter),
  });

  const createMutation = useMutation({
    mutationFn: createDistributor,
    onSuccess: () => {
      showToast("success", "Distribuidor cadastrado com sucesso.");
      setIsModalOpen(false);
      setForm(EMPTY_FORM);
      queryClient.invalidateQueries({ queryKey: ["distributors"] });
    },
    onError: () => showToast("error", "Erro ao cadastrar distribuidor."),
  });

  const canSubmit = form.code.trim().length > 0 && form.name.trim().length > 0;

  const columns: DataTableColumn<Distributor>[] = [
    { key: "code", header: "Código", render: (row) => row.code, sortValue: (row) => row.code },
    { key: "name", header: "Nome", render: (row) => row.name, sortValue: (row) => row.name },
    {
      key: "cnpj",
      header: "CNPJ",
      render: (row) => formatCnpj(row.cnpj),
      sortValue: (row) => row.cnpj,
    },
    {
      key: "location",
      header: "Cidade/UF",
      render: (row) => (row.city ? `${row.city}/${row.state ?? ""}` : "—"),
      sortValue: (row) => (row.city ? `${row.city}/${row.state ?? ""}` : null),
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
        title="Distribuidor"
        description="Distribuidores cadastrados na plataforma"
        actions={
          <Button onClick={() => setIsModalOpen(true)}>
            <Plus size={14} /> Incluir
          </Button>
        }
      />

      <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
        <SelectField
          label="Status"
          options={STATUS_OPTIONS}
          value={statusFilter === "all" ? "" : statusFilter}
          onChange={(event) =>
            setStatusFilter((event.target.value || "all") as StatusFilter)
          }
        />
      </div>

      <DataTable
        columns={columns}
        rows={distributors}
        rowKey={(row) => row.id}
        isLoading={isLoading}
      />

      <Modal
        title="Cadastrar Distribuidor"
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setIsModalOpen(false)}>
              Cancelar
            </Button>
            <Button
              disabled={!canSubmit || createMutation.isPending}
              onClick={() => createMutation.mutate(form)}
            >
              {createMutation.isPending ? "Salvando..." : "Salvar"}
            </Button>
          </>
        }
      >
        <div className="grid grid-cols-2 gap-3">
          <TextField
            label="Código"
            value={form.code}
            onChange={(event) => setForm({ ...form, code: event.target.value })}
            placeholder="DIST004"
          />
          <TextField
            label="CNPJ"
            value={form.cnpj}
            onChange={(event) => setForm({ ...form, cnpj: event.target.value })}
            placeholder="00.000.000/0000-00"
          />
          <TextField
            label="Nome"
            wrapperClassName="col-span-2"
            value={form.name}
            onChange={(event) => setForm({ ...form, name: event.target.value })}
            placeholder="Razão social do distribuidor"
          />
          <TextField
            label="Cidade"
            value={form.city}
            onChange={(event) => setForm({ ...form, city: event.target.value })}
          />
          <TextField
            label="UF"
            maxLength={2}
            value={form.state}
            onChange={(event) => setForm({ ...form, state: event.target.value.toUpperCase() })}
          />
        </div>
      </Modal>
    </div>
  );
}
