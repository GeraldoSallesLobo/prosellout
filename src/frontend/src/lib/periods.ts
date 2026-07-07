export interface DateRange {
  start: string;
  end: string;
}

function toIsoDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function getCurrentMonthToDate(reference = new Date()): DateRange {
  const start = new Date(reference.getFullYear(), reference.getMonth(), 1);
  return { start: toIsoDate(start), end: toIsoDate(reference) };
}

export function getFullMonth(reference: Date): DateRange {
  const start = new Date(reference.getFullYear(), reference.getMonth(), 1);
  const end = new Date(reference.getFullYear(), reference.getMonth() + 1, 0);
  return { start: toIsoDate(start), end: toIsoDate(end) };
}

export function getPreviousMonth(reference = new Date()): DateRange {
  return getFullMonth(new Date(reference.getFullYear(), reference.getMonth() - 1, 1));
}

export function getSameMonthLastYear(reference = new Date()): DateRange {
  return getFullMonth(new Date(reference.getFullYear() - 1, reference.getMonth(), 1));
}

export function getMonthStart(reference = new Date()): string {
  return toIsoDate(new Date(reference.getFullYear(), reference.getMonth(), 1));
}

const MONTH_LABELS = [
  "Jan", "Fev", "Mar", "Abr", "Mai", "Jun",
  "Jul", "Ago", "Set", "Out", "Nov", "Dez",
];

/** "2026-07-01" -> "Jul/2026". */
export function formatMonthLabel(isoDate: string): string {
  const [year, month] = isoDate.split("-").map(Number);
  if (!year || !month) return isoDate;
  return `${MONTH_LABELS[month - 1]}/${year}`;
}
