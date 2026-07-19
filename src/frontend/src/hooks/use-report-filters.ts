"use client";

import { useCallback, useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  getCurrentMonthToDate,
  getFullMonth,
  shiftDateRangeByYears,
} from "@/lib/periods";
import type { DateRange } from "@/lib/periods";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
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
const PREVIOUS_YEAR_OFFSET = -1;

function buildDefaultState(): ReportFilterState {
  const currentPeriod = getCurrentMonthToDate();
  const targetPeriod = getFullMonth(new Date());
  const previousPeriod = shiftDateRangeByYears(currentPeriod, PREVIOUS_YEAR_OFFSET);
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

function getPreviousYearRangeForCurrentPeriod(state: ReportFilterState): DateRange {
  return shiftDateRangeByYears(
    { start: state.currentStart, end: state.currentEnd },
    PREVIOUS_YEAR_OFFSET,
  );
}

function normalizePreviousPeriod(state: ReportFilterState): ReportFilterState {
  if (state.previousStart !== state.currentStart || state.previousEnd !== state.currentEnd) {
    return state;
  }

  const previousPeriod = getPreviousYearRangeForCurrentPeriod(state);
  return {
    ...state,
    previousStart: previousPeriod.start,
    previousEnd: previousPeriod.end,
  };
}

function shouldSyncPreviousPeriod(patch: Partial<ReportFilterState>): boolean {
  const hasCurrentPeriodChange = "currentStart" in patch || "currentEnd" in patch;
  const hasExplicitPreviousPeriodChange = "previousStart" in patch || "previousEnd" in patch;
  return hasCurrentPeriodChange && !hasExplicitPreviousPeriodChange;
}

function readStoredState(): ReportFilterState | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return normalizePreviousPeriod({
      ...buildDefaultState(),
      ...(JSON.parse(raw) as Partial<ReportFilterState>),
    });
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
  const [isStorageHydrated, setIsStorageHydrated] = useState(false);
  const { data: access, isLoading: isAccessLoading } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });

  useEffect(() => {
    const stored = readStoredState();
    if (stored) setFiltersState(stored);
    setIsStorageHydrated(true);
  }, []);

  const setFilters = useCallback((patch: Partial<ReportFilterState>) => {
    setFiltersState((current) => {
      let next = { ...current, ...patch };
      if (shouldSyncPreviousPeriod(patch)) {
        const previousPeriod = getPreviousYearRangeForCurrentPeriod(next);
        next = {
          ...next,
          previousStart: previousPeriod.start,
          previousEnd: previousPeriod.end,
        };
      }
      next = normalizePreviousPeriod(next);
      try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      } catch {
        // Session storage unavailable (SSR/private mode): filters stay in memory.
      }
      return next;
    });
  }, []);

  useEffect(() => {
    if (access && !access.isAdmin && filters.distributorId) {
      setFilters({ distributorId: "" });
    }
  }, [access, filters.distributorId, setFilters]);

  const hasResolvedDistributorScope = access?.isAdmin === true || !filters.distributorId;
  const isHydrated = isStorageHydrated && !isAccessLoading && hasResolvedDistributorScope;

  return { filters, setFilters, isHydrated };
}

/** Converts UI state to the repository/RPC filter contract. */
export function toReportFilters(state: ReportFilterState): ReportFilters {
  const normalizedState = normalizePreviousPeriod(state);
  return {
    currentStart: normalizedState.currentStart,
    currentEnd: normalizedState.currentEnd,
    previousStart: normalizedState.previousStart,
    previousEnd: normalizedState.previousEnd,
    targetStart: normalizedState.targetStart || undefined,
    targetEnd: normalizedState.targetEnd || undefined,
    distributorId: normalizedState.distributorId || undefined,
    categoryId: normalizedState.categoryId || undefined,
    subcategoryId: normalizedState.subcategoryId || undefined,
    productId: normalizedState.productId || undefined,
    channelId: normalizedState.channelId || undefined,
    clusterId: normalizedState.clusterId || undefined,
    salesRepId: normalizedState.salesRepId || undefined,
  };
}
