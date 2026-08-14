/**
 * Each distributor record represents a distributor × industry pair, so
 * switching "industry" means switching the scoped distributor. The business
 * may still rename the concept, so every screen must read labels from here.
 */
export const INDUSTRY_LABELS = {
  switcherLabel: "Indústria",
  selectTitle: "Selecione a indústria",
  selectDescription: "Escolha qual indústria você quer analisar agora.",
  noAccessTitle: "Sem acesso",
  noAccessDescription:
    "Seu usuário não está vinculado a nenhuma indústria ativa. Fale com o administrador para liberar o acesso.",
} as const;

const SELECTED_INDUSTRY_STORAGE_KEY = "prosellout-selected-industry";

/**
 * The selection belongs to the signed-in session: it survives reloads and
 * extra tabs, and is cleared on sign-out or user switch (see AuthCacheSync),
 * so every new login goes through the industry selection again. It is also
 * validated against the industries the user can actually access before use.
 */
export function readStoredIndustryId(): string | null {
  try {
    return localStorage.getItem(SELECTED_INDUSTRY_STORAGE_KEY);
  } catch {
    return null;
  }
}

export function storeIndustryId(distributorId: string): void {
  try {
    localStorage.setItem(SELECTED_INDUSTRY_STORAGE_KEY, distributorId);
  } catch {
    // Storage unavailable (SSR/private mode): the selection lives in memory only.
  }
}

export function clearStoredIndustryId(): void {
  try {
    localStorage.removeItem(SELECTED_INDUSTRY_STORAGE_KEY);
  } catch {
    // Storage unavailable: there is nothing persisted to clear.
  }
}
