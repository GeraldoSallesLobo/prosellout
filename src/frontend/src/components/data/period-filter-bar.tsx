"use client";

import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { DateField, SelectField } from "@/components/ui/field";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { fetchFilterOptions } from "@/lib/data/reports";

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
  const { data: options } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const canFilterByDistributor = showDistributor && access?.isAdmin === true;

  useEffect(() => {
    if (showDistributor && access && !access.isAdmin && filters.distributorId) {
      onChange({ distributorId: "" });
    }
  }, [access, filters.distributorId, onChange, showDistributor]);

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
