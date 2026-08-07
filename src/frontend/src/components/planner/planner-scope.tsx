"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { SelectField } from "@/components/ui/field";
import { CURRENT_USER_ACCESS_QUERY_KEY, fetchCurrentUserAccess } from "@/lib/data/access";
import { fetchFilterOptions } from "@/lib/data/reports";
import type { FilterOptions } from "@/types/reports";

export interface PlannerScope {
  isAdmin: boolean;
  /** Explicit distributor for admins; undefined lets the DB resolve the user's own. */
  distributorId: string | undefined;
  setDistributorId: (value: string) => void;
  filterOptions: FilterOptions | undefined;
}

/** Shared scope state for planner screens: admin distributor + filter options. */
export function usePlannerScope(): PlannerScope {
  const [distributorId, setDistributorId] = useState("");

  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const { data: filterOptions } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  return {
    isAdmin: access?.isAdmin === true,
    distributorId: distributorId || undefined,
    setDistributorId,
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
