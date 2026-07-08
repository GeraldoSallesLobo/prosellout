"use client";

import { useState } from "react";
import type { ReactElement } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { UserPlus } from "lucide-react";
import { AdminOnly } from "@/components/access/access-gate";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { TextField } from "@/components/ui/field";
import { Modal } from "@/components/ui/modal";
import { PageHeader } from "@/components/ui/page-header";
import { useToast } from "@/components/ui/toast";
import {
  createDistributorUser,
  fetchDistributorUsers,
  type DistributorUser,
} from "@/lib/data/admin";

const DEFAULT_PASSWORD = "123321";

const EMPTY_FORM = {
  email: "",
  password: DEFAULT_PASSWORD,
  distributorCode: "",
  distributorName: "",
  distributorCnpj: "",
  city: "",
  state: "",
};

function AdminUsersContent(): ReactElement {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: users = [], isLoading } = useQuery({
    queryKey: ["distributor-users"],
    queryFn: fetchDistributorUsers,
  });

  const createMutation = useMutation({
    mutationFn: createDistributorUser,
    onSuccess: () => {
      showToast("success", "Usuário e distribuidor cadastrados com sucesso.");
      setIsModalOpen(false);
      setForm(EMPTY_FORM);
      queryClient.invalidateQueries({ queryKey: ["distributor-users"] });
      queryClient.invalidateQueries({ queryKey: ["distributors"] });
    },
    onError: () => showToast("error", "Erro ao cadastrar usuário distribuidor."),
  });

  const canSubmit =
    form.email.trim().length > 0 &&
    form.password.length >= 6 &&
    form.distributorCode.trim().length > 0 &&
    form.distributorName.trim().length > 0;

  const columns: DataTableColumn<DistributorUser>[] = [
    {
      key: "email",
      header: "Usuário",
      render: (row) => row.email,
      sortValue: (row) => row.email,
    },
    {
      key: "distributor",
      header: "Distribuidor",
      render: (row) => row.distributorName,
      sortValue: (row) => row.distributorName,
    },
    {
      key: "code",
      header: "Código",
      render: (row) => <Badge variant="blue">{row.distributorCode}</Badge>,
      sortValue: (row) => row.distributorCode,
    },
    {
      key: "status",
      header: "Status",
      align: "center",
      render: (row) => <StatusBadge isActive={row.status === "active"} />,
      sortValue: (row) => row.status,
      searchable: false,
    },
    {
      key: "created",
      header: "Criado em",
      render: (row) => new Date(row.createdAt).toLocaleDateString("pt-BR"),
      sortValue: (row) => row.createdAt,
    },
  ];

  return (
    <div>
      <PageHeader
        title="Usuários"
        description="Criação de usuários distribuidores com vínculo automático"
        actions={
          <Button onClick={() => setIsModalOpen(true)}>
            <UserPlus size={14} /> Novo usuário
          </Button>
        }
      />

      <DataTable columns={columns} rows={users} rowKey={(row) => row.userId} isLoading={isLoading} />

      <Modal
        title="Cadastrar usuário distribuidor"
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
            label="E-mail"
            type="email"
            wrapperClassName="col-span-2"
            value={form.email}
            onChange={(event) => setForm({ ...form, email: event.target.value })}
            placeholder="distribuidora.exemplo@email.com"
          />
          <TextField
            label="Senha"
            type="password"
            value={form.password}
            onChange={(event) => setForm({ ...form, password: event.target.value })}
          />
          <TextField
            label="Código"
            value={form.distributorCode}
            onChange={(event) => setForm({ ...form, distributorCode: event.target.value })}
            placeholder="DIST001"
          />
          <TextField
            label="CNPJ"
            value={form.distributorCnpj}
            onChange={(event) => setForm({ ...form, distributorCnpj: event.target.value })}
            placeholder="00.000.000/0000-00"
          />
          <TextField
            label="Distribuidor"
            value={form.distributorName}
            onChange={(event) => setForm({ ...form, distributorName: event.target.value })}
            placeholder="Razão social"
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

export default function AdminUsersPage(): ReactElement {
  return (
    <AdminOnly>
      <AdminUsersContent />
    </AdminOnly>
  );
}
