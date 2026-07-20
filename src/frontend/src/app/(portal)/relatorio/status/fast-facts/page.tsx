"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { TrendingDown, TrendingUp } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { ExportButton } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { useReportFilters, toReportFilters } from "@/hooks/use-report-filters";
import { fetchFastFacts } from "@/lib/data/reports";
import {
  formatCurrency,
  formatInteger,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import type { FastFactsDimension, FastFactsHighlight } from "@/types/reports";

const DIMENSION_LABELS: Record<string, string> = {
  seller: "Vendedores",
  supervisor: "Supervisores",
  product: "SKU",
  category: "Categorias",
  channel: "Canais",
  customer: "Clientes",
};

const DIMENSION_SINGULAR_LABELS: Record<string, string> = {
  seller: "vendedor",
  supervisor: "supervisor",
  product: "SKU",
  category: "categoria",
  channel: "canal",
  customer: "cliente",
};

const DIMENSION_ORDER = ["seller", "supervisor", "product", "category", "channel", "customer"];
const DONUT_SIZE = 92;
const DONUT_STROKE_WIDTH = 10;

function VariationValue({ value }: { value: number | null }) {
  if (value === null) return <span className="font-semibold text-text2">—</span>;

  return (
    <span className={clsx("font-semibold", value >= 0 ? "text-green" : "text-red")}>
      {formatVariation(value)}
    </span>
  );
}

function AchievementDonut({ facts }: { facts: FastFactsDimension }) {
  const achievedRate = facts.eligibleCount > 0
    ? Math.min(1, Math.max(0, facts.achievedCount / facts.eligibleCount))
    : null;
  const radius = (DONUT_SIZE - DONUT_STROKE_WIDTH) / 2;
  const circumference = 2 * Math.PI * radius;
  const greenDashOffset = circumference * (1 - (achievedRate ?? 0));
  const missedCount = Math.max(facts.notAchievedCount, facts.eligibleCount - facts.achievedCount);

  return (
    <div className="flex w-[116px] shrink-0 flex-col items-center gap-2">
      <div className="relative" style={{ width: DONUT_SIZE, height: DONUT_SIZE }}>
        <svg width={DONUT_SIZE} height={DONUT_SIZE} className="-rotate-90">
          <circle
            cx={DONUT_SIZE / 2}
            cy={DONUT_SIZE / 2}
            r={radius}
            fill="none"
            className={facts.eligibleCount > 0 ? "stroke-red" : "stroke-bg3"}
            strokeWidth={DONUT_STROKE_WIDTH}
          />
          {facts.eligibleCount > 0 ? (
            <circle
              cx={DONUT_SIZE / 2}
              cy={DONUT_SIZE / 2}
              r={radius}
              fill="none"
              className="stroke-green"
              strokeWidth={DONUT_STROKE_WIDTH}
              strokeDasharray={circumference}
              strokeDashoffset={greenDashOffset}
            />
          ) : null}
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center leading-none">
          <span className="text-sm font-extrabold text-text1">
            {facts.eligibleCount > 0
              ? `${formatInteger(facts.achievedCount)}/${formatInteger(facts.eligibleCount)}`
              : "—"}
          </span>
          <span className="mt-1 text-[10px] font-semibold text-text2">
            {formatPercent(facts.achievedPct)}
          </span>
        </div>
      </div>
      <div className="grid w-full gap-1 text-[11px] leading-tight text-text2">
        <span className="flex items-center justify-center gap-1">
          <span className="h-2 w-2 rounded-full bg-green" />
          {formatInteger(facts.achievedCount)} na meta
        </span>
        <span className="flex items-center justify-center gap-1">
          <span className="h-2 w-2 rounded-full bg-red" />
          {formatInteger(missedCount)} abaixo
        </span>
      </div>
    </div>
  );
}

function HighlightSummary({
  type,
  dimension,
  highlight,
}: {
  type: "best" | "worst";
  dimension: string;
  highlight: FastFactsHighlight | null;
}) {
  const isBest = type === "best";
  const Icon = isBest ? TrendingUp : TrendingDown;
  const colorClassName = isBest ? "text-green" : "text-red";
  const labelPrefix = isBest ? "Melhor" : "Pior";
  const dimensionLabel = DIMENSION_SINGULAR_LABELS[dimension] ?? dimension;

  return (
    <div className="min-w-0 rounded-md bg-bg px-3 py-2">
      <div className="mb-1 flex items-center gap-1.5 text-[11px] font-semibold text-text2">
        <Icon size={13} className={colorClassName} />
        <span>{labelPrefix} {dimensionLabel}</span>
      </div>
      <div className="truncate text-sm font-bold text-text1" title={highlight?.name ?? undefined}>
        {highlight?.name ?? "—"}
      </div>
      <div className="mt-2 space-y-1 text-[11px]">
        <div className="flex items-center justify-between gap-2">
          <span className="text-text2">Realizado</span>
          <span className="text-right font-semibold text-text1">
            {formatCurrency(highlight?.currentValue)}
          </span>
        </div>
        <div className="flex items-center justify-between gap-2">
          <span className="text-text2">vs Meta</span>
          <VariationValue value={highlight?.currentVsTarget ?? null} />
        </div>
        <div className="flex items-center justify-between gap-2">
          <span className="text-text2">vs AA</span>
          <VariationValue value={highlight?.currentVsPrevious ?? null} />
        </div>
      </div>
    </div>
  );
}

function FastFactsCard({ facts }: { facts: FastFactsDimension }) {
  return (
    <div className="card flex flex-col gap-4 p-4">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-bold text-text1">
          {DIMENSION_LABELS[facts.dimension] ?? facts.dimension}
        </h3>
        <span className="rounded-full border border-line bg-bg3 px-2.5 py-0.5 text-[11px] font-semibold text-text2">
          {formatInteger(facts.eligibleCount)} avaliados
        </span>
      </div>

      <div className="grid gap-4 sm:grid-cols-[116px_minmax(0,1fr)]">
        <AchievementDonut facts={facts} />
        <div className="grid min-w-0 gap-2 lg:grid-cols-2">
          <HighlightSummary type="best" dimension={facts.dimension} highlight={facts.best} />
          <HighlightSummary type="worst" dimension={facts.dimension} highlight={facts.worst} />
        </div>
      </div>
    </div>
  );
}

export default function FastFactsPage() {
  const { filters, setFilters, isHydrated } = useReportFilters();
  const reportFilters = useMemo(() => toReportFilters(filters), [filters]);

  const { data: report, isLoading } = useQuery({
    queryKey: ["fast-facts", reportFilters],
    queryFn: () => fetchFastFacts(reportFilters),
    enabled: isHydrated,
  });

  const dimensions = DIMENSION_ORDER.map((key) => report?.[key]).filter(
    (facts): facts is FastFactsDimension => Boolean(facts),
  );

  return (
    <div>
      <PageHeader
        title="Análise de Fast Facts"
        description="Destaques do período: quem atingiu a meta, melhores e piores performances"
        actions={
          <ExportButton
            fileName="fast-facts"
            getRows={() =>
              dimensions.map((facts) => ({
                dimensao: DIMENSION_LABELS[facts.dimension] ?? facts.dimension,
                elegiveis: facts.eligibleCount,
                atingiram_meta: facts.achievedCount,
                nao_atingiram_meta: facts.notAchievedCount,
                pct_atingiram: facts.achievedPct,
                melhor: facts.best?.name,
                melhor_sell_out: facts.best?.currentValue,
                melhor_vs_meta: facts.best?.currentVsTarget,
                melhor_vs_ano_anterior: facts.best?.currentVsPrevious,
                pior: facts.worst?.name,
                pior_sell_out: facts.worst?.currentValue,
                pior_vs_meta: facts.worst?.currentVsTarget,
                pior_vs_ano_anterior: facts.worst?.currentVsPrevious,
              }))
            }
          />
        }
      />

      <ReportFilterBar
        filters={filters}
        onChange={setFilters}
        showDimensionFilters={false}
      />

      {isLoading || !report ? (
        <div className="grid grid-cols-1 gap-3 xl:grid-cols-2">
          {Array.from({ length: 6 }).map((_, index) => (
            <div key={index} className="card space-y-3 p-4">
              <Skeleton className="h-4 w-28" />
              <Skeleton className="h-20 w-full" />
            </div>
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 xl:grid-cols-2">
          {dimensions.map((facts) => (
            <FastFactsCard key={facts.dimension} facts={facts} />
          ))}
        </div>
      )}
    </div>
  );
}
