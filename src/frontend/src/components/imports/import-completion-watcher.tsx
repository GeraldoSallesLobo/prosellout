"use client";

import { useEffect, useRef } from "react";
import type { QueryKey } from "@tanstack/react-query";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ACTIVE_IMPORT_COUNT_QUERY_KEY,
  fetchActiveImportCount,
} from "@/lib/data/imports";

const ACTIVE_IMPORT_POLL_INTERVAL_MS = 2_000;

const IMPORT_COMPLETION_QUERY_KEYS_TO_INVALIDATE: QueryKey[] = [
  ["completed-import-codes"],
  ["filter-options"],
  ["customers"],
  ["sellers"],
  ["sell-out-rows"],
  ["sell-in-rows"],
  ["target-rows"],
  ["stock-rows"],
  ["product-hierarchy"],
  ["commercial-hierarchy"],
  ["status-mtd"],
  ["status-analysis"],
  ["status-analysis-full"],
  ["fast-facts"],
  ["three-month-history"],
  ["evolution-analysis"],
  ["evolution-weekly"],
];

/**
 * Mounted once in the portal shell so imports finishing in the background
 * refresh data/report caches regardless of which screen is open. Polls only
 * while at least one import is active; the upload flow wakes it by
 * invalidating ACTIVE_IMPORT_COUNT_QUERY_KEY.
 */
export function ImportCompletionWatcher() {
  const queryClient = useQueryClient();
  const hasSeenActiveImportRef = useRef(false);

  const { data: activeImportCount } = useQuery({
    queryKey: ACTIVE_IMPORT_COUNT_QUERY_KEY,
    queryFn: fetchActiveImportCount,
    refetchInterval: (query) =>
      (query.state.data ?? 0) > 0 ? ACTIVE_IMPORT_POLL_INTERVAL_MS : false,
  });

  useEffect(() => {
    if (activeImportCount === undefined) return;

    if (activeImportCount > 0) {
      hasSeenActiveImportRef.current = true;
      return;
    }

    if (!hasSeenActiveImportRef.current) return;

    hasSeenActiveImportRef.current = false;
    IMPORT_COMPLETION_QUERY_KEYS_TO_INVALIDATE.forEach((queryKey) => {
      queryClient.invalidateQueries({ queryKey });
    });
  }, [activeImportCount, queryClient]);

  return null;
}
