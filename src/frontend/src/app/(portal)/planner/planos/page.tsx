"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { RefreshCcw } from "lucide-react";
import { PlanResultSection } from "@/components/planner/plan-result-section";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { PageHeader } from "@/components/ui/page-header";
import { useToast } from "@/components/ui/toast";
import { fetchPlannerPlans, recalculatePlanRoute } from "@/lib/data/planner";
import { formatCurrency, formatDecimal, formatInteger, formatIsoDateTime } from "@/lib/format";
import {
  formatPlanCode,
  PLANNER_MODEL_LABELS,
  resolvePlannerErrorMessage,
} from "@/lib/planner";
import type { PlannerPlanSummary } from "@/types/planner";

const WEEKLY_MODELS = new Set(["automatic", "battleship_volume", "battleship_positivation"]);

export default function PlannerPlanosPage() {
  const scope = usePlannerScope();
  const queryClient = useQueryClient();
  const { showToast } = useToast();
  const [selectedPlan, setSelectedPlan] = useState<PlannerPlanSummary | null>(null);

  const { data: plans, isLoading } = useQuery({
    queryKey: ["planner-plans", scope.distributorId],
    queryFn: () => fetchPlannerPlans(scope.distributorId),
  });

  // Admins can switch distributors; a plan from the previous one must not
  // stay open in the detail section.
  useEffect(() => {
    setSelectedPlan(null);
  }, [scope.distributorId]);

  const recalculateMutation = useMutation({
    mutationFn: recalculatePlanRoute,
    onSuccess: (generated) => {
      queryClient.invalidateQueries({ queryKey: ["planner-plans"] });
      setSelectedPlan(null);
      showToast(
        "success",
        `Rota recalculada: ${formatPlanCode(generated.code)} agora na versão ${generated.version}.`,
      );
    },
    onError: (error) => showToast("error", resolvePlannerErrorMessage(error)),
  });

  const columns: DataTableColumn<PlannerPlanSummary>[] = [
    {
      key: "code",
      header: "Código",
      render: (row) => (
        <span className="font-semibold text-text1">{formatPlanCode(row.code)}</span>
      ),
      sortValue: (row) => row.code,
    },
    {
      key: "model",
      header: "Modelo",
      render: (row) => PLANNER_MODEL_LABELS[row.model],
      sortValue: (row) => PLANNER_MODEL_LABELS[row.model],
    },
    {
      key: "routeFile",
      header: "Roteiro",
      render: (row) => row.routeFileName ?? "—",
      sortValue: (row) => row.routeFileName,
    },
    { key: "version", header: "Versão", render: (row) => `v${row.version}`, sortValue: (row) => row.version },
    {
      key: "status",
      header: "Status",
      render: (row) =>
        row.status === "generated" ? (
          <Badge variant="green">Vigente</Badge>
        ) : (
          <Badge variant="neutral">Substituído</Badge>
        ),
      sortValue: (row) => row.status,
    },
    {
      key: "lines",
      header: "Linhas",
      align: "right",
      render: (row) => formatInteger(row.lineCount),
      sortValue: (row) => row.lineCount,
    },
    {
      key: "quantity",
      header: "Volume",
      align: "right",
      render: (row) => (row.totalQuantity === null ? "—" : formatDecimal(row.totalQuantity)),
      sortValue: (row) => row.totalQuantity,
    },
    {
      key: "value",
      header: "Valor R$",
      align: "right",
      render: (row) => (row.totalValue === null ? "—" : formatCurrency(row.totalValue)),
      sortValue: (row) => row.totalValue,
    },
    {
      key: "createdAt",
      header: "Gerado em",
      render: (row) => formatIsoDateTime(row.createdAt),
      sortValue: (row) => row.createdAt,
    },
    {
      key: "actions",
      header: "",
      sortable: false,
      render: (row) => (
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => setSelectedPlan(row)}>
            Ver linhas
          </Button>
          {row.status === "generated" && WEEKLY_MODELS.has(row.model) ? (
            <Button
              variant="secondary"
              disabled={recalculateMutation.isPending}
              onClick={() => recalculateMutation.mutate(row.id)}
            >
              <RefreshCcw size={14} />
              Recalcular Rota
            </Button>
          ) : null}
        </div>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Planificadores gerados"
        description="Todo planificador gerado recebe um código sequencial para reconsulta e avaliação — inclusive quando vários rodam ao mesmo tempo."
        actions={
          <Link href="/planner/dashboard">
            <Button variant="secondary">Avaliar no Dashboard</Button>
          </Link>
        }
      />

      <div className="mb-4 max-w-xs">
        <PlannerDistributorField scope={scope} />
      </div>

      <DataTable
        columns={columns}
        rows={plans ?? []}
        rowKey={(row) => row.id}
        isLoading={isLoading}
        emptyMessage="Nenhum planificador gerado ainda"
      />

      {selectedPlan ? (
        <div className="mt-5 grid gap-3">
          <div className="text-xs text-text2">
            {PLANNER_MODEL_LABELS[selectedPlan.model]} · v{selectedPlan.version} · gerado em{" "}
            {formatIsoDateTime(selectedPlan.createdAt)}
          </div>
          <PlanResultSection
            planId={selectedPlan.id}
            planCode={selectedPlan.code}
            exportFileName={`planificador-${formatPlanCode(selectedPlan.code)}-v${selectedPlan.version}`}
            exportParams={{
              Planificador: formatPlanCode(selectedPlan.code),
              Modelo: PLANNER_MODEL_LABELS[selectedPlan.model],
              Versão: selectedPlan.version,
              Status: selectedPlan.status === "generated" ? "Vigente" : "Substituído",
              Roteiro: selectedPlan.routeFileName ?? "—",
              Parâmetros: JSON.stringify(selectedPlan.params),
            }}
          />
        </div>
      ) : null}
    </div>
  );
}
