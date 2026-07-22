"use client";

import { useState } from "react";
import type { QueryKey } from "@tanstack/react-query";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/ui/toast";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import {
  deletePlatformData,
  type PlatformDataDataset,
} from "@/lib/data/admin";
import type { SearchState } from "@/lib/search";

const CONFIRMATION_TEXT = "EXCLUIR";
const DEFAULT_QUERY_KEYS_TO_INVALIDATE: QueryKey[] = [
  ["customers"],
  ["sellers"],
  ["sell-out-rows"],
  ["sell-in-rows"],
  ["target-rows"],
  ["stock-rows"],
  ["status-mtd"],
  ["status-analysis"],
  ["status-analysis-full"],
  ["fast-facts"],
  ["three-month-history"],
  ["evolution-analysis"],
  ["evolution-weekly"],
  ["product-hierarchy"],
  ["commercial-hierarchy"],
  ["distributors"],
  ["filter-options"],
  ["platform-deletion-logs"],
];

interface AdminDeleteFilters {
  start?: string;
  end?: string;
  distributorId?: string;
  channelIds?: string[];
  clusterId?: string;
  supervisorId?: string;
}

interface AdminDeleteFilteredDataButtonProps {
  dataset: PlatformDataDataset;
  label: string;
  scopeDescription: string;
  selectedRowIds?: Array<string | number>;
  filters?: AdminDeleteFilters;
  search?: SearchState | null;
  queryKeysToInvalidate?: QueryKey[];
  onDeleted?: () => void;
}

export function AdminDeleteFilteredDataButton({
  dataset,
  label,
  scopeDescription,
  selectedRowIds,
  filters,
  search,
  queryKeysToInvalidate,
  onDeleted,
}: AdminDeleteFilteredDataButtonProps) {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [confirmationText, setConfirmationText] = useState("");
  const queryClient = useQueryClient();
  const { showToast } = useToast();
  const invalidationQueryKeys = [
    ...DEFAULT_QUERY_KEYS_TO_INVALIDATE,
    ...(queryKeysToInvalidate ?? []),
  ];
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });

  const deleteMutation = useMutation({
    mutationFn: () =>
      deletePlatformData({
        dataset,
        rowIds: selectedRowIds,
        start: filters?.start,
        end: filters?.end,
        distributorId: filters?.distributorId,
        channelIds: filters?.channelIds,
        clusterId: filters?.clusterId,
        supervisorId: filters?.supervisorId,
        search,
      }),
    onSuccess: (deletedCount) => {
      const message =
        deletedCount === 1
          ? "1 registro excluído."
          : `${deletedCount.toLocaleString("pt-BR")} registros excluídos.`;
      showToast(deletedCount > 0 ? "success" : "info", message);
      setIsModalOpen(false);
      setConfirmationText("");
      onDeleted?.();
      invalidationQueryKeys.forEach((queryKey) => {
        queryClient.invalidateQueries({ queryKey });
      });
    },
    onError: () => {
      showToast("error", "Não foi possível excluir os dados filtrados.");
    },
  });

  if (!access?.isAdmin) return null;

  const selectedCount = selectedRowIds?.length ?? 0;
  const hasSelectedRows = selectedCount > 0;
  const canConfirm = confirmationText === CONFIRMATION_TEXT && !deleteMutation.isPending;

  function handleClose(): void {
    if (deleteMutation.isPending) return;
    setIsModalOpen(false);
    setConfirmationText("");
  }

  return (
    <>
      <Button variant="danger" onClick={() => setIsModalOpen(true)}>
        <Trash2 size={14} /> {hasSelectedRows ? "Excluir selecionados" : "Excluir"}
      </Button>

      <Modal
        title={`Excluir ${label}`}
        isOpen={isModalOpen}
        onClose={handleClose}
        footer={
          <>
            <Button variant="secondary" onClick={handleClose} disabled={deleteMutation.isPending}>
              Cancelar
            </Button>
            <Button
              variant="danger"
              disabled={!canConfirm}
              onClick={() => deleteMutation.mutate()}
            >
              {deleteMutation.isPending ? "Excluindo..." : "Excluir dados"}
            </Button>
          </>
        }
      >
        <div className="space-y-3 text-sm text-text2">
          <p>
            {hasSelectedRows
              ? `Esta ação remove ${selectedCount.toLocaleString("pt-BR")} registros selecionados de `
              : "Esta ação remove os registros que correspondem aos filtros atuais de "}
            <strong className="text-text1">{label}</strong>.
          </p>
          <p className="rounded-md border border-red/30 bg-red/5 px-3 py-2 text-red">
            {scopeDescription}
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
    </>
  );
}
