import type { Config } from "tailwindcss";

/**
 * Colors resolve to CSS variables (RGB triplets defined in globals.css) so
 * the whole UI switches between the dark and light themes by toggling the
 * `dark`/`light` class on <html>. `<alpha-value>` keeps opacity modifiers
 * (e.g. bg-red/10) working.
 */
function fromCssVariable(variableName: string): string {
  return `rgb(var(${variableName}) / <alpha-value>)`;
}

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        bg: fromCssVariable("--bg"),
        bg2: fromCssVariable("--bg2"),
        bg3: fromCssVariable("--bg3"),
        line: fromCssVariable("--line"),
        card: fromCssVariable("--card"),
        text1: fromCssVariable("--text1"),
        text2: fromCssVariable("--text2"),
        text3: fromCssVariable("--text3"),
        accent: fromCssVariable("--accent"),
        accent2: fromCssVariable("--accent2"),
        accent3: fromCssVariable("--accent3"),
        accent4: fromCssVariable("--accent4"),
        green: fromCssVariable("--green"),
        blue: fromCssVariable("--blue"),
        purple: fromCssVariable("--purple"),
        yellow: fromCssVariable("--yellow"),
        red: fromCssVariable("--red"),
        orange: fromCssVariable("--orange"),
        chartCurrent: fromCssVariable("--chart-current"),
        chartTarget: fromCssVariable("--chart-target"),
        chartPrevious: fromCssVariable("--chart-previous"),
        field: fromCssVariable("--field"),
      },
      borderRadius: {
        card: "10px",
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "sans-serif",
        ],
      },
    },
  },
  plugins: [],
};

export default config;
