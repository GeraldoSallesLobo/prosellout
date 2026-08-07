"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Download, Upload } from "lucide-react";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SelectField } from "@/components/ui/field";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { fetchPlannerRouteSummary } from "@/lib/data/planner";
import { formatInteger, formatIsoDateTime } from "@/lib/format";
import { buildRouteTemplateCsv, PLANNER_WEEK_COUNT_OPTIONS } from "@/lib/planner";

const DEFAULT_WEEK_COUNT = 4;

function downloadRouteTemplate(weekCount: number) {
  const csv = buildRouteTemplateCsv(weekCount);
  const blob = new Blob([`﻿${csv}`], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `roteiro-visitas-${weekCount}-semanas.csv`;
  anchor.click();
  URL.revokeObjectURL(url);
}

export default function PlannerParametrizacaoPage() {
  const scope = usePlannerScope();
  const [weekCount, setWeekCount] = useState(DEFAULT_WEEK_COUNT);

  const { data: routeSummary, isLoading } = useQuery({
    queryKey: ["planner-route-summary", scope.distributorId],
    queryFn: () => fetchPlannerRouteSummary(scope.distributorId),
  });

  return (
    <div>
      <PageHeader
        title="Parametrização do Roteirizador"
        description="Etapa inicial de todos os planificadores: escolha das semanas e importação do roteiro de visitas."
      />

      <div className="mb-5 grid gap-4 lg:grid-cols-2">
        <div className="card grid content-start gap-3 p-4">
          <h2 className="text-sm font-bold text-text1">Passo 1 — Semanas do mês</h2>
          <p className="text-xs text-text2">
            Escolha em quantas semanas a meta do mês será distribuída. O mês pode ter 5
            semanas de calendário e, mesmo assim, a venda pode ser concentrada em menos
            semanas.
          </p>
          <div className="grid grid-cols-2 items-end gap-3">
            <SelectField
              label="Quantidade de semanas"
              allLabel="Selecione"
              value={String(weekCount)}
              onChange={(event) => setWeekCount(Number(event.target.value))}
              options={PLANNER_WEEK_COUNT_OPTIONS.map((count) => ({
                value: String(count),
                label: `${count} semanas`,
              }))}
            />
            <Button variant="secondary" onClick={() => downloadRouteTemplate(weekCount)}>
              <Download size={14} />
              Baixar modelo ({weekCount} semanas)
            </Button>
          </div>
        </div>

        <div className="card grid content-start gap-3 p-4">
          <h2 className="text-sm font-bold text-text1">Passo 2 — Importar o roteiro</h2>
          <p className="text-xs text-text2">
            Preencha o modelo com o planejamento de visitas do mês inteiro, aberto por
            semana: cada linha é um PDV com o vendedor responsável e um “x” nas semanas em
            que será visitado. Mais de uma marcação na mesma semana conta como 1
            visita/semana; visitas em mais de uma semana são permitidas.
          </p>
          <p className="text-xs text-text2">
            A importação usa o tipo <strong>Roteiro de Visitas (Planner)</strong> na tela
            de Importação. Um vídeo/tutorial do passo a passo ficará disponível aqui; em
            caso de dúvida, agende um alinhamento com o time ProSellOut (parte do setup).
          </p>
          <div>
            <Link href="/arquivos/importacao">
              <Button>
                <Upload size={14} />
                Ir para Importação
              </Button>
            </Link>
          </div>
        </div>
      </div>

      <div className="card grid gap-3 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <h2 className="text-sm font-bold text-text1">Roteiro vigente</h2>
          <PlannerDistributorField scope={scope} />
        </div>
        {isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : !routeSummary ? (
          <p className="text-sm text-text2">
            Nenhum roteiro importado ainda. Os modelos Automático e Batalha Naval dependem
            do roteiro de visitas.
          </p>
        ) : (
          <div className="grid gap-3">
            <div className="flex flex-wrap items-center gap-2 text-xs text-text2">
              <Badge variant="blue">{routeSummary.weekCount} semanas</Badge>
              <span>
                Importado em {formatIsoDateTime(routeSummary.importedAt)}
                {routeSummary.fileName ? ` · ${routeSummary.fileName}` : ""}
              </span>
            </div>
            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              <SummaryStat label="Visitas" value={formatInteger(routeSummary.totalVisits)} />
              <SummaryStat
                label="PDVs no roteiro"
                value={formatInteger(routeSummary.totalCustomers)}
              />
              <SummaryStat
                label="Vendedores"
                value={formatInteger(routeSummary.totalSellers)}
              />
              <SummaryStat label="Semanas" value={String(routeSummary.weekCount)} />
            </div>
            <div className="flex flex-wrap gap-2">
              {routeSummary.weeks.map((week) => (
                <span
                  key={week.weekNumber}
                  className="rounded-md border border-line bg-bg px-3 py-1.5 text-xs text-text2"
                >
                  Semana {week.weekNumber}:{" "}
                  <strong className="text-text1">{formatInteger(week.visitCount)}</strong>{" "}
                  visitas
                </span>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function SummaryStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-line bg-bg px-3 py-2">
      <div className="text-[11px] font-bold uppercase tracking-wide text-text2">{label}</div>
      <div className="text-lg font-bold text-text1">{value}</div>
    </div>
  );
}
