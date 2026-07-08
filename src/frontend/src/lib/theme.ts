export type Theme = "dark" | "light";

export const THEME_STORAGE_KEY = "prosellout.theme";
export const DEFAULT_THEME: Theme = "light";
export const THEMES: readonly Theme[] = ["light", "dark"];

export function isTheme(value: unknown): value is Theme {
  return value === "dark" || value === "light";
}

/**
 * Inline script injected before hydration so the stored theme is applied
 * ahead of the first paint (no flash of the wrong theme).
 */
export const THEME_INIT_SCRIPT = `(function(){var t=null;try{t=localStorage.getItem("${THEME_STORAGE_KEY}")}catch(e){}if(t!=="light"&&t!=="dark"){t="${DEFAULT_THEME}"}document.documentElement.classList.add(t)})();`;

interface ChartColorTokens {
  grid: string;
  axisText: string;
  tooltipBg: string;
  tooltipBorder: string;
  tooltipText: string;
  cursor: string;
  barPrimary: string;
  lineAccent: string;
  seriesCurrent: string;
  seriesTarget: string;
  seriesPrevious: string;
}

/**
 * Hex palette for Recharts props. SVG presentation attributes don't
 * reliably resolve CSS variables, so charts read these per-theme values
 * through useTheme(). Keep in sync with the tokens in globals.css.
 */
export const CHART_COLORS: Record<Theme, ChartColorTokens> = {
  dark: {
    grid: "#30363d",
    axisText: "#8b949e",
    tooltipBg: "#161b22",
    tooltipBorder: "#30363d",
    tooltipText: "#e6edf3",
    cursor: "rgba(255, 255, 255, 0.04)",
    barPrimary: "#1f6feb",
    lineAccent: "#e3b341",
    seriesCurrent: "#58a6ff",
    seriesTarget: "#e3b341",
    seriesPrevious: "#8b949e",
  },
  light: {
    grid: "#d0d7de",
    axisText: "#59636e",
    tooltipBg: "#ffffff",
    tooltipBorder: "#d0d7de",
    tooltipText: "#1f2328",
    cursor: "rgba(31, 35, 40, 0.06)",
    barPrimary: "#0969da",
    lineAccent: "#bf8700",
    seriesCurrent: "#54aeff",
    seriesTarget: "#bf8700",
    seriesPrevious: "#8c959f",
  },
};
