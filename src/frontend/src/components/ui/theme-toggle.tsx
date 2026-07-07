"use client";

import { Moon, Sun } from "lucide-react";
import { useTheme } from "@/components/theme-provider";

const DEFAULT_ICON_SIZE = 15;

interface ThemeToggleProps {
  className?: string;
  iconSize?: number;
  showLabel?: boolean;
}

/**
 * Dark/light theme switch. Shows the theme the click switches TO
 * (sun while dark, moon while light). Visual styling comes from the
 * caller via className so it fits both the sidebar and the login screen.
 */
export function ThemeToggle({
  className,
  iconSize = DEFAULT_ICON_SIZE,
  showLabel = false,
}: ThemeToggleProps) {
  const { theme, toggleTheme } = useTheme();
  const isDark = theme === "dark";
  const targetThemeLabel = isDark ? "Tema claro" : "Tema escuro";
  const actionLabel = isDark
    ? "Mudar para o tema claro"
    : "Mudar para o tema escuro";

  return (
    <button
      type="button"
      onClick={toggleTheme}
      title={actionLabel}
      aria-label={actionLabel}
      className={className}
    >
      {isDark ? (
        <Sun size={iconSize} className="shrink-0" />
      ) : (
        <Moon size={iconSize} className="shrink-0" />
      )}
      {showLabel && targetThemeLabel}
    </button>
  );
}
