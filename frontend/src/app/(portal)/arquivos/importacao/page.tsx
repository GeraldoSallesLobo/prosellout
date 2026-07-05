"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { FileText, Upload } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { DateField, FieldWrapper, SelectField } from "@/components/ui/field";
import { Badge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { useToast } from "@/components/ui/toast";
import {
  fetchFileImports,
  fetchFileTypeConfigs,
  fetchImportLogs,
  registerFileImport,
} from "@/lib/data/imports";
import { formatInteger } from "@/lib/format";
import type { FileImport, ImportStatus } from "@/types/domain";

const STATUS_LABELS: Record<ImportStatus, { label: string; variant: "green" | "red" | "blue" | "yellow" | "neutral" }> = {
  pending: { label: "Pendente", variant: "neutral" },
  validating: { label: "Validando", variant: "blue" },
  processing: { label: "Processando", variant: "blue" },
  completed: { label: "Concluído", variant: "green" },
  completed_with_errors: { label: "Concluído c/ erros", variant: "yellow" },
  failed: { label: "Falhou", variant: "red" },
};

const STATUS_OPTIONS = Object.entries(STATUS_LABELS).map(([value, meta]) => ({
  value,
  label: meta.label,
}));

export default function FileImportPage() {
  const [statusFilter, setStatusFilter] = useState("");
  const [typeFilter, setTypeFilter] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [isUploadOpen, setIsUploadOpen] = useState(false);
  const [uploadTypeId, setUploadTypeId] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [logImport, setLogImport] = useState<FileImport | null>(null);
  const { showToast } = useToast();
  const queryClient = useQueryClient();

  const { data: fileTypes = [] } = useQuery({
    queryKey: ["file-type-configs"],
    queryFn: fetchFileTypeConfigs,
  });

  const { data: imports = [], isLoading } = useQuery({
    queryKey: ["file-imports", statusFilter, typeFilter, startDate, endDate],
    queryFn: () =>
      fetchFileImports({
        status: (statusFilter || undefined) as ImportStatus | undefined,
        typeId: typeFilter || undefined,
        start: startDate || undefined,
        end: endDate || undefined,
      }),
  });

  const { data: logs = [], isLoading: isLogsLoading } = useQuery({
    queryKey: ["import-logs", logImport?.id],
    queryFn: () => fetchImportLogs(logImport!.id),
    enabled: Boolean(logImport),
  });

  const uploadMutation = useMutation({
    mutationFn: async () => {
      if (!selectedFile || !uploadTypeId) return;
      await registerFileImport({
        fileName: selectedFile.name,
        sheetName: null,
        fileTypeId: uploadTypeId,
      });
    },
    onSuccess: () => {
      showToast(
        "success",
        "Importação registrada. O arquivo será processado em segundo plano.",
      );
      setIsUploadOpen(false);
      setSelectedFile(null);
      queryClient.invalidateQueries({ queryKey: ["file-imports"] });
    },
    onError: () => showToast("error", "Erro ao registrar importação."),
  });

  const columns: DataTableColumn<FileImport>[] = [
    { key: "file", header: "Arquivo", render: (row) => row.fileName, sortValue: (row) => row.fileName },
    { key: "sheet", header: "Aba", render: (row) => row.sheetName ?? "—", sortValue: (row) => row.sheetName },
    { key: "type", header: "Tipo", render: (row) => row.typeName, sortValue: (row) => row.typeName },
    {
      key: "status",
      header: "Status",
      align: "center",
      render: (row) => {
        const meta = STATUS_LABELS[row.status];
        return <Badge variant={meta.variant}>{meta.label}</Badge>;
      },
      sortValue: (row) => row.status,
      searchable: false,
    },
    {
      key: "records",
      header: "Registros",
      align: "right",
      render: (row) => `${formatInteger(row.processedRecords)}/${formatInteger(row.totalRecords)}`,
      sortValue: (row) => row.processedRecords,
    },
    {
      key: "errors",
      header: "Erros",
      align: "right",
      render: (row) =>
        row.errorCount > 0 ? (
          <span className="font-semibold text-red">{formatInteger(row.errorCount)}</span>
        ) : (
          "0"
        ),
      sortValue: (row) => row.errorCount,
    },
    {
      key: "date",
      header: "Data",
      render: (row) => new Date(row.createdAt).toLocaleString("pt-BR"),
      sortValue: (row) => row.createdAt,
    },
    { key: "user", header: "Usuário", render: (row) => row.importedBy ?? "—", sortValue: (row) => row.importedBy },
    {
      key: "actions",
      header: "Log",
      align: "center",
      sortable: false,
      render: (row) => (
        <button
          type="button"
          onClick={() => setLogImport(row)}
          className="rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-blue"
          aria-label={`Ver log de ${row.fileName}`}
        >
          <FileText size={15} />
        </button>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Importação"
        description="Histórico e envio de arquivos para processamento"
        actions={
          <Button onClick={() => setIsUploadOpen(true)}>
            <Upload size={14} /> Importar arquivo
          </Button>
        }
      />

      <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
        <SelectField
          label="Tipo Arquivo"
          options={fileTypes.map((type) => ({ value: type.id, label: type.name }))}
          value={typeFilter}
          onChange={(event) => setTypeFilter(event.target.value)}
        />
        <SelectField
          label="Status"
          options={STATUS_OPTIONS}
          value={statusFilter}
          onChange={(event) => setStatusFilter(event.target.value)}
        />
        <DateField
          label="Data Início"
          value={startDate}
          onChange={(event) => setStartDate(event.target.value)}
        />
        <DateField
          label="Data Fim"
          value={endDate}
          onChange={(event) => setEndDate(event.target.value)}
        />
      </div>

      <DataTable columns={columns} rows={imports} rowKey={(row) => row.id} isLoading={isLoading} />

      <Modal
        title="Importar arquivo"
        isOpen={isUploadOpen}
        onClose={() => setIsUploadOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setIsUploadOpen(false)}>
              Cancelar
            </Button>
            <Button
              disabled={!selectedFile || !uploadTypeId || uploadMutation.isPending}
              onClick={() => uploadMutation.mutate()}
            >
              {uploadMutation.isPending ? "Enviando..." : "Enviar"}
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          <SelectField
            label="Tipo do Arquivo"
            allLabel="Selecione"
            options={fileTypes
              .filter((type) => type.status === "active")
              .map((type) => ({ value: type.id, label: type.name }))}
            value={uploadTypeId}
            onChange={(event) => setUploadTypeId(event.target.value)}
          />
          <FieldWrapper label="Arquivo (.xlsx ou .csv)">
            <input
              type="file"
              accept=".xlsx,.csv"
              onChange={(event) => setSelectedFile(event.target.files?.[0] ?? null)}
              className="block w-full text-sm text-text2 file:mr-3 file:rounded-md file:border-0 file:bg-accent2 file:px-3 file:py-2 file:text-sm file:font-semibold file:text-white hover:file:bg-accent2/85"
            />
          </FieldWrapper>
          <p className="text-xs text-text2">
            O arquivo é enviado ao storage e processado de forma assíncrona. Acompanhe o
            status nesta tela; linhas rejeitadas ficam disponíveis no log.
          </p>
        </div>
      </Modal>

      <Modal
        title={`Log — ${logImport?.fileName ?? ""}`}
        isOpen={Boolean(logImport)}
        onClose={() => setLogImport(null)}
      >
        {isLogsLoading ? (
          <p className="text-sm text-text2">Carregando log...</p>
        ) : logs.length === 0 ? (
          <p className="text-sm text-text2">Nenhuma ocorrência registrada.</p>
        ) : (
          <div className="max-h-80 space-y-1.5 overflow-y-auto">
            {logs.map((log) => (
              <div
                key={log.id}
                className="flex items-start gap-2 rounded-md border border-line bg-bg px-3 py-2 text-xs"
              >
                <Badge variant={log.level === "error" ? "red" : "blue"}>
                  {log.level === "error" ? "Erro" : "Info"}
                </Badge>
                <span className="text-text2">linha {log.lineNumber ?? "—"}</span>
                <span className="text-text3">{log.message}</span>
              </div>
            ))}
          </div>
        )}
      </Modal>
    </div>
  );
}
