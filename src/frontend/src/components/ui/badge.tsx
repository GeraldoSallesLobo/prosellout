import clsx from "clsx";

type BadgeVariant = "green" | "red" | "blue" | "purple" | "yellow" | "neutral";

const VARIANT_STYLES: Record<BadgeVariant, string> = {
  green: "border-green/30 bg-green/10 text-green",
  red: "border-red/30 bg-red/10 text-red",
  blue: "border-blue/30 bg-blue/10 text-blue",
  purple: "border-purple/30 bg-purple/10 text-purple",
  yellow: "border-yellow/30 bg-yellow/10 text-yellow",
  neutral: "border-line bg-bg3 text-text2",
};

interface BadgeProps {
  variant?: BadgeVariant;
  children: React.ReactNode;
  className?: string;
}

export function Badge({ variant = "neutral", children, className }: BadgeProps) {
  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1 rounded-md border px-2 py-0.5 text-[11px] font-semibold",
        VARIANT_STYLES[variant],
        className,
      )}
    >
      {children}
    </span>
  );
}

export function StatusBadge({ isActive }: { isActive: boolean }) {
  return (
    <Badge variant={isActive ? "green" : "neutral"}>
      {isActive ? "Ativo" : "Inativo"}
    </Badge>
  );
}

/** Table badge used in the mockup analysis table ("Na Meta" / "Abaixo"). */
export function TargetBadge({ hasReachedTarget }: { hasReachedTarget: boolean }) {
  return (
    <Badge variant={hasReachedTarget ? "green" : "red"}>
      {hasReachedTarget ? "Na Meta" : "Abaixo"}
    </Badge>
  );
}
