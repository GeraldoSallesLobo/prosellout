const COMBINING_MARKS_PATTERN = new RegExp("[\\u0300-\\u036f]", "g");

export interface SearchState {
  /** Chave da coluna selecionada para a busca. */
  key: string;
  /** Texto livre digitado pelo usuário. */
  text: string;
}

/** Remove acentos e baixa a caixa, para busca amigável em pt-BR. */
export function normalizeSearchText(value: string): string {
  return value.normalize("NFD").replace(COMBINING_MARKS_PATTERN, "").toLowerCase();
}

/** Verifica se o valor da célula contém o texto buscado (sem acentos, case-insensitive). */
export function matchesSearch(
  value: string | number | null | undefined,
  text: string,
): boolean {
  if (value === null || value === undefined) return false;
  return normalizeSearchText(String(value)).includes(normalizeSearchText(text));
}
