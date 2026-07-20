"use client";

import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { DateField, SelectField } from "@/components/ui/field";
import { MultiSelectField } from "@/components/ui/multi-select-field";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { fetchFilterOptions } from "@/lib/data/reports";
import type { FilterOptions } from "@/types/reports";
import type { ReportFilterState } from "@/hooks/use-report-filters";

interface ReportFilterBarProps {
  filters: ReportFilterState;
  onChange: (patch: Partial<ReportFilterState>) => void;
  /** Which optional filter selects to display. */
  showDimensionFilters?: boolean;
  showTargetPeriod?: boolean;
  showPreviousPeriod?: boolean;
}

const EMPTY_OPTIONS: FilterOptions = {
  distributors: [],
  categories: [],
  subcategories: [],
  products: [],
  channels: [],
  clusters: [],
  sellers: [],
  supervisors: [],
};

function toSelectOptions(options: { id: string; name: string }[]) {
  return options.map((option) => ({ value: option.id, label: option.name }));
}

/**
 * Shared report filter bar: Período Atual / Meta / Período Anterior groups +
 * dimension filters, as specified for the MTD screen.
 */
export function ReportFilterBar({
  filters,
  onChange,
  showDimensionFilters = true,
  showTargetPeriod = true,
  showPreviousPeriod = true,
}: ReportFilterBarProps) {
  const { data: options = EMPTY_OPTIONS } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const canFilterByDistributor = access?.isAdmin === true;

  useEffect(() => {
    if (access && !access.isAdmin && filters.distributorId) {
      onChange({ distributorId: "" });
    }
  }, [access, filters.distributorId, onChange]);

  return (
    <div className="card mb-5 space-y-4 p-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        <DateField
          label="Período Início"
          value={filters.currentStart}
          onChange={(event) => onChange({ currentStart: event.target.value })}
        />
        <DateField
          label="Período Fim"
          value={filters.currentEnd}
          onChange={(event) => onChange({ currentEnd: event.target.value })}
        />
        {showTargetPeriod ? (
          <>
            <DateField
              label="Meta Início"
              value={filters.targetStart}
              onChange={(event) => onChange({ targetStart: event.target.value })}
            />
            <DateField
              label="Meta Fim"
              value={filters.targetEnd}
              onChange={(event) => onChange({ targetEnd: event.target.value })}
            />
          </>
        ) : null}
        {showPreviousPeriod ? (
          <>
            <DateField
              label="Ano Anterior Início"
              value={filters.previousStart}
              onChange={(event) => onChange({ previousStart: event.target.value })}
            />
            <DateField
              label="Ano Anterior Fim"
              value={filters.previousEnd}
              onChange={(event) => onChange({ previousEnd: event.target.value })}
            />
          </>
        ) : null}
      </div>

      {showDimensionFilters || canFilterByDistributor ? (
        <div
          className={clsx(
            "grid grid-cols-2 gap-3",
            showDimensionFilters ? "md:grid-cols-3" : "md:grid-cols-2",
            showDimensionFilters
              ? canFilterByDistributor
                ? "lg:grid-cols-4 xl:grid-cols-7"
                : "lg:grid-cols-6"
              : "lg:grid-cols-2",
          )}
        >
          {canFilterByDistributor ? (
            <SelectField
              label="Distribuidora"
              options={toSelectOptions(options.distributors)}
              value={filters.distributorId}
              onChange={(event) => onChange({ distributorId: event.target.value })}
            />
          ) : null}
          {showDimensionFilters ? (
            <>
              <MultiSelectField
                label="Categoria"
                options={toSelectOptions(options.categories)}
                values={filters.categoryIds}
                onChange={(categoryIds) => onChange({ categoryIds })}
              />
              <MultiSelectField
                label="SubCategoria"
                options={toSelectOptions(options.subcategories)}
                values={filters.subcategoryIds}
                onChange={(subcategoryIds) => onChange({ subcategoryIds })}
              />
              <MultiSelectField
                label="SKU"
                options={toSelectOptions(options.products)}
                values={filters.productIds}
                onChange={(productIds) => onChange({ productIds })}
              />
              <SelectField
                label="Unidade Medida"
                allLabel="R$"
                options={[{ value: "units", label: "Caixa" }]}
                value={filters.unit === "currency" ? "" : filters.unit}
                onChange={(event) =>
                  onChange({ unit: event.target.value === "units" ? "units" : "currency" })
                }
              />
              <MultiSelectField
                label="Canal"
                options={toSelectOptions(options.channels)}
                values={filters.channelIds}
                onChange={(channelIds) => onChange({ channelIds })}
              />
              <MultiSelectField
                label="Cluster"
                options={toSelectOptions(options.clusters)}
                values={filters.clusterIds}
                onChange={(clusterIds) => onChange({ clusterIds })}
              />
            </>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
