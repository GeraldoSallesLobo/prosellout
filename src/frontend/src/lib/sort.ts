export type SortDirection = "asc" | "desc";

export interface SortState {
  key: string;
  direction: SortDirection;
}

export type SortValue = string | number | null | undefined;

/**
 * Compara valores não-vazios: números numericamente, strings com
 * localeCompare pt-BR (numeric habilitado para códigos/EANs).
 */
export function compareSortValues(a: SortValue, b: SortValue): number {
  if (typeof a === "number" && typeof b === "number") return a - b;
  return String(a ?? "").localeCompare(String(b ?? ""), "pt-BR", {
    numeric: true,
    sensitivity: "base",
  });
}

/**
 * Ordena uma cópia de `rows` pelo valor extraído por `getValue`.
 * Valores vazios (null/undefined/"") vão sempre para o final,
 * independentemente da direção.
 */
export function sortByValue<T>(
  rows: T[],
  sort: SortState | null | undefined,
  getValue: ((row: T) => SortValue) | undefined,
): T[] {
  if (!sort || !getValue) return rows;
  const factor = sort.direction === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => {
    const aValue = getValue(a);
    const bValue = getValue(b);
    const aEmpty = aValue === null || aValue === undefined || aValue === "";
    const bEmpty = bValue === null || bValue === undefined || bValue === "";
    if (aEmpty || bEmpty) return aEmpty && bEmpty ? 0 : aEmpty ? 1 : -1;
    return compareSortValues(aValue, bValue) * factor;
  });
}
