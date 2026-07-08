"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { UserOnly } from "@/components/access/access-gate";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { SelectField, TextField } from "@/components/ui/field";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { useToast } from "@/components/ui/toast";
import { fetchFileTypeConfigs, updateFileTypeConfig } from "@/lib/data/imports";
import type { EntityStatus, FileTypeConfig } from "@/types/domain";

const FORMAT_OPTIONS = [
  { value: "xlsx", label: "XLSX" },
  { value: "csv", label: "CSV" },
];

const STATUS_OPTIONS = [
  { value: "active", label: "Ativo" },
  { value: "inactive", label: "Inativo" },
];

function FileConfigContent() {
  const [editing, setEditing] = useState<FileTypeConfig | null>(null);
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: configs = [], isLoading } = useQuery({
    queryKey: ["file-type-configs"],
    queryFn: fetchFileTypeConfigs,
  });

  const updateMutation = useMutation({
    mutationFn: updateFileTypeConfig,
    onSuccess: () => {
      showToast("success", "Configuração atualizada com sucesso.");
      setEditing(null);
      queryClient.invalidateQueries({ queryKey: ["file-type-configs"] });
    },
    onError: () => showToast("error", "Erro ao atualizar configuração."),
  });

  const setField = <K extends keyof FileTypeConfig>(key: K, value: FileTypeConfig[K]) =>
    setEditing((current) => (current ? { ...current, [key]: value } : current));

  const canSubmit =
    Boolean(editing) &&
    [editing?.code, editing?.name, editing?.targetTable, editing?.processingRoutine].every(
      (value) => (value ?? "").trim().length > 0,
    );

  const columns: DataTableColumn<FileTypeConfig>[] = [
    { key: "code", header: "Código", render: (row) => row.code, sortValue: (row) => row.code },
    { key: "name", header: "Nome", render: (row) => row.name, sortValue: (row) => row.name },
    {
      key: "table",
      header: "Tabela",
      render: (row) => <code className="text-xs text-purple">{row.targetTable}</code>,
      sortValue: (row) => row.targetTable,
    },
    {
      key: "routine",
      header: "Rotina",
      render: (row) => <code className="text-xs text-blue">{row.processingRoutine}</code>,
      sortValue: (row) => row.processingRoutine,
    },
    {
      key: "format",
      header: "Tipo",
      align: "center",
      render: (row) => <Badge variant="blue">{row.fileFormat.toUpperCase()}</Badge>,
      sortValue: (row) => row.fileFormat,
    },
    { key: "origin", header: "Origem", render: (row) => row.origin, sortValue: (row) => row.origin },
    {
      key: "status",
      header: "Status",
      align: "center",
      render: (row) => <StatusBadge isActive={row.status === "active"} />,
      sortValue: (row) => row.status,
      searchable: false,
    },
    {
      key: "actions",
      header: "Ações",
      align: "center",
      sortable: false,
      searchable: false,
      render: (row) => (
        <button
          type="button"
          onClick={() => setEditing({ ...row })}
          aria-label={`Editar ${row.name}`}
          className="rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
        >
          <Pencil size={14} />
        </button>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Configuração de Arquivos"
        description="Tipos de arquivo suportados, tabelas de destino e rotinas de processamento"
      />
      <DataTable columns={columns} rows={configs} rowKey={(row) => row.id} isLoading={isLoading} />

      <Modal
        title="Editar Configuração de Arquivo"
        isOpen={Boolean(editing)}
        onClose={() => setEditing(null)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setEditing(null)}>
              Cancelar
            </Button>
            <Button
              disabled={!canSubmit || updateMutation.isPending}
              onClick={() => editing && updateMutation.mutate(editing)}
            >
              {updateMutation.isPending ? "Salvando..." : "Salvar"}
            </Button>
          </>
        }
      >
        {editing ? (
          <div className="grid grid-cols-2 gap-3">
            <TextField
              label="Código"
              value={editing.code}
              onChange={(event) => setField("code", event.target.value)}
              placeholder="SELL_OUT"
            />
            <TextField
              label="Nome"
              value={editing.name}
              onChange={(event) => setField("name", event.target.value)}
              placeholder="Sell Out Distribuidor"
            />
            <TextField
              label="Tabela de destino"
              value={editing.targetTable}
              onChange={(event) => setField("targetTable", event.target.value)}
              placeholder="sell_out"
            />
            <TextField
              label="Rotina de processamento"
              value={editing.processingRoutine}
              onChange={(event) => setField("processingRoutine", event.target.value)}
              placeholder="process_sell_out_staging"
            />
            <SelectField
              label="Tipo de arquivo"
              options={FORMAT_OPTIONS}
              value={editing.fileFormat}
              onChange={(event) => setField("fileFormat", event.target.value)}
            />
            <TextField
              label="Origem"
              value={editing.origin}
              onChange={(event) => setField("origin", event.target.value)}
              placeholder="upload"
            />
            <SelectField
              label="Status"
              options={STATUS_OPTIONS}
              value={editing.status}
              onChange={(event) => setField("status", event.target.value as EntityStatus)}
            />
          </div>
        ) : null}
      </Modal>
    </div>
  );
}

export default function FileConfigPage() {
  return (
    <UserOnly>
      <FileConfigContent />
    </UserOnly>
  );
}
