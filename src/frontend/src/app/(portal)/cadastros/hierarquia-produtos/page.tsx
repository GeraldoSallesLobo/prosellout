"use client";

import { useMemo, useState } from "react";
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
  createHierarchyNode,
  fetchProductHierarchy,
  type StatusFilter,
} from "@/lib/data/master-data";
import type { HierarchyNode } from "@/types/domain";

const STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "inactive", label: "Inativo" },
];

const LEVEL_LABELS: Record<HierarchyNode["level"], string> = {
  macro_category: "Macro",
  category: "Categoria",
  subcategory: "Subcategoria",
};

const CHILD_LEVEL: Record<string, HierarchyNode["level"]> = {
  "": "macro_category",
  macro_category: "category",
  category: "subcategory",
};
const CONFIRMATION_TEXT = "EXCLUIR";

function toTreeNodes(nodes: HierarchyNode[]): TreeNode[] {
  return nodes.map((node) => ({
    id: node.id,
    name: node.name,
    isActive: node.status === "active",
    levelLabel: LEVEL_LABELS[node.level],
    children: toTreeNodes(node.children),
  }));
}

function flattenParents(nodes: HierarchyNode[]): { id: string; label: string; level: HierarchyNode["level"] }[] {
  const parents: { id: string; label: string; level: HierarchyNode["level"] }[] = [];
  const walk = (list: HierarchyNode[], prefix: string) => {
    list.forEach((node) => {
      if (node.level !== "subcategory") {
        parents.push({ id: node.id, label: `${prefix}${node.name}`, level: node.level });
      }
      walk(node.children, `${prefix}${node.name} › `);
    });
  };
  walk(nodes, "");
  return parents;
}

export default function ProductHierarchyPage() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [nodeToDelete, setNodeToDelete] = useState<TreeNode | null>(null);
  const [confirmationText, setConfirmationText] = useState("");
  const [name, setName] = useState("");
  const [parentId, setParentId] = useState("");
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const isAdmin = access?.isAdmin === true;

  const { data: tree = [], isLoading } = useQuery({
    queryKey: ["product-hierarchy", statusFilter],
    queryFn: () => fetchProductHierarchy(statusFilter),
  });

  const parentOptions = useMemo(() => flattenParents(tree), [tree]);

  const createMutation = useMutation({
    mutationFn: createHierarchyNode,
    onSuccess: () => {
      showToast("success", "Registro incluído na hierarquia.");
      setIsModalOpen(false);
      setName("");
      setParentId("");
      queryClient.invalidateQueries({ queryKey: ["product-hierarchy"] });
    },
    onError: () => showToast("error", "Erro ao salvar registro."),
  });

  const deleteMutation = useMutation({
    mutationFn: () =>
      deletePlatformData({
        dataset: "product_hierarchy",
        rowIds: nodeToDelete ? [nodeToDelete.id] : [],
      }),
    onSuccess: (deletedCount) => {
      showToast(
        deletedCount > 0 ? "success" : "info",
        deletedCount === 1
          ? "1 nível da hierarquia excluído."
          : `${deletedCount.toLocaleString("pt-BR")} níveis da hierarquia excluídos.`,
      );
      setNodeToDelete(null);
      setConfirmationText("");
      queryClient.invalidateQueries({ queryKey: ["product-hierarchy"] });
      queryClient.invalidateQueries({ queryKey: ["filter-options"] });
      queryClient.invalidateQueries({ queryKey: ["platform-deletion-logs"] });
      queryClient.invalidateQueries({ queryKey: ["status-mtd"] });
      queryClient.invalidateQueries({ queryKey: ["status-analysis"] });
      queryClient.invalidateQueries({ queryKey: ["fast-facts"] });
    },
    onError: () => showToast("error", "Erro ao excluir hierarquia de produtos."),
  });

  function handleSubmit() {
    const parent = parentOptions.find((option) => option.id === parentId);
    const level = CHILD_LEVEL[parent?.level ?? ""];
    createMutation.mutate({ parentId: parentId || null, level, name });
  }

  function handleCloseDeleteModal(): void {
    if (deleteMutation.isPending) return;
    setNodeToDelete(null);
    setConfirmationText("");
  }

  return (
    <div>
      <PageHeader
        title="Hierarquia de Produtos"
        description="Macrocategoria › Categoria › Subcategoria"
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
          nodes={toTreeNodes(tree)}
          onEdit={() => showToast("info", "Edição disponível após conectar o Supabase.")}
          onDelete={isAdmin ? setNodeToDelete : undefined}
        />
      )}

      <Modal
        title="Cadastrar nível da hierarquia"
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setIsModalOpen(false)}>
              Cancelar
            </Button>
            <Button
              disabled={name.trim().length === 0 || createMutation.isPending}
              onClick={handleSubmit}
            >
              {createMutation.isPending ? "Salvando..." : "Salvar"}
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          <SelectField
            label="Nível pai"
            allLabel="Nenhum (nova macrocategoria)"
            options={parentOptions.map((option) => ({ value: option.id, label: option.label }))}
            value={parentId}
            onChange={(event) => setParentId(event.target.value)}
          />
          <TextField
            label="Nome"
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Ex.: Snacks de Batatas"
          />
        </div>
      </Modal>

      <Modal
        title="Excluir hierarquia de produtos"
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
            Esta ação remove <strong className="text-text1">{nodeToDelete?.name}</strong>, seus
            níveis filhos, produtos vinculados e movimentações/metas desses produtos.
          </p>
          <p className="rounded-md border border-red/30 bg-red/5 px-3 py-2 text-red">
            Essa exclusão atualiza os relatórios e fica registrada em Admin › Logs.
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
