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

export default function CommercialHierarchyPage() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [name, setName] = useState("");
  const [role, setRole] = useState<SalesRole>("seller");
  const [supervisorId, setSupervisorId] = useState("");
  const { showToast } = useToast();
  const queryClient = useQueryClient();

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
    </div>
  );
}
