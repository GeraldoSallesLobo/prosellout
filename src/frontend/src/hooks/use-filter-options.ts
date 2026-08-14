"use client";

import { useQuery } from "@tanstack/react-query";
import { useIndustryScope } from "@/components/access/industry-provider";
import { fetchFilterOptions } from "@/lib/data/reports";

/**
 * Filter options scoped to the selected industry for distributor users.
 * Admins keep the global catalog (selectedDistributorId is null for them).
 */
export function useFilterOptions() {
  const { selectedDistributorId } = useIndustryScope();
  return useQuery({
    queryKey: ["filter-options", selectedDistributorId],
    queryFn: () => fetchFilterOptions(selectedDistributorId ?? undefined),
  });
}
