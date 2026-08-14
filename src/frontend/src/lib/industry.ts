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
 * Mirrors the selection so the picker can still hand it over to the portal when
 * localStorage cannot be written (private mode, blocked site data, quota):
 * the picker saves and navigates away immediately, so without the mirror the
 * portal would read nothing back and bounce the user to the picker forever.
 * It is consulted only while storage is known to be unwritable, so a selection
 * cleared in another tab is never resurrected here.
 */
let inMemoryIndustryId: string | null = null;
let isStorageWritable = true;

/**
 * The selection belongs to the signed-in session: it survives reloads and extra
 * tabs, and is cleared when the signed-in user changes, so a new login goes
 * through the industry selection again. It is always validated against the
 * industries the user can actually access before being used.
 */
export function readStoredIndustryId(): string | null {
  if (typeof window === "undefined") return null;
  try {
    const storedId = localStorage.getItem(SELECTED_INDUSTRY_STORAGE_KEY);
    if (storedId !== null) return storedId;
    return isStorageWritable ? null : inMemoryIndustryId;
  } catch {
    return inMemoryIndustryId;
  }
}

export function storeIndustryId(distributorId: string): void {
  if (typeof window === "undefined") return;
  inMemoryIndustryId = distributorId;
  try {
    localStorage.setItem(SELECTED_INDUSTRY_STORAGE_KEY, distributorId);
  } catch {
    isStorageWritable = false;
  }
}

export function clearStoredIndustryId(): void {
  if (typeof window === "undefined") return;
  inMemoryIndustryId = null;
  try {
    localStorage.removeItem(SELECTED_INDUSTRY_STORAGE_KEY);
  } catch {
    // Storage unwritable: clearing the mirror is enough.
  }
}
