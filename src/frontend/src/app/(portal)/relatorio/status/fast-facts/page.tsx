"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { TrendingDown, TrendingUp } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { ExportButton } from "@/components/ui/export-button";
import { ReportFilterBar } from "@/components/reports/report-filter-bar";
import { ProbabilityGauge } from "@/components/charts/probability-gauge";
import { useReportFilters, toReportFilters } from "@/hooks/use-report-filters";
import { fetchFastFacts } from "@/lib/data/reports";
import { formatPercent, formatVariation } from "@/lib/format";
import type { FastFactsDimension } from "@/types/reports";

const DIMENSION_LABELS: Record<string, string> = {
  seller: "Vendedores",
  supervisor: "Supervisores",
  product: "SKU",
  category: "Categorias",
  channel: "Canais",
  customer: "Clientes",
};

const DIMENSION_ORDER = ["seller", "supervisor", "product", "category", "channel", "customer"];

function HighlightLine({
  icon: Icon,
  label,
  highlight,
  colorClassName,
}: {
  icon: typeof TrendingUp;
  label: string;
  highlight: FastFactsDimension["best"];
  colorClassName: string;
}) {
  return (
    <div className="flex items-start gap-2 text-xs">
      <Icon size={14} className={`${colorClassName} mt-0.5 shrink-0`} />
      <div className="min-w-0">
        <span className="text-text2">{label}: </span>
        <span className="font-semibold text-text1">{highlight?.name ?? "—"}</span>
        {highlight?.achievement !== null && highlight?.achievement !== undefined ? (
          <span className={`ml-1 font-semibold ${colorClassName}`}>
            {formatVariation(highlight.achievement - 1)}
          </span>
        ) : null}
      </div>
    </div>
  );
}

function FastFactsCard({ facts }: { facts: FastFactsDimension }) {
  return (
    <div className="card flex flex-col gap-3 p-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-bold text-text1">
          {DIMENSION_LABELS[facts.dimension] ?? facts.dimension}
        </h3>
        <span className="rounded-full border border-line bg-bg3 px-2.5 py-0.5 text-[11px] font-semibold text-text2">
          {facts.achievedCount}/{facts.eligibleCount} na meta
        </span>
      </div>

      <div className="flex items-center gap-4">
        <ProbabilityGauge
          value={facts.avgProbability}
          label="Prob. atingir meta"
          size={76}
        />
        <div className="min-w-0 flex-1 space-y-2">
          <div className="text-xs text-text2">
            Atingiram a meta:{" "}
            <span className="font-bold text-text1">{formatPercent(facts.achievedPct)}</span>
          </div>
          <HighlightLine
            icon={TrendingUp}
            label="Melhor"
            highlight={facts.best}
            colorClassName="text-green"
          />
          <HighlightLine
            icon={TrendingDown}
            label="Pior"
            highlight={facts.worst}
            colorClassName="text-red"
          />
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
                pct_atingiram: facts.achievedPct,
                probabilidade_media: facts.avgProbability,
                melhor: facts.best?.name,
                pior: facts.worst?.name,
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
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }).map((_, index) => (
            <div key={index} className="card space-y-3 p-4">
              <Skeleton className="h-4 w-28" />
              <Skeleton className="h-20 w-full" />
            </div>
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
          {dimensions.map((facts) => (
            <FastFactsCard key={facts.dimension} facts={facts} />
          ))}
        </div>
      )}
    </div>
  );
}
