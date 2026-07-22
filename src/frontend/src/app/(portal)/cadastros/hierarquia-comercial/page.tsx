"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { SelectField, TextField } from "@/components/ui/field";
import { TreeView, type TreeNode } from "@/components/ui/tree-view";
import { Skeleton } from "@/components/ui/skeleton";
import { useToast } from "@/components/ui/toast";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { deletePlatformData } from "@/lib/data/admin";
import {
  createSalesRep,
  fetchCommercialHierarchy,
  type StatusFilter,
} from "@/lib/data/master-data";
import type { SalesRole } from "@/types/domain";

const STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "inactive", label: "Inativo" },
];

const ROLE_OPTIONS = [
  { value: "supervisor", label: "Supervisor" },
  { value: "seller", label: "Vendedor" },
];
const CONFIRMATION_TEXT = "EXCLUIR";

export default function CommercialHierarchyPage() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [nodeToDelete, setNodeToDelete] = useState<TreeNode | null>(null);
  const [confirmationText, setConfirmationText] = useState("");
  const [name, setName] = useState("");
  const [role, setRole] = useState<SalesRole>("seller");
  const [supervisorId, setSupervisorId] = useState("");
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const isAdmin = access?.isAdmin === true;

  const { data, isLoading } = useQuery({
    queryKey: ["commercial-hierarchy", statusFilter],
    queryFn: () => fetchCommercialHierarchy(statusFilter),
  });

  const createMutation = useMutation({
    mutationFn: createSalesRep,
    onSuccess: () => {
      showToast("success", "Classificação comercial cadastrada.");
      setIsModalOpen(false);
      setName("");
      queryClient.invalidateQueries({ queryKey: ["commercial-hierarchy"] });
    },
    onError: () => showToast("error", "Erro ao salvar classificação."),
  });

  const deleteMutation = useMutation({
    mutationFn: () =>
      deletePlatformData({
        dataset: "commercial_hierarchy",
        rowIds: nodeToDelete ? [nodeToDelete.id] : [],
      }),
    onSuccess: (deletedCount) => {
      showToast(
        deletedCount > 0 ? "success" : "info",
        deletedCount === 1
          ? "1 registro comercial excluído."
          : `${deletedCount.toLocaleString("pt-BR")} registros comerciais excluídos.`,
      );
      setNodeToDelete(null);
      setConfirmationText("");
      queryClient.invalidateQueries({ queryKey: ["commercial-hierarchy"] });
      queryClient.invalidateQueries({ queryKey: ["sellers"] });
      queryClient.invalidateQueries({ queryKey: ["filter-options"] });
      queryClient.invalidateQueries({ queryKey: ["platform-deletion-logs"] });
      queryClient.invalidateQueries({ queryKey: ["status-mtd"] });
      queryClient.invalidateQueries({ queryKey: ["status-analysis"] });
      queryClient.invalidateQueries({ queryKey: ["fast-facts"] });
    },
    onError: () => showToast("error", "Erro ao excluir hierarquia comercial."),
  });

  const treeNodes: TreeNode[] = (data?.supervisors ?? []).map((supervisor) => ({
    id: supervisor.id,
    name: supervisor.name,
    isActive: supervisor.status === "active",
    levelLabel: "Supervisor",
    children: (data?.sellersBySupervisor.get(supervisor.id) ?? []).map((seller) => ({
      id: seller.id,
      name: seller.name,
      isActive: seller.status === "active",
      levelLabel: "Vendedor",
      children: [],
    })),
  }));

  const canSubmit =
    name.trim().length > 0 && (role === "supervisor" || supervisorId.length > 0);

  function handleCloseDeleteModal(): void {
    if (deleteMutation.isPending) return;
    setNodeToDelete(null);
    setConfirmationText("");
  }

  return (
    <div>
      <PageHeader
        title="Hierarquia Comercial"
        description="Supervisores e vendedores vinculados"
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

      {isLoading ? (
        <Skeleton className="h-64 w-full rounded-card" />
      ) : (
        <TreeView
          nodes={treeNodes}
          onEdit={() => showToast("info", "Edição disponível após conectar o Supabase.")}
          onDelete={isAdmin ? setNodeToDelete : undefined}
        />
      )}

      <Modal
        title="Cadastrar Classificação Comercial"
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setIsModalOpen(false)}>
              Cancelar
            </Button>
            <Button
              disabled={!canSubmit || createMutation.isPending}
              onClick={() =>
                createMutation.mutate({
                  name,
                  role,
                  supervisorId: role === "seller" ? supervisorId : null,
                })
              }
            >
              {createMutation.isPending ? "Salvando..." : "Salvar"}
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          <TextField
            label="Nome"
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Nome do colaborador"
          />
          <SelectField
            label="Função"
            allLabel="Selecione"
            options={ROLE_OPTIONS}
            value={role}
            onChange={(event) => setRole((event.target.value || "seller") as SalesRole)}
          />
          {role === "seller" ? (
            <SelectField
              label="Supervisor"
              allLabel="Selecione"
              options={(data?.supervisors ?? []).map((supervisor) => ({
                value: supervisor.id,
                label: supervisor.name,
              }))}
              value={supervisorId}
              onChange={(event) => setSupervisorId(event.target.value)}
            />
          ) : null}
        </div>
      </Modal>

      <Modal
        title="Excluir hierarquia comercial"
        isOpen={Boolean(nodeToDelete)}
        onClose={handleCloseDeleteModal}
        footer={
          <>
            <Button
              variant="secondary"
              onClick={handleCloseDeleteModal}
              disabled={deleteMutation.isPending}
            >
              Cancelar
            </Button>
            <Button
              variant="danger"
              disabled={confirmationText !== CONFIRMATION_TEXT || deleteMutation.isPending}
              onClick={() => deleteMutation.mutate()}
            >
              {deleteMutation.isPending ? "Excluindo..." : "Excluir hierarquia"}
            </Button>
          </>
        }
      >
        <div className="space-y-3 text-sm text-text2">
          <p>
            Esta ação remove <strong className="text-text1">{nodeToDelete?.name}</strong>. Se for
            um supervisor, os vendedores subordinados também serão removidos.
          </p>
          <p className="rounded-md border border-red/30 bg-red/5 px-3 py-2 text-red">
            Clientes, Sell Out e metas não são apagados; eles ficam sem vínculo com os vendedores
            excluídos. A ação fica registrada em Admin › Logs.
          </p>
          <label className="block">
            <span className="mb-1.5 block text-xs font-semibold uppercase tracking-wide text-text2">
              Digite {CONFIRMATION_TEXT} para confirmar
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
