"use client";

import {
  Bar,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useTheme } from "@/components/theme-provider";
import { CHART_COLORS } from "@/lib/theme";
import {
  CategoricalChartFrame,
  formatCategoryTick,
} from "./categorical-chart-frame";

export interface ComboChartDatum {
  name: string;
  barValue: number;
  lineValue: number;
}

interface ComboChartProps {
  title: string;
  barLabel: string;
  lineLabel: string;
  data: ComboChartDatum[];
  formatBar: (value: number) => string;
  formatLine: (value: number) => string;
}

const CHART_HEIGHT = 240;
const MIN_ITEM_WIDTH = 64;

/**
 * Stacked bar+line chart with dual y axis, used by the monthly evolution
 * screen (e.g. Sell Out R$ × Positivação per week).
 */
export function ComboChart({
  title,
  barLabel,
  lineLabel,
  data,
  formatBar,
  formatLine,
}: ComboChartProps) {
  const { theme } = useTheme();
  const colors = CHART_COLORS[theme];

  return (
    <div className="card p-4">
      <h3 className="mb-3 text-sm font-bold text-text1">{title}</h3>
      <CategoricalChartFrame
        itemCount={data.length}
        height={CHART_HEIGHT}
        minItemWidth={MIN_ITEM_WIDTH}
        ariaLabel={title}
      >
        <ResponsiveContainer width="100%" height={CHART_HEIGHT}>
          <ComposedChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
            <CartesianGrid stroke={colors.grid} strokeDasharray="3 3" vertical={false} />
            <XAxis
              dataKey="name"
              tick={{ fill: colors.axisText, fontSize: 11 }}
              axisLine={{ stroke: colors.grid }}
              tickLine={false}
              interval={0}
              angle={-30}
              textAnchor="end"
              height={64}
              tickFormatter={formatCategoryTick}
            />
            <YAxis
              yAxisId="bar"
              tick={{ fill: colors.axisText, fontSize: 11 }}
              axisLine={false}
              tickLine={false}
              tickFormatter={formatBar}
              width={70}
            />
            <YAxis
              yAxisId="line"
              orientation="right"
              tick={{ fill: colors.axisText, fontSize: 11 }}
              axisLine={false}
              tickLine={false}
              tickFormatter={formatLine}
              width={64}
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
              formatter={(value: number, name: string) => [
                name === barLabel ? formatBar(value) : formatLine(value),
                name,
              ]}
            />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            <Bar
              yAxisId="bar"
              dataKey="barValue"
              name={barLabel}
              fill={colors.barPrimary}
              radius={[3, 3, 0, 0]}
              barSize={28}
            />
            <Line
              yAxisId="line"
              dataKey="lineValue"
              name={lineLabel}
              stroke={colors.lineAccent}
              strokeWidth={2}
              dot={{ fill: colors.lineAccent, r: 3 }}
            />
          </ComposedChart>
        </ResponsiveContainer>
      </CategoricalChartFrame>
    </div>
  );
}
