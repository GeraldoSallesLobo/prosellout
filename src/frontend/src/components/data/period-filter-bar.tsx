"use client";

import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { useIndustryScope } from "@/components/access/industry-provider";
import { DateField, SelectField } from "@/components/ui/field";
import { useFilterOptions } from "@/hooks/use-filter-options";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";

export interface PeriodFilterState {
  start: string;
  end: string;
  distributorId: string;
}

interface PeriodFilterBarProps {
  filters: PeriodFilterState;
  onChange: (patch: Partial<PeriodFilterState>) => void;
  showDistributor?: boolean;
  showStartDate?: boolean;
  endDateLabel?: string;
}

/** Filter row shared by the consolidated data screens. */
export function PeriodFilterBar({
  filters,
  onChange,
  showDistributor = true,
  showStartDate = true,
  endDateLabel = "Período Fim",
}: PeriodFilterBarProps) {
  const { selectedDistributorId } = useIndustryScope();
  const { data: options } = useFilterOptions();
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const canFilterByDistributor = showDistributor && access?.isAdmin === true;

  // Distributor users always query the industry in scope, even when the
  // select is hidden; pages initialize the state with it and this effect
  // covers any leftover mismatch.
  const scopedDistributorId = selectedDistributorId ?? "";
  useEffect(() => {
    if (access && !access.isAdmin && filters.distributorId !== scopedDistributorId) {
      onChange({ distributorId: scopedDistributorId });
    }
  }, [access, filters.distributorId, onChange, scopedDistributorId]);

  return (
    <div
      className={clsx(
        "card mb-5 grid grid-cols-2 gap-3 p-4",
        canFilterByDistributor && showStartDate ? "md:grid-cols-4" : "md:grid-cols-2",
      )}
    >
      {canFilterByDistributor ? (
        <SelectField
          label="Distribuidora"
          options={(options?.distributors ?? []).map((option) => ({
            value: option.id,
            label: option.name,
          }))}
          value={filters.distributorId}
          onChange={(event) => onChange({ distributorId: event.target.value })}
        />
      ) : null}
      {showStartDate ? (
        <DateField
          label="Período Início"
          value={filters.start}
          onChange={(event) => onChange({ start: event.target.value })}
        />
      ) : null}
      <DateField
        label={endDateLabel}
        value={filters.end}
        onChange={(event) => onChange({ end: event.target.value })}
      />
    </div>
  );
}
