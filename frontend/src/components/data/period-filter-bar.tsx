"use client";

import { useQuery } from "@tanstack/react-query";
import { DateField, SelectField } from "@/components/ui/field";
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
}

/** Filter row shared by the consolidated data screens. */
export function PeriodFilterBar({
  filters,
  onChange,
  showDistributor = true,
}: PeriodFilterBarProps) {
  const { data: options } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  return (
    <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
      {showDistributor ? (
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
      <DateField
        label="Período Início"
        value={filters.start}
        onChange={(event) => onChange({ start: event.target.value })}
      />
      <DateField
        label="Período Fim"
        value={filters.end}
        onChange={(event) => onChange({ end: event.target.value })}
      />
    </div>
  );
}
