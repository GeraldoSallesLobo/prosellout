"use client";

import { useEffect, useId, useRef, useState } from "react";
import clsx from "clsx";
import { FieldWrapper, type SelectOption } from "./field";

interface MultiSelectFieldProps {
  label: string;
  options: SelectOption[];
  values: string[];
  onChange: (values: string[]) => void;
  /** Text shown in the trigger when nothing is selected. */
  allLabel?: string;
  /** Builds the trigger text when more than one option is selected. */
  getSummary?: (count: number) => string;
  /** Label for the action that clears the current selection. */
  clearLabel?: string;
  wrapperClassName?: string;
}

function defaultGetSummary(count: number): string {
  return `${count} selecionados`;
}

/**
 * Checkbox dropdown that lets the user pick several options at once.
 * Mirrors the footprint of {@link SelectField} so it drops into the same
 * filter grid, and closes on outside click or Escape.
 */
export function MultiSelectField({
  label,
  options,
  values,
  onChange,
  allLabel = "Todos",
  getSummary = defaultGetSummary,
  clearLabel = "Limpar",
  wrapperClassName,
}: MultiSelectFieldProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const panelId = useId();

  useEffect(() => {
    if (!isOpen) return;

    function handlePointerDown(event: MouseEvent) {
      if (!containerRef.current?.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setIsOpen(false);
    }

    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [isOpen]);

  function toggleValue(optionValue: string) {
    const isSelected = values.includes(optionValue);
    onChange(
      isSelected
        ? values.filter((value) => value !== optionValue)
        : [...values, optionValue],
    );
  }

  const selectedLabels = options
    .filter((option) => values.includes(option.value))
    .map((option) => option.label);

  const hasSelection = selectedLabels.length > 0;
  const summaryText = !hasSelection
    ? allLabel
    : selectedLabels.length === 1
      ? selectedLabels[0]
      : getSummary(selectedLabels.length);

  return (
    <FieldWrapper label={label} className={wrapperClassName}>
      <div ref={containerRef} className="relative">
        <button
          type="button"
          onClick={() => setIsOpen((open) => !open)}
          aria-haspopup="listbox"
          aria-expanded={isOpen}
          aria-controls={panelId}
          className={clsx(
            "input-base flex items-center justify-between gap-2 pr-3 text-left",
            !hasSelection && "text-text2",
          )}
        >
          <span className="truncate">{summaryText}</span>
          <svg
            aria-hidden="true"
            viewBox="0 0 12 12"
            className={clsx(
              "h-3 w-3 shrink-0 transition-transform",
              isOpen && "rotate-180",
            )}
          >
            <path
              d="M2.5 4.5 6 8l3.5-3.5"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>

        {isOpen && (
          <div
            id={panelId}
            role="listbox"
            aria-multiselectable="true"
            className="absolute z-20 mt-1 max-h-64 w-full overflow-y-auto rounded-md border border-line bg-card py-1 shadow-lg"
          >
            {hasSelection && (
              <button
                type="button"
                onClick={() => onChange([])}
                className="w-full px-3 py-1.5 text-left text-[13px] font-semibold text-blue hover:bg-bg3"
              >
                {clearLabel}
              </button>
            )}
            {options.map((option) => {
              const isSelected = values.includes(option.value);
              return (
                <label
                  key={option.value}
                  role="option"
                  aria-selected={isSelected}
                  className="flex cursor-pointer items-center gap-2 px-3 py-1.5 text-sm text-text1 hover:bg-bg3"
                >
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onChange={() => toggleValue(option.value)}
                    className="h-4 w-4 accent-accent2"
                  />
                  <span className="truncate">{option.label}</span>
                </label>
              );
            })}
          </div>
        )}
      </div>
    </FieldWrapper>
  );
}
