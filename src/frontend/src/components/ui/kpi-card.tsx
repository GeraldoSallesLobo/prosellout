import clsx from "clsx";
import { formatVariation } from "@/lib/format";
import type { KpiBlock } from "@/types/reports";

interface KpiCardProps {
  label: string;
  /** Formatted main value (current period). */
  value: string;
  /** Variation vs target (ratio, e.g. -0.6977). */
  vsTarget?: number | null;
  /** Variation vs previous period. */
  vsPrevious?: number | null;
  footer?: string;
}

function VariationLine({
  label,
  variation,
}: {
  label: string;
  variation: number | null | undefined;
}) {
  if (variation === null || variation === undefined) {
    return (
      <div className="text-xs text-text2">
        {label}: <span className="text-text2">—</span>
      </div>
    );
  }
  const isPositive = variation >= 0;
  return (
    <div className={clsx("text-xs font-semibold", isPositive ? "text-green" : "text-red")}>
      {isPositive ? "▲" : "▼"} {formatVariation(variation)}{" "}
      <span className="font-normal text-text2">{label}</span>
    </div>
  );
}

export function KpiCard({ label, value, vsTarget, vsPrevious, footer }: KpiCardProps) {
  return (
    <div className="card min-w-0 [container-type:inline-size] p-4">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-text2">
        {label}
      </div>
      <div className="mt-1.5 max-w-full break-words text-xl font-extrabold leading-tight text-text1 tabular-nums [font-size:clamp(1rem,10cqw,1.375rem)] [overflow-wrap:anywhere]">
        {value}
      </div>
      <div className="mt-1.5 space-y-0.5">
        {vsTarget !== undefined ? <VariationLine label="vs. meta" variation={vsTarget} /> : null}
        {vsPrevious !== undefined ? (
          <VariationLine label="vs. anterior" variation={vsPrevious} />
        ) : null}
        {footer ? <div className="text-xs text-text2">{footer}</div> : null}
      </div>
    </div>
  );
}

interface KpiBlockCardProps {
  label: string;
  block: KpiBlock;
  formatValue: (value: number | null) => string;
}

/** KPI card wired directly to a KpiBlock coming from report_status_mtd. */
export function KpiBlockCard({ label, block, formatValue }: KpiBlockCardProps) {
  return (
    <KpiCard
      label={label}
      value={formatValue(block.current)}
      vsTarget={block.currentVsTarget}
      vsPrevious={
        block.previous !== null && block.current !== null && block.previous !== 0
          ? block.current / block.previous - 1
          : null
      }
    />
  );
}
