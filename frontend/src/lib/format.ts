const CURRENCY_FORMATTER = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  maximumFractionDigits: 2,
});

const COMPACT_CURRENCY_FORMATTER = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  notation: "compact",
  maximumFractionDigits: 2,
});

const INTEGER_FORMATTER = new Intl.NumberFormat("pt-BR", {
  maximumFractionDigits: 0,
});

const DECIMAL_FORMATTER = new Intl.NumberFormat("pt-BR", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const EMPTY_PLACEHOLDER = "—";

export function formatCurrency(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY_PLACEHOLDER;
  return CURRENCY_FORMATTER.format(value);
}

export function formatCompactCurrency(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY_PLACEHOLDER;
  return COMPACT_CURRENCY_FORMATTER.format(value);
}

export function formatInteger(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY_PLACEHOLDER;
  return INTEGER_FORMATTER.format(value);
}

export function formatDecimal(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY_PLACEHOLDER;
  return DECIMAL_FORMATTER.format(value);
}

/** Formats a ratio (0.05) as a signed percentage ("+5,00%"). */
export function formatVariation(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY_PLACEHOLDER;
  const sign = value > 0 ? "+" : "";
  return `${sign}${DECIMAL_FORMATTER.format(value * 100)}%`;
}

/** Formats a fraction (0.15) as a plain percentage ("15,00%"). */
export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY_PLACEHOLDER;
  return `${DECIMAL_FORMATTER.format(value * 100)}%`;
}

/** Formats an ISO date (YYYY-MM-DD) as DD/MM/YYYY. */
export function formatIsoDate(value: string | null | undefined): string {
  if (!value) return EMPTY_PLACEHOLDER;
  const [year, month, day] = value.slice(0, 10).split("-");
  if (!year || !month || !day) return value;
  return `${day}/${month}/${year}`;
}

export function formatCnpj(value: string | null | undefined): string {
  if (!value) return EMPTY_PLACEHOLDER;
  const digits = value.replace(/\D/g, "");
  if (digits.length !== 14) return value;
  return digits.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, "$1.$2.$3/$4-$5");
}
