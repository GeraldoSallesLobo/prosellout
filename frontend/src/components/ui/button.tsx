import clsx from "clsx";
import type { ButtonHTMLAttributes } from "react";

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";

const VARIANT_STYLES: Record<ButtonVariant, string> = {
  primary: "bg-accent2 text-white hover:bg-accent2/85",
  secondary: "border border-line bg-bg3 text-text1 hover:border-blue/50",
  ghost: "text-text2 hover:bg-text1/5 hover:text-text1",
  danger: "border border-red/40 text-red hover:bg-red/10",
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
}

export function Button({ variant = "primary", className, ...props }: ButtonProps) {
  return (
    <button
      className={clsx(
        "inline-flex h-9 items-center justify-center gap-2 rounded-md px-3.5 text-sm font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50",
        VARIANT_STYLES[variant],
        className,
      )}
      {...props}
    />
  );
}
