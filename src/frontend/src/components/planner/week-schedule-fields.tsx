"use client";

import { DateField } from "@/components/ui/field";
import type { PlannerWeekInput } from "@/types/planner";

interface WeekScheduleFieldsProps {
  weeks: PlannerWeekInput[];
  onChange: (weeks: PlannerWeekInput[]) => void;
  /** Pickers only offer dates inside the target month (Eduardo, 06/08/2026). */
  minDate?: string;
  maxDate?: string;
}

/**
 * Start/end date pair per week (Automático step 2). Distributors work
 * different week shapes (Mon-Fri, Mon-Sat, Sun-Sat), so the dates are free
 * inside the target month.
 */
export function WeekScheduleFields({ weeks, onChange, minDate, maxDate }: WeekScheduleFieldsProps) {
  function updateWeek(weekNumber: number, patch: Partial<PlannerWeekInput>) {
    onChange(
      weeks.map((week) =>
        week.weekNumber === weekNumber ? { ...week, ...patch } : week,
      ),
    );
  }

  return (
    <div className="grid gap-3">
      {weeks.map((week) => (
        <div key={week.weekNumber} className="grid grid-cols-[auto_1fr_1fr] items-end gap-3">
          <span className="pb-2 text-sm font-semibold text-text1">
            Semana {week.weekNumber}
          </span>
          <DateField
            label="Início"
            value={week.startDate}
            min={minDate}
            max={maxDate}
            onChange={(event) => updateWeek(week.weekNumber, { startDate: event.target.value })}
          />
          <DateField
            label="Fim"
            value={week.endDate}
            min={minDate}
            max={maxDate}
            onChange={(event) => updateWeek(week.weekNumber, { endDate: event.target.value })}
          />
        </div>
      ))}
    </div>
  );
}
