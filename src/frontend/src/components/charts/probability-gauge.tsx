import { formatPercent } from "@/lib/format";

interface ProbabilityGaugeProps {
  value: number | null;
  label: string;
  size?: number;
}

const DEFAULT_SIZE = 84;
const STROKE_WIDTH = 7;
const HIGH_THRESHOLD = 0.7;
const MEDIUM_THRESHOLD = 0.4;

/** Tailwind stroke classes resolve to theme CSS variables, so the gauge follows the active theme. */
function gaugeColorClass(value: number): string {
  if (value >= HIGH_THRESHOLD) return "stroke-green";
  if (value >= MEDIUM_THRESHOLD) return "stroke-yellow";
  return "stroke-red";
}

/** Circular probability meter used by Fast Facts and the MTD probability KPIs. */
export function ProbabilityGauge({ value, label, size = DEFAULT_SIZE }: ProbabilityGaugeProps) {
  // The arc is clamped to [0,1]; the centre label shows the true ratio, which
  // can exceed 100% (Prob. = realizado / meta, per the calculation reference).
  const arcValue = Math.min(1, Math.max(0, value ?? 0));
  const radius = (size - STROKE_WIDTH) / 2;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - arcValue);
  const colorClass = gaugeColorClass(arcValue);

  return (
    <div className="flex flex-col items-center gap-2">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="-rotate-90">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="none"
            className="stroke-bg3"
            strokeWidth={STROKE_WIDTH}
          />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="none"
            className={colorClass}
            strokeWidth={STROKE_WIDTH}
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={dashOffset}
          />
        </svg>
        <div className="absolute inset-0 flex items-center justify-center text-sm font-extrabold text-text1">
          {value === null ? "—" : formatPercent(value)}
        </div>
      </div>
      <span className="text-center text-[11px] leading-tight text-text2">{label}</span>
    </div>
  );
}
