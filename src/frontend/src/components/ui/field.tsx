import type { InputHTMLAttributes, SelectHTMLAttributes } from "react";
import clsx from "clsx";

interface FieldWrapperProps {
  label: string;
  className?: string;
  children: React.ReactNode;
}

export function FieldWrapper({ label, className, children }: FieldWrapperProps) {
  return (
    <div className={className}>
      <span className="label-base">{label}</span>
      {children}
    </div>
  );
}

interface TextFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  wrapperClassName?: string;
}

export function TextField({ label, wrapperClassName, className, ...props }: TextFieldProps) {
  return (
    <FieldWrapper label={label} className={wrapperClassName}>
      <input className={clsx("input-base", className)} {...props} />
    </FieldWrapper>
  );
}

interface DateFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  wrapperClassName?: string;
}

export function DateField({ label, wrapperClassName, className, ...props }: DateFieldProps) {
  return (
    <FieldWrapper label={label} className={wrapperClassName}>
      <input
        type="date"
        className={clsx("input-base [color-scheme:dark]", className)}
        {...props}
      />
    </FieldWrapper>
  );
}

export interface SelectOption {
  value: string;
  label: string;
}

interface SelectFieldProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label: string;
  options: SelectOption[];
  /** Adds an "all" option at the top (empty value). */
  allLabel?: string;
  wrapperClassName?: string;
}

export function SelectField({
  label,
  options,
  allLabel = "Todos",
  wrapperClassName,
  className,
  ...props
}: SelectFieldProps) {
  return (
    <FieldWrapper label={label} className={wrapperClassName}>
      <select className={clsx("input-base appearance-none pr-8", className)} {...props}>
        <option value="">{allLabel}</option>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </FieldWrapper>
  );
}
