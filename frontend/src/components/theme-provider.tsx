"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import { DEFAULT_THEME, THEME_STORAGE_KEY, type Theme } from "@/lib/theme";

interface ThemeContextValue {
  theme: Theme;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

function readAppliedTheme(): Theme {
  return document.documentElement.classList.contains("light")
    ? "light"
    : "dark";
}

function applyTheme(theme: Theme) {
  const root = document.documentElement;
  root.classList.remove("dark", "light");
  root.classList.add(theme);
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    // Storage unavailable (private mode/quota) — theme still applies for the session.
  }
}

/**
 * Holds the active theme. The initial DOM class is set pre-hydration by
 * THEME_INIT_SCRIPT (see root layout); this provider syncs React state with
 * it on mount, then owns all subsequent changes.
 */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(DEFAULT_THEME);
  const [isHydrated, setIsHydrated] = useState(false);

  useEffect(() => {
    setTheme(readAppliedTheme());
    setIsHydrated(true);
  }, []);

  useEffect(() => {
    if (!isHydrated) return;
    applyTheme(theme);
  }, [theme, isHydrated]);

  const toggleTheme = useCallback(() => {
    setTheme((current) => (current === "dark" ? "light" : "dark"));
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error("useTheme must be used within a ThemeProvider");
  }
  return context;
}
