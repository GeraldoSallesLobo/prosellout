"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useIndustryScope } from "@/components/access/industry-provider";
import { SelectField } from "@/components/ui/field";
import { useFilterOptions } from "@/hooks/use-filter-options";
import { CURRENT_USER_ACCESS_QUERY_KEY, fetchCurrentUserAccess } from "@/lib/data/access";
import type { FilterOptions } from "@/types/reports";

export interface PlannerScope {
  isAdmin: boolean;
  /** Admins pick a distributor explicitly; other users get the industry in scope. */
  distributorId: string | undefined;
  setDistributorId: (value: string) => void;
  filterOptions: FilterOptions | undefined;
}

/** Shared scope state for planner screens: distributor in scope + filter options. */
export function usePlannerScope(): PlannerScope {
  const [adminDistributorId, setAdminDistributorId] = useState("");
  const { selectedDistributorId } = useIndustryScope();

  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const { data: filterOptions } = useFilterOptions();

  const isAdmin = access?.isAdmin === true;

  return {
    isAdmin,
    distributorId: isAdmin
      ? adminDistributorId || undefined
      : selectedDistributorId ?? undefined,
    setDistributorId: setAdminDistributorId,
    filterOptions,
  };
}

/** Distributor selector, visible only to platform admins (same rule as reports). */
export function PlannerDistributorField({ scope }: { scope: PlannerScope }) {
  if (!scope.isAdmin) return null;
  return (
    <SelectField
      label="Distribuidora"
      allLabel="Selecione"
      value={scope.distributorId ?? ""}
      onChange={(event) => scope.setDistributorId(event.target.value)}
      options={(scope.filterOptions?.distributors ?? []).map((option) => ({
        value: option.id,
        label: option.name,
      }))}
    />
  );
}
