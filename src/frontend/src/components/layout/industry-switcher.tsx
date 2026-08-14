"use client";

import type { ReactElement } from "react";
import { Factory } from "lucide-react";
import { useIndustryScope } from "@/components/access/industry-provider";
import { INDUSTRY_LABELS } from "@/lib/industry";

/**
 * Header dropdown that switches the industry in scope. Rendered only for
 * distributor users linked to more than one industry; admins keep the
 * per-screen distributor filters instead.
 */
export function IndustrySwitcher(): ReactElement | null {
  const { distributors, selectedDistributorId, hasMultipleIndustries, selectIndustry } =
    useIndustryScope();

  if (!hasMultipleIndustries) return null;

  return (
    <label className="flex min-w-0 items-center gap-2">
      <Factory size={14} className="shrink-0 text-text2" aria-hidden />
      <select
        className="input-base h-8 w-auto max-w-[11rem] py-0 text-[13px] sm:max-w-[16rem]"
        value={selectedDistributorId ?? ""}
        onChange={(event) => selectIndustry(event.target.value)}
        aria-label={INDUSTRY_LABELS.switcherLabel}
        title={INDUSTRY_LABELS.switcherLabel}
      >
        {distributors.map((distributor) => (
          <option key={distributor.id} value={distributor.id}>
            {distributor.name}
          </option>
        ))}
      </select>
    </label>
  );
}
