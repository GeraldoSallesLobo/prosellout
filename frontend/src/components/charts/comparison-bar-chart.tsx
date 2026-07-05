"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatCompactCurrency } from "@/lib/format";
import { useTheme } from "@/components/theme-provider";
import { CHART_COLORS } from "@/lib/theme";

export interface ComparisonBarDatum {
  name: string;
  current: number;
  target: number | null;
  previous: number;
}

const CHART_HEIGHT = 280;

/** Footer chart of the MTD screen: current vs target vs previous per group. */
export function ComparisonBarChart({ data }: { data: ComparisonBarDatum[] }) {
  const { theme } = useTheme();
  const colors = CHART_COLORS[theme];

  return (
    <ResponsiveContainer width="100%" height={CHART_HEIGHT}>
      <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
        <CartesianGrid stroke={colors.grid} strokeDasharray="3 3" vertical={false} />
        <XAxis
          dataKey="name"
          tick={{ fill: colors.axisText, fontSize: 11 }}
          axisLine={{ stroke: colors.grid }}
          tickLine={false}
          interval={0}
          angle={-15}
          textAnchor="end"
          height={48}
        />
        <YAxis
          tick={{ fill: colors.axisText, fontSize: 11 }}
          axisLine={false}
          tickLine={false}
          tickFormatter={(value: number) => formatCompactCurrency(value)}
          width={72}
        />
        <Tooltip
          cursor={{ fill: colors.cursor }}
          contentStyle={{
            background: colors.tooltipBg,
            border: `1px solid ${colors.tooltipBorder}`,
            borderRadius: 8,
            fontSize: 12,
          }}
          labelStyle={{ color: colors.tooltipText }}
          formatter={(value: number, name: string) => [formatCompactCurrency(value), name]}
        />
        <Legend wrapperStyle={{ fontSize: 12, color: colors.axisText }} />
        <Bar
          dataKey="current"
          name="Período Atual"
          fill={colors.seriesCurrent}
          radius={[3, 3, 0, 0]}
        />
        <Bar
          dataKey="target"
          name="Meta"
          fill={colors.seriesTarget}
          radius={[3, 3, 0, 0]}
        />
        <Bar
          dataKey="previous"
          name="Período Anterior"
          fill={colors.seriesPrevious}
          radius={[3, 3, 0, 0]}
        />
      </BarChart>
    </ResponsiveContainer>
  );
}
