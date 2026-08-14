"use client";

import { useMemo, useState } from "react";
import type { ReactElement } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Eye, EyeOff, Settings2, UserPlus } from "lucide-react";
import { AdminOnly } from "@/components/access/access-gate";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { FieldWrapper, SelectField, TextField } from "@/components/ui/field";
import { Modal } from "@/components/ui/modal";
import { MultiSelectField } from "@/components/ui/multi-select-field";
import { PageHeader } from "@/components/ui/page-header";
import { useToast } from "@/components/ui/toast";
import {
  createPortalUser,
  fetchDistributorUsers,
  grantDistributorAccess,
  revokeDistributorAccess,
  type DistributorUser,
} from "@/lib/data/admin";
import { fetchDistributors } from "@/lib/data/master-data";
import { INDUSTRY_LABELS } from "@/lib/industry";

const MIN_PASSWORD_LENGTH = 6;

const EMPTY_FORM = {
  email: "",
  password: "",
  distributorIds: [] as string[],
};

/** One row per portal user, aggregating that user's industry links. */
interface PortalUserRow {
  userId: string;
  email: string;
  createdAt: string;
  links: DistributorUser[];
}

function groupUsersByEmail(links: DistributorUser[]): PortalUserRow[] {
  const rowsByUserId = new Map<string, PortalUserRow>();
  links.forEach((link) => {
    const row = rowsByUserId.get(link.userId);
    if (!row) {
      rowsByUserId.set(link.userId, {
        userId: link.userId,
        email: link.email,
        createdAt: link.createdAt,
        links: [link],
      });
      return;
    }
    row.links.push(link);
    if (link.createdAt < row.createdAt) row.createdAt = link.createdAt;
  });
  return Array.from(rowsByUserId.values());
}

function getActiveLinks(row: PortalUserRow): DistributorUser[] {
  return row.links.filter((link) => link.status === "active");
}

function AdminUsersContent(): ReactElement {
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
  const [managedUserId, setManagedUserId] = useState<string | null>(null);
  const [grantDistributorId, setGrantDistributorId] = useState("");
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: links = [], isLoading } = useQuery({
    queryKey: ["distributor-users"],
    queryFn: fetchDistributorUsers,
  });

  const { data: distributors = [] } = useQuery({
    queryKey: ["distributors", "active"],
    queryFn: () => fetchDistributors("active"),
  });

  const users = useMemo(() => groupUsersByEmail(links), [links]);
  const managedUser = users.find((row) => row.userId === managedUserId) ?? null;

  function invalidateUsers(): void {
    queryClient.invalidateQueries({ queryKey: ["distributor-users"] });
  }

  const createMutation = useMutation({
    mutationFn: createPortalUser,
    onSuccess: () => {
      showToast("success", "Usuário cadastrado com sucesso.");
      setIsCreateModalOpen(false);
      setForm(EMPTY_FORM);
      invalidateUsers();
    },
    onError: () => showToast("error", "Erro ao cadastrar usuário."),
  });

  const grantMutation = useMutation({
    mutationFn: ({ userId, distributorId }: { userId: string; distributorId: string }) =>
      grantDistributorAccess(userId, distributorId),
    onSuccess: () => {
      showToast("success", "Acesso liberado.");
      setGrantDistributorId("");
      invalidateUsers();
    },
    onError: () => showToast("error", "Erro ao liberar acesso."),
  });

  const revokeMutation = useMutation({
    mutationFn: ({ userId, distributorId }: { userId: string; distributorId: string }) =>
      revokeDistributorAccess(userId, distributorId),
    onSuccess: () => {
      showToast("success", "Acesso revogado.");
      invalidateUsers();
    },
    onError: () => showToast("error", "Erro ao revogar acesso."),
  });

  const canSubmitCreate =
    form.email.trim().length > 0 &&
    form.password.length >= MIN_PASSWORD_LENGTH &&
    form.distributorIds.length > 0;

  const managedActiveLinkIds = new Set(
    (managedUser ? getActiveLinks(managedUser) : []).map((link) => link.distributorId),
  );
  const grantableDistributors = distributors.filter(
    (distributor) => !managedActiveLinkIds.has(distributor.id),
  );

  const columns: DataTableColumn<PortalUserRow>[] = [
    {
      key: "email",
      header: "Usuário",
      render: (row) => row.email,
      sortValue: (row) => row.email,
    },
    {
      key: "industries",
      header: INDUSTRY_LABELS.switcherLabel + "s",
      render: (row) => {
        const activeLinks = getActiveLinks(row);
        if (activeLinks.length === 0) {
          return <span className="text-text2">Sem acesso</span>;
        }
        return (
          <span className="flex flex-wrap gap-1">
            {activeLinks.map((link) => (
              <Badge key={link.distributorId} variant="blue">
                {link.distributorName}
              </Badge>
            ))}
          </span>
        );
      },
      sortValue: (row) => getActiveLinks(row).length,
    },
    {
      key: "created",
      header: "Criado em",
      render: (row) => new Date(row.createdAt).toLocaleDateString("pt-BR"),
      sortValue: (row) => row.createdAt,
    },
    {
      key: "actions",
      header: "Ações",
      align: "center",
      render: (row) => (
        <Button
          variant="secondary"
          onClick={() => {
            setGrantDistributorId("");
            setManagedUserId(row.userId);
          }}
        >
          <Settings2 size={14} /> Gerenciar acessos
        </Button>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Usuários"
        description="Usuários do portal e as indústrias que cada um pode acessar"
        actions={
          <Button
            onClick={() => {
              setForm(EMPTY_FORM);
              setIsCreateModalOpen(true);
            }}
          >
            <UserPlus size={14} /> Novo usuário
          </Button>
        }
      />

      <DataTable columns={columns} rows={users} rowKey={(row) => row.userId} isLoading={isLoading} />

      <Modal
        title="Cadastrar usuário"
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setIsCreateModalOpen(false)}>
              Cancelar
            </Button>
            <Button
              disabled={!canSubmitCreate || createMutation.isPending}
              onClick={() => createMutation.mutate({ ...form, email: form.email.trim() })}
            >
              {createMutation.isPending ? "Salvando..." : "Salvar"}
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          <TextField
            label="E-mail"
            type="email"
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
          <MultiSelectField
            label={INDUSTRY_LABELS.switcherLabel + "s"}
            allLabel="Selecione"
            options={distributors.map((distributor) => ({
              value: distributor.id,
              label: distributor.name,
            }))}
            values={form.distributorIds}
            onChange={(distributorIds) => setForm({ ...form, distributorIds })}
          />
          <p className="text-xs text-text2">
            O usuário poderá alternar entre as indústrias selecionadas após o login.
          </p>
        </div>
      </Modal>

      <Modal
        title={managedUser ? `Acessos de ${managedUser.email}` : "Acessos"}
        isOpen={managedUser !== null}
        onClose={() => setManagedUserId(null)}
        footer={
          <Button variant="secondary" onClick={() => setManagedUserId(null)}>
            Fechar
          </Button>
        }
      >
        {managedUser ? (
          <div className="space-y-4">
            <div>
              <span className="label-base">Acessos atuais</span>
              {managedUser.links.length === 0 ? (
                <p className="text-sm text-text2">Nenhum acesso cadastrado.</p>
              ) : (
                <ul className="space-y-2">
                  {managedUser.links.map((link) => (
                    <li
                      key={link.distributorId}
                      className="flex items-center justify-between gap-3 rounded-md border border-line px-3 py-2"
                    >
                      <span className="min-w-0">
                        <span className="block truncate text-sm text-text1">
                          {link.distributorName}
                        </span>
                        <Badge variant="blue">{link.distributorCode}</Badge>
                      </span>
                      <span className="flex shrink-0 items-center gap-2">
                        <StatusBadge isActive={link.status === "active"} />
                        {link.status === "active" ? (
                          <Button
                            variant="secondary"
                            disabled={revokeMutation.isPending}
                            onClick={() =>
                              revokeMutation.mutate({
                                userId: managedUser.userId,
                                distributorId: link.distributorId,
                              })
                            }
                          >
                            Revogar
                          </Button>
                        ) : (
                          <Button
                            variant="secondary"
                            disabled={grantMutation.isPending}
                            onClick={() =>
                              grantMutation.mutate({
                                userId: managedUser.userId,
                                distributorId: link.distributorId,
                              })
                            }
                          >
                            Reativar
                          </Button>
                        )}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <div className="flex items-end gap-2">
              <SelectField
                label={`Adicionar ${INDUSTRY_LABELS.switcherLabel.toLowerCase()}`}
                allLabel="Selecione"
                wrapperClassName="min-w-0 flex-1"
                options={grantableDistributors.map((distributor) => ({
                  value: distributor.id,
                  label: distributor.name,
                }))}
                value={grantDistributorId}
                onChange={(event) => setGrantDistributorId(event.target.value)}
              />
              <Button
                disabled={!grantDistributorId || grantMutation.isPending}
                onClick={() =>
                  grantMutation.mutate({
                    userId: managedUser.userId,
                    distributorId: grantDistributorId,
                  })
                }
              >
                {grantMutation.isPending ? "Adicionando..." : "Adicionar"}
              </Button>
            </div>
          </div>
        ) : null}
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
