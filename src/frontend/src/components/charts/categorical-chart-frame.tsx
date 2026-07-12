"use client";

import type { ReactNode } from "react";

interface CategoricalChartFrameProps {
  children: ReactNode;
  itemCount: number;
  height: number;
  minItemWidth?: number;
  minWidth?: number;
  ariaLabel: string;
}

const DEFAULT_MIN_ITEM_WIDTH = 72;
const DEFAULT_MIN_WIDTH = 640;
const TICK_LABEL_MAX_LENGTH = 18;

function getChartWidth(
  itemCount: number,
  minItemWidth: number,
  minWidth: number,
): number {
  return Math.max(minWidth, itemCount * minItemWidth);
}

export function formatCategoryTick(value: unknown): string {
  const label = String(value ?? "");
  if (label.length <= TICK_LABEL_MAX_LENGTH) return label;
  return `${label.slice(0, TICK_LABEL_MAX_LENGTH - 3)}...`;
}

export function CategoricalChartFrame({
  children,
  itemCount,
  height,
  minItemWidth = DEFAULT_MIN_ITEM_WIDTH,
  minWidth = DEFAULT_MIN_WIDTH,
  ariaLabel,
}: CategoricalChartFrameProps) {
  const width = getChartWidth(itemCount, minItemWidth, minWidth);

  return (
    <div
      className="overflow-x-auto overflow-y-hidden pb-2"
      aria-label={ariaLabel}
      role="region"
      tabIndex={0}
    >
      <div style={{ minWidth: width, height }}>{children}</div>
    </div>
  );
}
