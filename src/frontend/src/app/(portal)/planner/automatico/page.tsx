"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { RefreshCcw, Wand2 } from "lucide-react";
import { PlanResultSection } from "@/components/planner/plan-result-section";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { WeekScheduleFields } from "@/components/planner/week-schedule-fields";
import { Button } from "@/components/ui/button";
import { SelectField } from "@/components/ui/field";
import { PageHeader } from "@/components/ui/page-header";
import { useToast } from "@/components/ui/toast";
import {
  fetchPlannerRouteSummary,
  fetchPlannerTargetMonths,
  generateAutomaticPlan,
  recalculatePlanRoute,
} from "@/lib/data/planner";
import { formatDecimal } from "@/lib/format";
import { formatMonthLabel } from "@/lib/periods";
import {
  buildDefaultWeeks,
  formatPlanCode,
  getMonthEndIso,
  PLANNER_MODEL_LABELS,
  resolvePlannerErrorMessage,
} from "@/lib/planner";
import type { PlannerGenerationResult, PlannerWeekInput } from "@/types/planner";

const ALLOCATION_GAP_TOLERANCE_UNITS = 1;

function describeWeeks(weeks: PlannerWeekInput[]): string {
  return weeks
    .map((week) => `S${week.weekNumber} ${week.startDate}..${week.endDate}`)
    .join(" | ");
}

export default function PlannerAutomaticoPage() {
  const scope = usePlannerScope();
  const queryClient = useQueryClient();
  const { showToast } = useToast();

  const [targetMonth, setTargetMonth] = useState("");
  const [weeks, setWeeks] = useState<PlannerWeekInput[]>([]);
  const [result, setResult] = useState<PlannerGenerationResult | null>(null);
  const [exportParams, setExportParams] = useState<Record<string, unknown>>({});

  const { data: targetMonths } = useQuery({
    queryKey: ["planner-target-months", scope.distributorId],
    queryFn: () => fetchPlannerTargetMonths(scope.distributorId),
  });

  const { data: routeSummary, isLoading: isRouteLoading } = useQuery({
    queryKey: ["planner-route-summary", scope.distributorId],
    queryFn: () => fetchPlannerRouteSummary(scope.distributorId),
  });

  const monthOptions = useMemo(
    () =>
      (targetMonths ?? []).map((month) => ({
        value: month.monthStart,
        label: `${formatMonthLabel(month.monthStart)} · meta ${formatDecimal(month.totalQuantity)} un`,
      })),
    [targetMonths],
  );

  function handleMonthChange(monthStart: string) {
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

  const generateMutation = useMutation({
    mutationFn: generateAutomaticPlan,
    onSuccess: (generated, variables) => {
      setResult(generated);
      // Snapshot of the inputs actually used, so later form edits never leak
      // into the export ("exportações indicam os parâmetros usados").
      setExportParams({
        Planificador: formatPlanCode(generated.code),
        Modelo: PLANNER_MODEL_LABELS.automatic,
        Versão: generated.version,
        "Mês da meta": variables.targetMonth,
        Semanas: describeWeeks(variables.weeks),
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

  const recalculateMutation = useMutation({
    mutationFn: recalculatePlanRoute,
    onSuccess: (generated) => {
      setResult(generated);
      setExportParams((previous) => ({
        ...previous,
        Versão: generated.version,
        "Volume alocado": generated.allocatedQuantity ?? "",
        "Recalculado a partir da semana": generated.recalculatedFromWeek ?? "",
      }));
      queryClient.invalidateQueries({ queryKey: ["planner-plans"] });
      showToast(
        "success",
        `Rota recalculada: versão ${generated.version} a partir da semana ${generated.recalculatedFromWeek}.`,
      );
    },
    onError: (error) => showToast("error", resolvePlannerErrorMessage(error)),
  });

  const canGenerate = Boolean(targetMonth) && weeks.length > 0 && !generateMutation.isPending;
  const hasAllocationGap =
    result?.allocatedQuantity !== null &&
    result?.weekTargetQuantity !== null &&
    result !== null &&
    (result.weekTargetQuantity ?? 0) - (result.allocatedQuantity ?? 0) >
      ALLOCATION_GAP_TOLERANCE_UNITS;

  return (
    <div>
      <PageHeader
        title="Planificador Automático"
        description="Distribui a meta mensal de Sell Out (volume) por SKU × PDV × semana, com peso da mesma semana do ano anterior e fallback da média dos últimos 3 meses."
      />

      {!isRouteLoading && !routeSummary ? (
        <div className="card mb-5 border-yellow/40 bg-yellow/5 p-4 text-sm text-text1">
          Nenhum roteiro de visitas importado. Configure em{" "}
          <Link href="/planner/parametrizacao" className="font-semibold text-blue underline">
            Planner › Parametrização
          </Link>{" "}
          antes de gerar o planificador.
        </div>
      ) : null}

      <div className="card mb-5 grid gap-4 p-4">
        <div className="grid gap-3 md:grid-cols-3">
          <PlannerDistributorField scope={scope} />
          <SelectField
            label="Passo 1 — Mês da meta"
            allLabel="Selecione o mês"
            value={targetMonth}
            onChange={(event) => handleMonthChange(event.target.value)}
            options={monthOptions}
          />
        </div>
        {targetMonths && targetMonths.length === 0 ? (
          <p className="text-xs text-text1">
            Nenhum mês com meta de Sell Out cadastrada (do mês atual em diante). Importe a
            Meta de Sell Out em Arquivos › Importação antes de gerar o planificador.
          </p>
        ) : null}

        {targetMonth && weeks.length > 0 ? (
          <div className="grid gap-2">
            <h2 className="text-sm font-bold text-text1">
              Passo 2 — Datas das semanas ({routeSummary?.weekCount ?? weeks.length} semanas
              do roteiro)
            </h2>
            <p className="text-xs text-text2">
              Informe o início e o fim de cada semana (segunda a sexta, segunda a sábado,
              domingo a sábado…), sempre dentro do mês da meta. As datas são usadas para
              cruzar a meta diária por semana e depois comparar planejado × realizado.
            </p>
            <WeekScheduleFields
              weeks={weeks}
              onChange={setWeeks}
              minDate={targetMonth}
              maxDate={getMonthEndIso(targetMonth)}
            />
          </div>
        ) : null}

        <div className="flex flex-wrap items-center gap-3">
          <Button
            disabled={!canGenerate}
            onClick={() =>
              generateMutation.mutate({
                targetMonth,
                weeks,
                distributorId: scope.distributorId,
              })
            }
          >
            <Wand2 size={14} />
            {generateMutation.isPending ? "Gerando..." : "Passo 3 — Gerar planificador"}
          </Button>
          {result ? (
            <Button
              variant="secondary"
              disabled={recalculateMutation.isPending}
              onClick={() => recalculateMutation.mutate(result.planId)}
            >
              <RefreshCcw size={14} />
              {recalculateMutation.isPending ? "Recalculando..." : "Recalcular Rota"}
            </Button>
          ) : null}
        </div>
        {result ? (
          <p className="text-xs text-text2">
            Recalcular Rota (opcional): após o fim de cada semana, redistribui o saldo da
            meta (meta do mês − realizado) nas semanas restantes, substituindo o
            valor-objetivo sem alterar as visitas.
          </p>
        ) : null}
      </div>

      {result ? (
        <div className="grid gap-4">
          {hasAllocationGap ? (
            <div className="card border-yellow/40 bg-yellow/5 p-4 text-xs text-text1">
              Parte da meta não pôde ser alocada (
              {formatDecimal((result.weekTargetQuantity ?? 0) - (result.allocatedQuantity ?? 0))}{" "}
              un): há SKUs/semanas sem histórico de participação ou sem PDVs visitados.
            </div>
          ) : null}
          <PlanResultSection
            planId={result.planId}
            planCode={result.code}
            exportFileName={`planificador-automatico-${formatPlanCode(result.code)}`}
            exportParams={exportParams}
          />
        </div>
      ) : null}
    </div>
  );
}
