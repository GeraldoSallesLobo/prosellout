"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AdminOnly } from "@/components/access/access-gate";
import { Badge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { DateField, SelectField } from "@/components/ui/field";
import { PageHeader } from "@/components/ui/page-header";
import {
  fetchPlatformDeletionLogs,
  type PlatformDataDataset,
  type PlatformDeletionLog,
} from "@/lib/data/admin";
import { DATA_PAGE_SIZE } from "@/lib/data/consolidated";
import { formatCnpj, formatInteger, formatIsoDate, formatIsoDateTime } from "@/lib/format";

const DATASET_LABELS: Record<PlatformDataDataset, string> = {
  customers: "Clientes",
  sales_reps: "Vendedores",
  sell_out: "Sell Out",
  sell_in: "Sell In",
  sales_targets: "Metas",
  product_hierarchy: "Hierarquia de Produtos",
  commercial_hierarchy: "Hierarquia Comercial",
  distributors: "Distribuidores",
};

const DATASET_OPTIONS = Object.entries(DATASET_LABELS).map(([value, label]) => ({
  value,
  label,
}));

interface LoggedDistributor {
  id: string | null;
  code: string | null;
  name: string | null;
  cnpj: string | null;
}

interface LoggedItem {
  id: string | null;
  code: string | null;
  name: string | null;
  type: string | null;
  cnpj: string | null;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(value: Record<string, unknown>, key: string): string | null {
  const field = value[key];
  return typeof field === "string" && field.trim() ? field : null;
}

function parseLoggedDistributors(filters: Record<string, unknown>): LoggedDistributor[] {
  const distributors = Array.isArray(filters.distributors) ? filters.distributors : [];
  return distributors
    .filter(isObject)
    .map((distributor) => ({
      id: readString(distributor, "id"),
      code: readString(distributor, "code"),
      name: readString(distributor, "name"),
      cnpj: readString(distributor, "cnpj"),
    }))
    .filter((distributor) => distributor.code || distributor.name || distributor.cnpj);
}

function parseLoggedItems(filters: Record<string, unknown>): LoggedItem[] {
  const items = Array.isArray(filters.items) ? filters.items : [];
  return items
    .filter(isObject)
    .map((item) => ({
      id: readString(item, "id"),
      code: readString(item, "code"),
      name: readString(item, "name"),
      type: readString(item, "type"),
      cnpj: readString(item, "cnpj"),
    }))
    .filter((item) => item.code || item.name || item.cnpj || item.type);
}

function formatLoggedDistributor(distributor: LoggedDistributor): string {
  const fallbackName = distributor.cnpj ? formatCnpj(distributor.cnpj) : null;
  const name = distributor.name ?? fallbackName;
  if (distributor.code && name) return `${distributor.code} - ${name}`;
  return distributor.code ?? name ?? distributor.id ?? "";
}

function formatLoggedItem(item: LoggedItem): string {
  const fallbackName = item.cnpj ? formatCnpj(item.cnpj) : null;
  const name = item.name ?? fallbackName;
  const label = item.code && name ? `${item.code} - ${name}` : item.code ?? name ?? item.id ?? "";
  return item.type ? `${label} (${item.type})` : label;
}

function formatFilterSummary(filters: Record<string, unknown>): string {
  const parts: string[] = [];
  const action = typeof filters.action === "string" ? filters.action : null;
  const mode = typeof filters.mode === "string" ? filters.mode : null;
  const rowIds = Array.isArray(filters.row_ids) ? filters.row_ids : [];
  const start = typeof filters.start === "string" ? filters.start : null;
  const end = typeof filters.end === "string" ? filters.end : null;
  const distributorId =
    typeof filters.distributor_id === "string" ? filters.distributor_id : null;
  const distributors = parseLoggedDistributors(filters);
  const items = parseLoggedItems(filters);
  const searchKey = typeof filters.search_key === "string" ? filters.search_key : null;
  const searchText = typeof filters.search_text === "string" ? filters.search_text : null;
  const channelIds = Array.isArray(filters.channel_ids) ? filters.channel_ids : [];
  const clusterId = typeof filters.cluster_id === "string" ? filters.cluster_id : null;
  const supervisorId =
    typeof filters.supervisor_id === "string" ? filters.supervisor_id : null;

  if (action === "inactivate") {
    parts.push("Ação: Inativação");
  } else if (action === "activate") {
    parts.push("Ação: Ativação");
  }
  if (mode === "selected_rows") {
    parts.push(`Selecionados: ${rowIds.length.toLocaleString("pt-BR")}`);
  }
  if (items.length > 0) {
    parts.push(`Itens: ${items.map(formatLoggedItem).join(", ")}`);
  }
  if (start || end) {
    const startLabel = start ? formatIsoDate(start) : "início";
    const endLabel = end ? formatIsoDate(end) : "fim";
    parts.push(`Período: ${startLabel} até ${endLabel}`);
  }
  if (distributors.length > 0) {
    parts.push(`Distribuidora: ${distributors.map(formatLoggedDistributor).join(", ")}`);
  } else if (distributorId) {
    parts.push(`Distribuidora: ${distributorId}`);
  }
  if (searchText) parts.push(`Busca${searchKey ? ` (${searchKey})` : ""}: ${searchText}`);
  if (channelIds.length > 0) parts.push(`Canais: ${channelIds.length}`);
  if (clusterId) parts.push(`Cluster: ${clusterId}`);
  if (supervisorId) parts.push(`Supervisor: ${supervisorId}`);

  return parts.length > 0 ? parts.join(" · ") : "Sem filtros";
}

function AdminDeletionLogsContent() {
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(DATA_PAGE_SIZE);
  const [dataset, setDataset] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");

  const { data, isLoading } = useQuery({
    queryKey: ["platform-deletion-logs", page, pageSize, dataset, start, end],
    queryFn: () =>
      fetchPlatformDeletionLogs({
        page,
        pageSize,
        dataset: dataset ? (dataset as PlatformDataDataset) : undefined,
        start: start || undefined,
        end: end || undefined,
      }),
  });

  const columns: DataTableColumn<PlatformDeletionLog>[] = [
    {
      key: "created",
      header: "Data/Hora",
      render: (row) => formatIsoDateTime(row.createdAt),
    },
    {
      key: "admin",
      header: "Admin",
      render: (row) => row.adminEmail ?? row.adminUserId,
    },
    {
      key: "dataset",
      header: "Base",
      render: (row) => <Badge variant="blue">{DATASET_LABELS[row.dataset]}</Badge>,
    },
    {
      key: "count",
      header: "Registros",
      align: "right",
      render: (row) => formatInteger(row.deletedCount),
    },
    {
      key: "filters",
      header: "Filtros usados",
      render: (row) => {
        const summary = formatFilterSummary(row.filters);
        return (
          <span title={summary} className="block max-w-[36rem] truncate">
            {summary}
          </span>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        title="Logs de Exclusão"
        description="Histórico das exclusões confirmadas por administradores"
      />

      <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
        <SelectField
          label="Base"
          options={DATASET_OPTIONS}
          value={dataset}
          onChange={(event) => {
            setDataset(event.target.value);
            setPage(1);
          }}
        />
        <DateField
          label="Data início"
          value={start}
          onChange={(event) => {
            setStart(event.target.value);
            setPage(1);
          }}
        />
        <DateField
          label="Data fim"
          value={end}
          onChange={(event) => {
            setEnd(event.target.value);
            setPage(1);
          }}
        />
      </div>

      <DataTable
        columns={columns}
        rows={data?.rows ?? []}
        rowKey={(row) => row.id}
        isLoading={isLoading}
        emptyMessage="Nenhum log de exclusão encontrado"
        pagination={{
          page,
          pageSize,
          total: data?.total ?? 0,
          onPageChange: setPage,
          onPageSizeChange: (size) => {
            setPageSize(size);
            setPage(1);
          },
        }}
      />
    </div>
  );
}

export default function AdminDeletionLogsPage() {
  return (
    <AdminOnly>
      <AdminDeletionLogsContent />
    </AdminOnly>
  );
}
