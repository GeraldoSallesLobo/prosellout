"use client";

import { useCallback, useEffect, useState } from "react";
import {
  getCurrentMonthToDate,
  getFullMonth,
  getPreviousMonth,
} from "@/lib/periods";
import type { ReportFilters } from "@/types/reports";

export interface ReportFilterState {
  currentStart: string;
  currentEnd: string;
  targetStart: string;
  targetEnd: string;
  previousStart: string;
  previousEnd: string;
  categoryId: string;
  subcategoryId: string;
  productId: string;
  channelId: string;
  clusterId: string;
  distributorId: string;
  salesRepId: string;
  unit: "currency" | "units";
}

const STORAGE_KEY = "prosellout-report-filters";

function buildDefaultState(): ReportFilterState {
  const currentPeriod = getCurrentMonthToDate();
  const targetPeriod = getFullMonth(new Date());
  const previousPeriod = getPreviousMonth();
  return {
    currentStart: currentPeriod.start,
    currentEnd: currentPeriod.end,
    targetStart: targetPeriod.start,
    targetEnd: targetPeriod.end,
    previousStart: previousPeriod.start,
    previousEnd: previousPeriod.end,
    categoryId: "",
    subcategoryId: "",
    productId: "",
    channelId: "",
    clusterId: "",
    distributorId: "",
    salesRepId: "",
    unit: "currency",
  };
}

function readStoredState(): ReportFilterState | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return { ...buildDefaultState(), ...(JSON.parse(raw) as Partial<ReportFilterState>) };
  } catch {
    return null;
  }
}

/**
 * Report filters persisted in the session (proposal UX improvement: the user
 * keeps period/grouping selections while navigating between reports).
 */
export function useReportFilters() {
  const [filters, setFiltersState] = useState<ReportFilterState>(buildDefaultState);
  const [isHydrated, setIsHydrated] = useState(false);

  useEffect(() => {
    const stored = readStoredState();
    if (stored) setFiltersState(stored);
    setIsHydrated(true);
  }, []);

  const setFilters = useCallback((patch: Partial<ReportFilterState>) => {
    setFiltersState((current) => {
      const next = { ...current, ...patch };
      try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      } catch {
        // Session storage unavailable (SSR/private mode): filters stay in memory.
      }
      return next;
    });
  }, []);

  return { filters, setFilters, isHydrated };
}

/** Converts UI state to the repository/RPC filter contract. */
export function toReportFilters(state: ReportFilterState): ReportFilters {
  return {
    currentStart: state.currentStart,
    currentEnd: state.currentEnd,
    previousStart: state.previousStart,
    previousEnd: state.previousEnd,
    targetStart: state.targetStart || undefined,
    targetEnd: state.targetEnd || undefined,
    distributorId: state.distributorId || undefined,
    categoryId: state.categoryId || undefined,
    subcategoryId: state.subcategoryId || undefined,
    productId: state.productId || undefined,
    channelId: state.channelId || undefined,
    clusterId: state.clusterId || undefined,
    salesRepId: state.salesRepId || undefined,
  };
}
