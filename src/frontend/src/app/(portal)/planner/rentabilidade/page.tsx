"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Percent } from "lucide-react";
import { PlanResultSection } from "@/components/planner/plan-result-section";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { Button } from "@/components/ui/button";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { DateField, SelectField, TextField } from "@/components/ui/field";
import { PageHeader } from "@/components/ui/page-header";
import { useToast } from "@/components/ui/toast";
import {
  fetchPlannerLowMarginCustomers,
  generateProfitabilityPlan,
} from "@/lib/data/planner";
import { formatCurrency, formatInteger, formatPercent } from "@/lib/format";
import {
  formatPlanCode,
  PLANNER_MODEL_LABELS,
  resolvePlannerErrorMessage,
} from "@/lib/planner";
import type { PlannerGenerationResult, PlannerLowMarginCustomer } from "@/types/planner";

const LOW_MARGIN_COLUMNS: DataTableColumn<PlannerLowMarginCustomer>[] = [
  { key: "pdv", header: "Cód. PDV", render: (row) => row.pdvCode ?? "—", sortValue: (row) => row.pdvCode },
  { key: "customer", header: "Cliente", render: (row) => row.customerName, sortValue: (row) => row.customerName },
  { key: "channel", header: "Canal", render: (row) => row.channelName ?? "—", sortValue: (row) => row.channelName },
  {
    key: "value",
    header: "Faturamento",
    align: "right",
    render: (row) => formatCurrency(row.realizedValue),
    sortValue: (row) => row.realizedValue,
  },
  {
    key: "margin",
    header: "Margem praticada",
    align: "right",
    render: (row) => formatPercent(row.realizedMargin),
    sortValue: (row) => row.realizedMargin,
  },
  {
    key: "gap",
    header: "Gap de margem",
    align: "right",
    render: (row) => formatPercent(row.marginGap),
    sortValue: (row) => row.marginGap,
  },
  {
    key: "revenueGap",
    header: "Receita não capturada",
    align: "right",
    render: (row) => formatCurrency(row.revenueGap),
    sortValue: (row) => row.revenueGap,
  },
];

const PERCENT_DIVISOR = 100;

export default function PlannerRentabilidadePage() {
  const scope = usePlannerScope();
  const queryClient = useQueryClient();
  const { showToast } = useToast();

  const [productId, setProductId] = useState("");
  const [channelId, setChannelId] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [marginInput, setMarginInput] = useState("20");
  const [executionStart, setExecutionStart] = useState("");
  const [executionEnd, setExecutionEnd] = useState("");
  const [isPreviewEnabled, setIsPreviewEnabled] = useState(false);
  const [result, setResult] = useState<PlannerGenerationResult | null>(null);
  const [exportParams, setExportParams] = useState<Record<string, unknown>>({});

  const channelIds = channelId ? [channelId] : undefined;
  const targetMargin = Number(marginInput.replace(",", ".")) / PERCENT_DIVISOR;
  const hasFilters =
    Boolean(productId) && Boolean(startDate) && Boolean(endDate) && targetMargin > 0 && targetMargin < 1;

  const {
    data: lowMargin,
    isLoading: isLowMarginLoading,
    error: lowMarginError,
  } = useQuery({
    queryKey: ["planner-low-margin", productId, channelId, startDate, endDate, marginInput, scope.distributorId],
    queryFn: () =>
      fetchPlannerLowMarginCustomers(
        productId, startDate, endDate, targetMargin, channelIds, scope.distributorId,
      ),
    enabled: isPreviewEnabled && hasFilters,
    retry: false,
  });

  const generateMutation = useMutation({
    mutationFn: generateProfitabilityPlan,
    onSuccess: (generated, variables) => {
      setResult(generated);
      // Snapshot of the inputs actually used, so later form edits never leak
      // into the export ("exportações indicam os parâmetros usados").
      setExportParams({
        Planificador: formatPlanCode(generated.code),
        Modelo: PLANNER_MODEL_LABELS.profitability,
        SKU:
          scope.filterOptions?.products.find(
            (product) => product.id === variables.productId,
          )?.name ?? variables.productId,
        Canal:
          scope.filterOptions?.channels.find(
            (channel) => channel.id === variables.channelIds?.[0],
          )?.name ?? "Todos",
        "Período analisado": `${variables.startDate} a ${variables.endDate}`,
        "Margem objetivo": formatPercent(variables.targetMargin),
        "Receita não capturada total": generated.totalRevenueGap ?? "",
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

  const hasExecutionPeriod =
    Boolean(executionStart) && Boolean(executionEnd) && executionStart <= executionEnd;
  const canGenerate =
    hasFilters &&
    hasExecutionPeriod &&
    (lowMargin?.length ?? 0) > 0 &&
    !generateMutation.isPending;

  return (
    <div>
      <PageHeader
        title="Planificador de Rentabilidade"
        description="Encontra os PDVs com margem abaixo da margem objetivo e calcula a receita que o gap deixou de gerar. A margem usa o preço de compra do Sell In como custo (mesma regra do Status MTD)."
      />

      <div className="card mb-5 grid gap-4 p-4">
        <div className="grid gap-3 md:grid-cols-6">
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
          <TextField
            label="Passo 4 — Margem objetivo (%)"
            type="number"
            min={1}
            max={99}
            value={marginInput}
            onChange={(event) => {
              setMarginInput(event.target.value);
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
            <Percent size={14} />
            Buscar PDVs abaixo da margem
          </Button>
        </div>

        {isPreviewEnabled && lowMarginError ? (
          <div className="rounded-md border border-yellow/40 bg-yellow/5 px-4 py-3 text-sm text-text1">
            {resolvePlannerErrorMessage(lowMarginError)}
          </div>
        ) : null}

        {isPreviewEnabled && hasFilters && !lowMarginError ? (
          <div className="grid gap-3">
            <p className="text-xs text-text2">
              {isLowMarginLoading
                ? "Calculando margens por PDV..."
                : `${formatInteger(lowMargin?.length ?? 0)} PDVs com margem abaixo de ${marginInput}% no período.`}
            </p>
            <DataTable
              columns={LOW_MARGIN_COLUMNS}
              rows={lowMargin ?? []}
              rowKey={(row) => row.customerId}
              isLoading={isLowMarginLoading}
              emptyMessage="Nenhum PDV abaixo da margem objetivo"
            />
            <div className="grid max-w-md grid-cols-2 gap-3">
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
              O prazo de execução define o período em que a receita deve ser recuperada — é
              ele que o Dashboard usa para comparar planejado × realizado.
            </p>
            <div>
              <Button
                disabled={!canGenerate}
                onClick={() =>
                  generateMutation.mutate({
                    productId,
                    startDate,
                    endDate,
                    targetMargin,
                    executionStart,
                    executionEnd,
                    channelIds,
                    distributorId: scope.distributorId,
                  })
                }
              >
                {generateMutation.isPending
                  ? "Gerando..."
                  : "Passos 5 e 6 — Gerar plano de recuperação"}
              </Button>
            </div>
          </div>
        ) : null}
      </div>

      {result ? (
        <PlanResultSection
          planId={result.planId}
          planCode={result.code}
          exportFileName={`planificador-rentabilidade-${formatPlanCode(result.code)}`}
          exportParams={exportParams}
        />
      ) : null}
    </div>
  );
}
