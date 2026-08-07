"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Radar } from "lucide-react";
import { PlanResultSection } from "@/components/planner/plan-result-section";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { DateField, SelectField, TextField } from "@/components/ui/field";
import { PageHeader } from "@/components/ui/page-header";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { useToast } from "@/components/ui/toast";
import { fetchPlannerUncoveredCustomers, generateCoveragePlan } from "@/lib/data/planner";
import { formatInteger } from "@/lib/format";
import {
  formatPlanCode,
  PLANNER_MODEL_LABELS,
  resolvePlannerErrorMessage,
} from "@/lib/planner";
import type {
  PlannerCoverageTargetKind,
  PlannerGenerationResult,
  PlannerUncoveredCustomer,
} from "@/types/planner";

const UNCOVERED_COLUMNS: DataTableColumn<PlannerUncoveredCustomer>[] = [
  { key: "pdv", header: "Cód. PDV", render: (row) => row.pdvCode ?? "—", sortValue: (row) => row.pdvCode },
  { key: "customer", header: "Cliente", render: (row) => row.customerName, sortValue: (row) => row.customerName },
  { key: "channel", header: "Canal", render: (row) => row.channelName ?? "—", sortValue: (row) => row.channelName },
];

const TARGET_KIND_OPTIONS = [
  { value: "value" as const, label: "Meta financeira (R$)" },
  { value: "quantity" as const, label: "Meta de volume (un)" },
];

export default function PlannerCoberturaPage() {
  const scope = usePlannerScope();
  const queryClient = useQueryClient();
  const { showToast } = useToast();

  const [productId, setProductId] = useState("");
  const [channelId, setChannelId] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [isPreviewEnabled, setIsPreviewEnabled] = useState(false);
  const [targetKind, setTargetKind] = useState<PlannerCoverageTargetKind>("value");
  const [targetAmount, setTargetAmount] = useState("");
  const [executionStart, setExecutionStart] = useState("");
  const [executionEnd, setExecutionEnd] = useState("");
  const [result, setResult] = useState<PlannerGenerationResult | null>(null);
  const [exportParams, setExportParams] = useState<Record<string, unknown>>({});

  const channelIds = channelId ? [channelId] : undefined;
  const hasFilters = Boolean(productId) && Boolean(startDate) && Boolean(endDate);

  const { data: uncovered, isLoading: isUncoveredLoading } = useQuery({
    queryKey: ["planner-uncovered", productId, channelId, startDate, endDate, scope.distributorId],
    queryFn: () =>
      fetchPlannerUncoveredCustomers(productId, startDate, endDate, channelIds, scope.distributorId),
    enabled: isPreviewEnabled && hasFilters,
  });

  const generateMutation = useMutation({
    mutationFn: generateCoveragePlan,
    onSuccess: (generated, variables) => {
      setResult(generated);
      // Snapshot of the inputs actually used, so later form edits never leak
      // into the export ("exportações indicam os parâmetros usados").
      setExportParams({
        Planificador: formatPlanCode(generated.code),
        Modelo: PLANNER_MODEL_LABELS.coverage,
        SKU:
          scope.filterOptions?.products.find(
            (product) => product.id === variables.productId,
          )?.name ?? variables.productId,
        Canal:
          scope.filterOptions?.channels.find(
            (channel) => channel.id === variables.channelIds?.[0],
          )?.name ?? "Todos",
        "Período analisado": `${variables.startDate} a ${variables.endDate}`,
        "Tipo de meta":
          variables.targetKind === "value" ? "Financeira (R$)" : "Volume (un)",
        "Meta informada": variables.targetAmount,
        "Meta por PDV": generated.amountPerCustomer ?? "",
        "Prazo de execução": `${variables.executionStart} a ${variables.executionEnd}`,
      });
      queryClient.invalidateQueries({ queryKey: ["planner-plans"] });
      showToast(
        "success",
        `Planificador ${formatPlanCode(generated.code)} gerado com ${generated.lineCount} PDVs.`,
      );
    },
    onError: (error) => showToast("error", resolvePlannerErrorMessage(error)),
  });

  const parsedAmount = Number(targetAmount.replace(",", "."));
  const hasExecutionPeriod =
    Boolean(executionStart) && Boolean(executionEnd) && executionStart <= executionEnd;
  const canGenerate =
    hasFilters &&
    parsedAmount > 0 &&
    hasExecutionPeriod &&
    (uncovered?.length ?? 0) > 0 &&
    !generateMutation.isPending;

  return (
    <div>
      <PageHeader
        title="Planificador de Cobertura"
        description="Identifica os PDVs sem venda do SKU em um período passado e distribui uma meta (R$ ou volume) de forma linear entre eles."
      />

      <div className="card mb-5 grid gap-4 p-4">
        <div className="grid gap-3 md:grid-cols-5">
          <PlannerDistributorField scope={scope} />
          <SelectField
            label="Passo 1 — SKU"
            allLabel="Selecione o SKU"
            value={productId}
            onChange={(event) => {
              setProductId(event.target.value);
              setIsPreviewEnabled(false);
              setResult(null);
            }}
            options={(scope.filterOptions?.products ?? []).map((product) => ({
              value: product.id,
              label: product.name,
            }))}
          />
          <SelectField
            label="Passo 2 — Canal (opcional)"
            value={channelId}
            onChange={(event) => {
              setChannelId(event.target.value);
              setIsPreviewEnabled(false);
            }}
            options={(scope.filterOptions?.channels ?? []).map((channel) => ({
              value: channel.id,
              label: channel.name,
            }))}
          />
          <DateField
            label="Passo 3 — Data início"
            value={startDate}
            onChange={(event) => {
              setStartDate(event.target.value);
              setIsPreviewEnabled(false);
            }}
          />
          <DateField
            label="Data fim"
            value={endDate}
            onChange={(event) => {
              setEndDate(event.target.value);
              setIsPreviewEnabled(false);
            }}
          />
        </div>
        <div>
          <Button
            variant="secondary"
            disabled={!hasFilters}
            onClick={() => setIsPreviewEnabled(true)}
          >
            <Radar size={14} />
            Passo 4 — Buscar PDVs descobertos
          </Button>
        </div>

        {isPreviewEnabled && hasFilters ? (
          <div className="grid gap-3">
            <p className="text-xs text-text2">
              {isUncoveredLoading
                ? "Buscando PDVs sem venda no período..."
                : `${formatInteger(uncovered?.length ?? 0)} PDVs sem venda do SKU no período selecionado.`}
            </p>
            <DataTable
              columns={UNCOVERED_COLUMNS}
              rows={uncovered ?? []}
              rowKey={(row) => row.customerId}
              isLoading={isUncoveredLoading}
              emptyMessage="Todos os PDVs do recorte tiveram venda no período"
            />
            <div className="grid gap-3">
              <h2 className="text-sm font-bold text-text1">Passo 5 — Meta a ser buscada</h2>
              <ToggleBadges
                options={TARGET_KIND_OPTIONS}
                value={targetKind}
                onChange={(value) => setTargetKind(value)}
              />
              <div className="grid gap-3 md:grid-cols-3">
                <TextField
                  label={targetKind === "value" ? "Valor da meta (R$)" : "Volume da meta (un)"}
                  type="number"
                  min={0}
                  value={targetAmount}
                  onChange={(event) => setTargetAmount(event.target.value)}
                />
                <DateField
                  label="Executar de"
                  value={executionStart}
                  onChange={(event) => setExecutionStart(event.target.value)}
                />
                <DateField
                  label="Executar até"
                  value={executionEnd}
                  onChange={(event) => setExecutionEnd(event.target.value)}
                />
              </div>
              <p className="text-xs text-text2">
                O prazo de execução define o período em que a meta deve ser buscada — é ele
                que o Dashboard usa para comparar planejado × realizado.
              </p>
              <div>
                <Button
                  disabled={!canGenerate}
                  onClick={() =>
                    generateMutation.mutate({
                      productId,
                      startDate,
                      endDate,
                      targetKind,
                      targetAmount: parsedAmount,
                      executionStart,
                      executionEnd,
                      channelIds,
                      distributorId: scope.distributorId,
                    })
                  }
                >
                  {generateMutation.isPending
                    ? "Gerando..."
                    : "Passo 6 — Distribuir meta entre os PDVs"}
                </Button>
              </div>
            </div>
          </div>
        ) : null}
      </div>

      {result ? (
        <PlanResultSection
          planId={result.planId}
          planCode={result.code}
          exportFileName={`planificador-cobertura-${formatPlanCode(result.code)}`}
          exportParams={exportParams}
        />
      ) : null}
    </div>
  );
}
