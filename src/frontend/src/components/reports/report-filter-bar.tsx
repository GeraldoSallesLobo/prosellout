"use client";

import { useQuery } from "@tanstack/react-query";
import { DateField, SelectField } from "@/components/ui/field";
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
              label="Anterior Início"
              value={filters.previousStart}
              onChange={(event) => onChange({ previousStart: event.target.value })}
            />
            <DateField
              label="Anterior Fim"
              value={filters.previousEnd}
              onChange={(event) => onChange({ previousEnd: event.target.value })}
            />
          </>
        ) : null}
      </div>

      {showDimensionFilters ? (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
          <SelectField
            label="Categoria"
            options={toSelectOptions(options.categories)}
            value={filters.categoryId}
            onChange={(event) => onChange({ categoryId: event.target.value })}
          />
          <SelectField
            label="SubCategoria"
            options={toSelectOptions(options.subcategories)}
            value={filters.subcategoryId}
            onChange={(event) => onChange({ subcategoryId: event.target.value })}
          />
          <SelectField
            label="SKU"
            options={toSelectOptions(options.products)}
            value={filters.productId}
            onChange={(event) => onChange({ productId: event.target.value })}
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
          <SelectField
            label="Canal"
            options={toSelectOptions(options.channels)}
            value={filters.channelId}
            onChange={(event) => onChange({ channelId: event.target.value })}
          />
          <SelectField
            label="Cluster"
            options={toSelectOptions(options.clusters)}
            value={filters.clusterId}
            onChange={(event) => onChange({ clusterId: event.target.value })}
          />
        </div>
      ) : null}
    </div>
  );
}
