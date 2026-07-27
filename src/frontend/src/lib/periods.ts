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

function getLastDayOfMonth(year: number, monthIndex: number): number {
  return new Date(year, monthIndex + 1, 0).getDate();
}

export function shiftIsoDateByYears(isoDate: string, yearOffset: number): string {
  const [year, month, day] = isoDate.split("-").map(Number);
  if (!year || !month || !day) return isoDate;

  const targetYear = year + yearOffset;
  const monthIndex = month - 1;
  const clampedDay = Math.min(day, getLastDayOfMonth(targetYear, monthIndex));
  return toIsoDate(new Date(targetYear, monthIndex, clampedDay));
}

export function shiftDateRangeByYears(range: DateRange, yearOffset: number): DateRange {
  return {
    start: shiftIsoDateByYears(range.start, yearOffset),
    end: shiftIsoDateByYears(range.end, yearOffset),
  };
}

export function getMonthStart(reference = new Date()): string {
  return toIsoDate(new Date(reference.getFullYear(), reference.getMonth(), 1));
}

export function getMonthStartFromIsoDate(isoDate: string): string {
  const [year, month] = isoDate.split("-").map(Number);
  if (!year || !month) return isoDate;
  return `${year}-${String(month).padStart(2, "0")}-01`;
}

const MONTH_LABELS = [
  "Jan", "Fev", "Mar", "Abr", "Mai", "Jun",
  "Jul", "Ago", "Set", "Out", "Nov", "Dez",
];

const DAYS_PER_WEEK = 7;
const MILLISECONDS_PER_DAY = 86_400_000;

/** "2026-07-01" -> "Jul/2026". */
export function formatMonthLabel(isoDate: string): string {
  const [year, month] = isoDate.split("-").map(Number);
  if (!year || !month) return isoDate;
  return `${MONTH_LABELS[month - 1]}/${year}`;
}

/** Matches Excel WEEKNUM(date, 1): weeks start on Sunday and Jan 1 is week 1. */
export function getSundayWeekNumber(isoDate: string): number | null {
  const [year, month, day] = isoDate.split("-").map(Number);
  if (!year || !month || !day) return null;

  const current = Date.UTC(year, month - 1, day);
  const yearStart = Date.UTC(year, 0, 1);
  const dayOfYear = Math.floor((current - yearStart) / MILLISECONDS_PER_DAY) + 1;
  const yearStartWeekday = new Date(yearStart).getUTCDay();

  return Math.floor((dayOfYear + yearStartWeekday - 1) / DAYS_PER_WEEK) + 1;
}
