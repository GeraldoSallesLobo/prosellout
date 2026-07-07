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
  const [name, setName] = useState("");
  const [parentId, setParentId] = useState("");
  const { showToast } = useToast();
  const queryClient = useQueryClient();

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

  function handleSubmit() {
    const parent = parentOptions.find((option) => option.id === parentId);
    const level = CHILD_LEVEL[parent?.level ?? ""];
    createMutation.mutate({ parentId: parentId || null, level, name });
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
    </div>
  );
}
