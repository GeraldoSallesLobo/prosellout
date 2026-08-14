"use client";

import clsx from "clsx";
import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import { fetchPlannerPlanWeekSummary } from "@/lib/data/planner";
import { formatCurrency, formatDecimal, formatIsoDate } from "@/lib/format";
import type { PlannerPlanWeek } from "@/types/planner";

/** Values come from numeric(14,3), so anything smaller is float noise. */
const CHANGE_TOLERANCE = 0.001;

interface WeekSeries {
  isQuantity: boolean;
  current: number | null;
  previous: number | null;
}

/**
 * Picks the unit of the week (volume or money) looking at both versions: a
 * week can end up with no lines after a recalculation, and its unit still has
 * to come from the version that does have them.
 */
function resolveSeries(week: PlannerPlanWeek): WeekSeries {
  const hasQuantity = week.quantity !== null || week.previousQuantity !== null;
  return hasQuantity
    ? { isQuantity: true, current: week.quantity, previous: week.previousQuantity }
    : { isQuantity: false, current: week.grossValue, previous: week.previousGrossValue };
}

function formatSeriesValue(series: WeekSeries, value: number): string {
  return series.isQuantity ? `${formatDecimal(value)} un` : formatCurrency(value);
}

/** Short range (01/08 – 08/08); the plan header already carries the year. */
function formatWeekRange(week: PlannerPlanWeek): string {
  const start = formatIsoDate(week.startDate).slice(0, 5);
  const end = formatIsoDate(week.endDate).slice(0, 5);
  return `${start} – ${end}`;
}

interface PlanWeekSummaryProps {
  planId: string;
}

/**
 * Weekly split of a generated plan: how the month's target landed on each week
 * and, after a Recalcular Rota, what changed against the previous version.
 * Renders nothing for models without weeks (Cobertura/Rentabilidade).
 */
export function PlanWeekSummary({ planId }: PlanWeekSummaryProps) {
  const { data: weeks } = useQuery({
    queryKey: ["planner-plan-weeks", planId],
    queryFn: () => fetchPlannerPlanWeekSummary(planId),
  });

  if (!weeks || weeks.length === 0) return null;

  const previousVersion = weeks[0].previousVersion;

  return (
    <div className="grid gap-2">
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="text-sm font-bold text-text1">Distribuição por semana</h3>
        {previousVersion === null ? null : (
          <span className="text-xs text-text2">comparado à v{previousVersion}</span>
        )}
      </div>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(min(100%,11rem),1fr))] gap-3">
        {weeks.map((week) => (
          <WeekCard key={week.weekNumber} week={week} />
        ))}
      </div>
    </div>
  );
}

function WeekCard({ week }: { week: PlannerPlanWeek }) {
  const series = resolveSeries(week);
  const hasPreviousVersion = week.previousVersion !== null;

  // With a previous version, an empty week means zero allocated (not unknown),
  // so the drop to zero — and the jump from zero — stay visible.
  const displayValue = series.current ?? (hasPreviousVersion ? 0 : null);
  const change = hasPreviousVersion
    ? (series.current ?? 0) - (series.previous ?? 0)
    : null;
  const hasChanged = change !== null && Math.abs(change) > CHANGE_TOLERANCE;

  const wasRecalculated =
    week.recalculatedFromWeek !== null && week.weekNumber >= week.recalculatedFromWeek;
  // A version built by Recalcular Rota is described by what it did to each
  // week; a first version is described by whether the week is still open.
  const label = hasPreviousVersion
    ? { text: wasRecalculated ? "Recalculada" : "Preservada", variant: wasRecalculated ? "blue" : "neutral" }
    : { text: week.isClosed ? "Fechada" : "Em aberto", variant: week.isClosed ? "neutral" : "blue" };

  return (
    <div
      className={clsx(
        "rounded-md border px-3 py-2.5",
        label.variant === "blue" ? "border-accent2/40 bg-bg" : "border-line bg-bg3/40",
      )}
    >
      <div className="mb-1 flex items-center justify-between gap-2">
        <span className="text-sm font-semibold text-text1">Semana {week.weekNumber}</span>
        <Badge variant={label.variant === "blue" ? "blue" : "neutral"}>{label.text}</Badge>
      </div>
      <div className="text-[11px] text-text2">{formatWeekRange(week)}</div>
      <div className="mt-1.5 text-lg font-bold text-text1">
        {displayValue === null ? "—" : formatSeriesValue(series, displayValue)}
      </div>
      {change === null ? null : hasChanged ? (
        // Redistribution is neither good nor bad, so no green/red here: the
        // arrow shows direction only.
        <div className="text-xs font-semibold text-text2">
          {change > 0 ? "▲" : "▼"} {formatSeriesValue(series, Math.abs(change))}
        </div>
      ) : (
        <div className="text-xs text-text2">sem alteração</div>
      )}
    </div>
  );
}
