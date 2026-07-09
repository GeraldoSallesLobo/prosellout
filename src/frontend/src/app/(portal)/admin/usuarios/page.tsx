"use client";

import { useState } from "react";
import type { ReactElement } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Eye, EyeOff, UserPlus } from "lucide-react";
import { AdminOnly } from "@/components/access/access-gate";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { FieldWrapper, TextField } from "@/components/ui/field";
import { Modal } from "@/components/ui/modal";
import { PageHeader } from "@/components/ui/page-header";
import { useToast } from "@/components/ui/toast";
import {
  createDistributorUser,
  fetchDistributorUsers,
  type DistributorUser,
} from "@/lib/data/admin";

const CNPJ_DIGIT_COUNT = 14;
const CNPJ_DIGIT_LIMIT = 14;
const DISTRIBUTOR_CODE_PATTERN = /^[A-Z0-9_-]{3,32}$/;

const EMPTY_FORM = {
  email: "",
  password: "",
  distributorCode: "",
  distributorName: "",
  distributorCnpj: "",
  city: "",
  state: "",
};

function getDigits(value: string): string {
  return value.replace(/\D/g, "");
}

function formatCnpjInput(value: string): string {
  const digits = getDigits(value).slice(0, CNPJ_DIGIT_LIMIT);
  return digits
    .replace(/^(\d{2})(\d)/, "$1.$2")
    .replace(/^(\d{2})\.(\d{3})(\d)/, "$1.$2.$3")
    .replace(/\.(\d{3})(\d)/, ".$1/$2")
    .replace(/(\d{4})(\d)/, "$1-$2");
}

function formatDistributorCode(value: string): string {
  return value.toUpperCase().replace(/[^A-Z0-9_-]/g, "");
}

function AdminUsersContent(): ReactElement {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
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

  const cnpjDigits = getDigits(form.distributorCnpj);
  const hasValidCnpj = cnpjDigits.length === 0 || cnpjDigits.length === CNPJ_DIGIT_COUNT;
  const hasValidDistributorCode = DISTRIBUTOR_CODE_PATTERN.test(form.distributorCode);
  const canSubmit =
    form.email.trim().length > 0 &&
    form.password.length >= 6 &&
    hasValidDistributorCode &&
    hasValidCnpj &&
    form.distributorName.trim().length > 0;

  function handleCreateDistributorUser(): void {
    createMutation.mutate({
      ...form,
      distributorCode: form.distributorCode.trim().toUpperCase(),
      distributorCnpj: cnpjDigits,
    });
  }

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
              onClick={handleCreateDistributorUser}
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
          <FieldWrapper label="Senha">
            <div className="relative">
              <input
                className="input-base pr-10"
                type={isPasswordVisible ? "text" : "password"}
                value={form.password}
                onChange={(event) => setForm({ ...form, password: event.target.value })}
              />
              <button
                type="button"
                onClick={() => setIsPasswordVisible((current) => !current)}
                title={isPasswordVisible ? "Ocultar senha" : "Mostrar senha"}
                aria-label={isPasswordVisible ? "Ocultar senha" : "Mostrar senha"}
                className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
              >
                {isPasswordVisible ? <EyeOff size={15} /> : <Eye size={15} />}
              </button>
            </div>
          </FieldWrapper>
          <FieldWrapper label="Código">
            <input
              className="input-base"
              value={form.distributorCode}
              onChange={(event) =>
                setForm({
                  ...form,
                  distributorCode: formatDistributorCode(event.target.value),
                })
              }
              placeholder="DIST001"
              maxLength={32}
              aria-invalid={!hasValidDistributorCode && form.distributorCode.length > 0}
            />
          </FieldWrapper>
          <TextField
            label="CNPJ"
            value={form.distributorCnpj}
            onChange={(event) =>
              setForm({ ...form, distributorCnpj: formatCnpjInput(event.target.value) })
            }
            placeholder="00.000.000/0000-00"
            inputMode="numeric"
            aria-invalid={!hasValidCnpj}
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
