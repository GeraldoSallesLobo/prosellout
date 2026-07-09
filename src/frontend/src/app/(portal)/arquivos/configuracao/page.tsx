"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { FileText } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { UserOnly } from "@/components/access/access-gate";
import { Modal } from "@/components/ui/modal";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ImportLayoutHelp } from "@/components/imports/import-layout-help";
import { fetchFileTypeConfigs } from "@/lib/data/imports";
import type { FileTypeConfig } from "@/types/domain";

function FileConfigContent() {
  const [layoutConfig, setLayoutConfig] = useState<FileTypeConfig | null>(null);

  const { data: configs = [], isLoading } = useQuery({
    queryKey: ["file-type-configs"],
    queryFn: fetchFileTypeConfigs,
  });

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
      header: "Layout",
      align: "center",
      sortable: false,
      searchable: false,
      render: (row) => (
        <button
          type="button"
          onClick={() => setLayoutConfig(row)}
          aria-label={`Ver layout de ${row.name}`}
          title="Ver layout esperado"
          className="rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-blue"
        >
          <FileText size={14} />
        </button>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Configuração de Arquivos"
        description="Visualização dos tipos de arquivo suportados, tabelas de destino e rotinas de processamento"
      />
      <DataTable columns={columns} rows={configs} rowKey={(row) => row.id} isLoading={isLoading} />

      <Modal
        title={`Layout — ${layoutConfig?.name ?? ""}`}
        isOpen={Boolean(layoutConfig)}
        onClose={() => setLayoutConfig(null)}
      >
        <ImportLayoutHelp
          config={layoutConfig}
          emptyMessage="Este tipo ainda não tem contrato de importação documentado."
        />
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
