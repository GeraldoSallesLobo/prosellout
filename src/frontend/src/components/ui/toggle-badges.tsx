"use client";

import clsx from "clsx";

export interface ToggleOption<T extends string> {
  value: T;
  label: string;
}

interface ToggleBadgesProps<T extends string> {
  options: ToggleOption<T>[];
  value: T;
  onChange: (value: T) => void;
}

/**
 * Badge-toggle from the proposal: consolidates sibling screens (same table,
 * different grouping) into a single page.
 */
export function ToggleBadges<T extends string>({
  options,
  value,
  onChange,
}: ToggleBadgesProps<T>) {
  return (
    <div className="flex flex-wrap gap-2">
      {options.map((option) => {
        const isActive = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => onChange(option.value)}
            className={clsx(
              "rounded-full border px-4 py-1.5 text-[13px] font-semibold transition-colors",
              isActive
                ? "border-accent2 bg-accent2/20 text-blue"
                : "border-line bg-bg3 text-text2 hover:border-blue/40 hover:text-text1",
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
