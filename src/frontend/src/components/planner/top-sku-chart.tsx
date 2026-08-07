"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useTheme } from "@/components/theme-provider";
import {
  CategoricalChartFrame,
  formatCategoryTick,
} from "@/components/charts/categorical-chart-frame";
import { formatInteger } from "@/lib/format";
import { CHART_COLORS } from "@/lib/theme";
import type { PlannerTopSku, PlannerTopSkuMetric } from "@/types/planner";

const CHART_HEIGHT = 260;
const MIN_ITEM_WIDTH = 96;

interface TopSkuChartProps {
  data: PlannerTopSku[];
  metric: PlannerTopSkuMetric;
}

/** Column chart of the best SKUs (Batalha Naval step 2). */
export function TopSkuChart({ data, metric }: TopSkuChartProps) {
  const { theme } = useTheme();
  const colors = CHART_COLORS[theme];

  const chartData = data.map((sku) => ({
    name: sku.isExtra ? `${sku.productName} (extra)` : sku.productName,
    value: metric === "volume" ? sku.totalQuantity : sku.positivation,
  }));

  return (
    <CategoricalChartFrame
      itemCount={chartData.length}
      height={CHART_HEIGHT}
      minItemWidth={MIN_ITEM_WIDTH}
      ariaLabel={
        metric === "volume"
          ? "Gráfico dos SKUs com maior volume"
          : "Gráfico dos SKUs com maior positivação"
      }
    >
      <ResponsiveContainer width="100%" height={CHART_HEIGHT}>
        <BarChart data={chartData} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <CartesianGrid stroke={colors.grid} strokeDasharray="3 3" vertical={false} />
          <XAxis
            dataKey="name"
            tick={{ fill: colors.axisText, fontSize: 11 }}
            axisLine={{ stroke: colors.grid }}
            tickLine={false}
            interval={0}
            angle={-25}
            textAnchor="end"
            height={64}
            tickFormatter={formatCategoryTick}
          />
          <YAxis
            tick={{ fill: colors.axisText, fontSize: 11 }}
            axisLine={false}
            tickLine={false}
            tickFormatter={(value: number) => formatInteger(value)}
          />
          <Tooltip
            cursor={{ fill: colors.cursor }}
            contentStyle={{
              backgroundColor: colors.tooltipBg,
              border: `1px solid ${colors.tooltipBorder}`,
              borderRadius: 8,
              color: colors.tooltipText,
              fontSize: 12,
            }}
            formatter={(value: number) => [
              formatInteger(value),
              metric === "volume" ? "Volume" : "Positivação",
            ]}
          />
          <Bar dataKey="value" fill={colors.barPrimary} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </CategoricalChartFrame>
  );
}
