"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Anchor } from "lucide-react";
import { PlanResultSection } from "@/components/planner/plan-result-section";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { TopSkuChart } from "@/components/planner/top-sku-chart";
import { WeekScheduleFields } from "@/components/planner/week-schedule-fields";
import { Button } from "@/components/ui/button";
import { MultiSelectField } from "@/components/ui/multi-select-field";
import { SelectField } from "@/components/ui/field";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { useToast } from "@/components/ui/toast";
import {
  fetchPlannerRouteSummary,
  fetchPlannerSkuParticipation,
  fetchPlannerTargetMonths,
  fetchPlannerTopSkus,
  generateBattleshipPlan,
} from "@/lib/data/planner";
import { formatDecimal, formatPercent } from "@/lib/format";
import { formatMonthLabel } from "@/lib/periods";
import {
  buildDefaultWeeks,
  buildReferenceMonthOptions,
  formatPlanCode,
  getMonthEndIso,
  resolvePlannerErrorMessage,
} from "@/lib/planner";
import type {
  PlannerGenerationResult,
  PlannerSkuParticipationRow,
  PlannerTopSkuMetric,
  PlannerWeekInput,
} from "@/types/planner";

const ALLOCATION_GAP_TOLERANCE_UNITS = 1;

const PARTICIPATION_COLUMNS: DataTableColumn<PlannerSkuParticipationRow>[] = [
  { key: "pdv", header: "Cód. PDV", render: (row) => row.pdvCode ?? "—", sortable: false },
  { key: "customer", header: "Cliente", render: (row) => row.customerName, sortable: false },
  { key: "channel", header: "Canal", render: (row) => row.channelName ?? "—", sortable: false },
  {
    key: "quantity",
    header: "Volume",
    align: "right",
    render: (row) => formatDecimal(row.totalQuantity),
    sortable: false,
  },
  {
    key: "share",
    header: "% Volume",
    align: "right",
    render: (row) => (row.volumeShare === null ? "—" : formatPercent(row.volumeShare)),
    sortable: false,
  },
];

interface BattleshipWizardProps {
  mode: "volume" | "positivation";
  title: string;
  description: string;
}

/**
 * Shared wizard for both Batalha Naval models — the flow is identical, only
 * the ranking metric (step 2) and the distribution rule (proportional vs
 * linear) change.
 */
export function BattleshipWizard({ mode, title, description }: BattleshipWizardProps) {
  // Both models rank the chart by positivação (Planificador.xlsx, confirmed by
  // Eduardo on 06/08/2026); what changes between them is the distribution rule.
  const metric: PlannerTopSkuMetric = "positivation";
  const scope = usePlannerScope();
  const queryClient = useQueryClient();
  const { showToast } = useToast();

  const [referenceMonth, setReferenceMonth] = useState("");
  const [channelId, setChannelId] = useState("");
  const [extraProductIds, setExtraProductIds] = useState<string[]>([]);
  const [referenceProductId, setReferenceProductId] = useState("");
  const [targetMonth, setTargetMonth] = useState("");
  const [weeks, setWeeks] = useState<PlannerWeekInput[]>([]);
  const [result, setResult] = useState<PlannerGenerationResult | null>(null);
  const [exportParams, setExportParams] = useState<Record<string, unknown>>({});

  const referenceMonthOptions = useMemo(() => buildReferenceMonthOptions(new Date()), []);
  const channelIds = channelId ? [channelId] : undefined;

  const { data: topSkus, isLoading: isTopSkusLoading } = useQuery({
    queryKey: ["planner-top-skus", referenceMonth, metric, channelId, extraProductIds, scope.distributorId],
    queryFn: () =>
      fetchPlannerTopSkus(referenceMonth, metric, channelIds, extraProductIds, scope.distributorId),
    enabled: Boolean(referenceMonth),
  });

  const { data: participation, isLoading: isParticipationLoading } = useQuery({
    queryKey: ["planner-sku-participation", referenceMonth, referenceProductId, channelId, scope.distributorId],
    queryFn: () =>
      fetchPlannerSkuParticipation(referenceMonth, referenceProductId, channelIds, scope.distributorId),
    enabled: Boolean(referenceMonth) && Boolean(referenceProductId),
  });

  const { data: targetMonths } = useQuery({
    queryKey: ["planner-target-months", scope.distributorId],
    queryFn: () => fetchPlannerTargetMonths(scope.distributorId),
  });

  const { data: routeSummary } = useQuery({
    queryKey: ["planner-route-summary", scope.distributorId],
    queryFn: () => fetchPlannerRouteSummary(scope.distributorId),
  });

  const generateMutation = useMutation({
    mutationFn: generateBattleshipPlan,
    onSuccess: (generated, variables) => {
      setResult(generated);
      // Snapshot of the inputs actually used, so later form edits never leak
      // into the export ("exportações indicam os parâmetros usados").
      setExportParams({
        Planificador: formatPlanCode(generated.code),
        Modelo: title,
        Versão: generated.version,
        "Mês de referência": variables.referenceMonth,
        "SKU de referência":
          (topSkus ?? []).find((sku) => sku.productId === variables.referenceProductId)
            ?.productName ?? variables.referenceProductId,
        Canal:
          scope.filterOptions?.channels.find(
            (channel) => channel.id === variables.channelIds?.[0],
          )?.name ?? "Todos",
        "Mês da meta": variables.targetMonth,
        Semanas: variables.weeks
          .map((week) => `S${week.weekNumber} ${week.startDate}..${week.endDate}`)
          .join(" | "),
        "Volume alocado": generated.allocatedQuantity ?? "",
        "Meta das semanas": generated.weekTargetQuantity ?? "",
      });
      queryClient.invalidateQueries({ queryKey: ["planner-plans"] });
      showToast(
        "success",
        `Planificador ${formatPlanCode(generated.code)} gerado com ${generated.lineCount} linhas.`,
      );
    },
    onError: (error) => showToast("error", resolvePlannerErrorMessage(error)),
  });

  function handleTargetMonthChange(monthStart: string) {
    setTargetMonth(monthStart);
    setResult(null);
    if (monthStart && routeSummary) {
      setWeeks(buildDefaultWeeks(monthStart, routeSummary.weekCount));
    } else {
      setWeeks([]);
    }
  }

  // The month can be picked before the route summary loads; fill the weeks in
  // as soon as the route arrives instead of forcing a re-selection.
  useEffect(() => {
    if (targetMonth && routeSummary && weeks.length === 0) {
      setWeeks(buildDefaultWeeks(targetMonth, routeSummary.weekCount));
    }
  }, [targetMonth, routeSummary, weeks.length]);

  const skuOptions = (topSkus ?? []).map((sku) => ({
    value: sku.productId,
    label: sku.isExtra ? `${sku.productName} (adicionado)` : sku.productName,
  }));
  const extraOptions = (scope.filterOptions?.products ?? []).map((product) => ({
    value: product.id,
    label: product.name,
  }));
  const canGenerate =
    Boolean(referenceMonth) &&
    Boolean(referenceProductId) &&
    Boolean(targetMonth) &&
    weeks.length > 0 &&
    !generateMutation.isPending;

  return (
    <div>
      <PageHeader title={title} description={description} />

      <div className="card mb-5 grid gap-4 p-4">
        <div className="grid gap-3 md:grid-cols-3">
          <PlannerDistributorField scope={scope} />
          <SelectField
            label="Passo 1 — Mês de referência"
            allLabel="Selecione o mês"
            value={referenceMonth}
            onChange={(event) => {
              setReferenceMonth(event.target.value);
              setReferenceProductId("");
              setResult(null);
            }}
            options={referenceMonthOptions}
          />
          <SelectField
            label="Canal"
            value={channelId}
            onChange={(event) => {
              // The ranking changes with the channel, so the previously picked
              // reference SKU may no longer be valid — force a new selection.
              setChannelId(event.target.value);
              setReferenceProductId("");
              setResult(null);
            }}
            options={(scope.filterOptions?.channels ?? []).map((channel) => ({
              value: channel.id,
              label: channel.name,
            }))}
          />
        </div>

        {referenceMonth ? (
          <div className="grid gap-3">
            <div className="flex flex-wrap items-end justify-between gap-3">
              <h2 className="text-sm font-bold text-text1">
                Passo 2 — Top 5 SKUs por positivação em {formatMonthLabel(referenceMonth)}
              </h2>
              <MultiSelectField
                label="Adicionar SKUs ao gráfico (opcional)"
                options={extraOptions}
                values={extraProductIds}
                onChange={setExtraProductIds}
                allLabel="Nenhum"
                wrapperClassName="min-w-56"
              />
            </div>
            {isTopSkusLoading ? (
              <Skeleton className="h-64 w-full" />
            ) : (
              <TopSkuChart data={topSkus ?? []} metric={metric} />
            )}
            <SelectField
              label="Passo 3 — SKU de referência para desdobrar a meta"
              allLabel="Selecione o SKU"
              value={referenceProductId}
              onChange={(event) => {
                setReferenceProductId(event.target.value);
                setResult(null);
              }}
              options={skuOptions}
              wrapperClassName="max-w-md"
            />
          </div>
        ) : null}

        {referenceProductId ? (
          <div className="grid gap-2">
            <h2 className="text-sm font-bold text-text1">
              Passo 4 —{" "}
              {mode === "volume"
                ? "Participação de volume por PDV (peso aplicado sobre a meta)"
                : "PDVs que positivaram o SKU (a meta é distribuída de forma linear entre eles)"}
            </h2>
            {isParticipationLoading ? (
              <Skeleton className="h-40 w-full" />
            ) : (
              <DataTable
                columns={
                  mode === "volume"
                    ? PARTICIPATION_COLUMNS
                    : PARTICIPATION_COLUMNS.filter((column) => column.key !== "share")
                }
                rows={participation ?? []}
                rowKey={(row) => row.customerId}
                emptyMessage="Nenhuma venda do SKU no mês/canal selecionado"
              />
            )}
          </div>
        ) : null}

        {referenceProductId ? (
          <div className="grid gap-3">
            <h2 className="text-sm font-bold text-text1">
              Passo 5 — Meta e semanas (mesmo fluxo do Automático)
            </h2>
            {!routeSummary ? (
              <p className="text-xs text-text1">
                Nenhum roteiro de visitas importado. Configure em{" "}
                <Link
                  href="/planner/parametrizacao"
                  className="font-semibold text-blue underline"
                >
                  Planner › Parametrização
                </Link>
                .
              </p>
            ) : null}
            <SelectField
              label="Mês da meta"
              allLabel="Selecione o mês"
              value={targetMonth}
              onChange={(event) => handleTargetMonthChange(event.target.value)}
              options={(targetMonths ?? []).map((month) => ({
                value: month.monthStart,
                label: `${formatMonthLabel(month.monthStart)} · meta ${formatDecimal(month.totalQuantity)} un`,
              }))}
              wrapperClassName="max-w-md"
            />
            {targetMonths && targetMonths.length === 0 ? (
              <p className="text-xs text-text1">
                Nenhum mês com meta de Sell Out cadastrada (do mês atual em diante). Importe
                a Meta de Sell Out em Arquivos › Importação antes de gerar o planificador.
              </p>
            ) : null}
            {weeks.length > 0 ? (
              <WeekScheduleFields
                weeks={weeks}
                onChange={setWeeks}
                minDate={targetMonth}
                maxDate={getMonthEndIso(targetMonth)}
              />
            ) : null}
            <div>
              <Button
                disabled={!canGenerate}
                onClick={() =>
                  generateMutation.mutate({
                    mode,
                    referenceMonth,
                    referenceProductId,
                    targetMonth,
                    weeks,
                    channelIds,
                    distributorId: scope.distributorId,
                  })
                }
              >
                <Anchor size={14} />
                {generateMutation.isPending ? "Gerando..." : "Gerar planificador"}
              </Button>
            </div>
          </div>
        ) : null}
      </div>

      {result ? (
        <div className="grid gap-4">
          {result.weekTargetQuantity !== null &&
          result.allocatedQuantity !== null &&
          result.weekTargetQuantity - result.allocatedQuantity >
            ALLOCATION_GAP_TOLERANCE_UNITS ? (
            <div className="card border-yellow/40 bg-yellow/5 p-4 text-xs text-text1">
              Parte da meta não pôde ser alocada (
              {formatDecimal(result.weekTargetQuantity - result.allocatedQuantity)} un): há
              SKUs/semanas sem PDVs do universo de referência visitados.
            </div>
          ) : null}
          <PlanResultSection
            planId={result.planId}
            planCode={result.code}
            exportFileName={`planificador-batalha-naval-${mode}-${formatPlanCode(result.code)}`}
            exportParams={exportParams}
          />
        </div>
      ) : null}
    </div>
  );
}
