"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Ban, CheckCircle2, Plus } from "lucide-react";
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
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { setDistributorStatus } from "@/lib/data/admin";
import { formatCnpj } from "@/lib/format";
import type { Distributor } from "@/types/domain";

const STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "inactive", label: "Inativo" },
];

const EMPTY_FORM = { code: "", name: "", cnpj: "", city: "", state: "" };
const CONFIRMATION_TEXT_BY_STATUS = {
  active: "ATIVAR",
  inactive: "INATIVAR",
} as const;

export default function DistributorPage() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [distributorToUpdate, setDistributorToUpdate] = useState<Distributor | null>(null);
  const [confirmationText, setConfirmationText] = useState("");
  const [form, setForm] = useState(EMPTY_FORM);
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const isAdmin = access?.isAdmin === true;

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

  const nextDistributorStatus =
    distributorToUpdate?.status === "active" ? "inactive" : "active";
  const confirmationTextRequired = CONFIRMATION_TEXT_BY_STATUS[nextDistributorStatus];

  const statusMutation = useMutation({
    mutationFn: () =>
      distributorToUpdate
        ? setDistributorStatus(distributorToUpdate.id, nextDistributorStatus)
        : Promise.resolve(0),
    onSuccess: (affectedCount) => {
      const isActivating = nextDistributorStatus === "active";
      showToast(
        affectedCount > 0 ? "success" : "info",
        affectedCount > 0
          ? isActivating
            ? "Distribuidor ativado."
            : "Distribuidor inativado."
          : isActivating
            ? "Distribuidor já estava ativo."
            : "Distribuidor já estava inativo.",
      );
      setDistributorToUpdate(null);
      setConfirmationText("");
      queryClient.invalidateQueries({ queryKey: ["distributors"] });
      queryClient.invalidateQueries({ queryKey: ["filter-options"] });
      queryClient.invalidateQueries({ queryKey: CURRENT_USER_ACCESS_QUERY_KEY });
      queryClient.invalidateQueries({ queryKey: ["platform-deletion-logs"] });
    },
    onError: () => showToast("error", "Erro ao alterar status do distribuidor."),
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
    ...(isAdmin
      ? [
          {
            key: "actions",
            header: "",
            align: "right" as const,
            sortable: false,
            searchable: false,
            render: (row: Distributor) =>
              row.status === "active" ? (
                <Button variant="secondary" onClick={() => setDistributorToUpdate(row)}>
                  <Ban size={14} /> Inativar
                </Button>
              ) : (
                <Button variant="secondary" onClick={() => setDistributorToUpdate(row)}>
                  <CheckCircle2 size={14} /> Ativar
                </Button>
              ),
          },
        ]
      : []),
  ];

  function handleCloseStatusModal(): void {
    if (statusMutation.isPending) return;
    setDistributorToUpdate(null);
    setConfirmationText("");
  }

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

      <Modal
        title={nextDistributorStatus === "active" ? "Ativar Distribuidor" : "Inativar Distribuidor"}
        isOpen={Boolean(distributorToUpdate)}
        onClose={handleCloseStatusModal}
        footer={
          <>
            <Button
              variant="secondary"
              onClick={handleCloseStatusModal}
              disabled={statusMutation.isPending}
            >
              Cancelar
            </Button>
            <Button
              variant={nextDistributorStatus === "active" ? "primary" : "danger"}
              disabled={
                confirmationText !== confirmationTextRequired || statusMutation.isPending
              }
              onClick={() => statusMutation.mutate()}
            >
              {statusMutation.isPending
                ? nextDistributorStatus === "active"
                  ? "Ativando..."
                  : "Inativando..."
                : nextDistributorStatus === "active"
                  ? "Ativar distribuidor"
                  : "Inativar distribuidor"}
            </Button>
          </>
        }
      >
        <div className="space-y-3 text-sm text-text2">
          <p>
            Esta ação {nextDistributorStatus === "active" ? "ativa" : "inativa"}{" "}
            <strong className="text-text1">{distributorToUpdate?.code}</strong>
            {distributorToUpdate?.name ? ` - ${distributorToUpdate.name}` : ""}.
          </p>
          <p className="rounded-md border border-red/30 bg-red/5 px-3 py-2 text-red">
            {nextDistributorStatus === "active"
              ? "Os usuários vinculados voltam a acessar a plataforma. A ação fica registrada em Admin › Logs."
              : "Os usuários vinculados perdem acesso à plataforma. Os dados históricos não são apagados e a ação fica registrada em Admin › Logs."}
          </p>
          <label className="block">
            <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-text2">
              Digite {confirmationTextRequired} para confirmar
            </span>
            <input
              className="input-base"
              value={confirmationText}
              onChange={(event) => setConfirmationText(event.target.value.toUpperCase())}
              autoComplete="off"
            />
          </label>
        </div>
      </Modal>
    </div>
  );
}
