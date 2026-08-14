"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import type { ReactElement, ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  MY_DISTRIBUTORS_QUERY_KEY,
  fetchCurrentUserAccess,
  fetchMyDistributors,
  type DistributorOption,
} from "@/lib/data/access";
import { INDUSTRY_LABELS, readStoredIndustryId, storeIndustryId } from "@/lib/industry";
import { LOGIN_ROUTE, SELECT_INDUSTRY_ROUTE } from "@/lib/routes";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export interface IndustryScope {
  /** Active industries linked to the current user (empty for admins). */
  distributors: DistributorOption[];
  /**
   * Industry every scoped read/write must use. Null only for admins, whose
   * global view keeps the per-screen distributor filters.
   */
  selectedDistributorId: string | null;
  hasMultipleIndustries: boolean;
  selectIndustry: (distributorId: string) => void;
}

const IndustryScopeContext = createContext<IndustryScope | null>(null);

const ADMIN_SELECT_INDUSTRY: IndustryScope["selectIndustry"] = () => {};

export function useIndustryScope(): IndustryScope {
  const scope = useContext(IndustryScopeContext);
  if (!scope) {
    throw new Error("useIndustryScope must be used within IndustryProvider");
  }
  return scope;
}

/** Errors raised by the database when the industry link no longer exists. */
function isIndustryAccessError(error: unknown): boolean {
  if (!error || typeof error !== "object" || !("message" in error)) return false;
  const message = String((error as { message: unknown }).message);
  return (
    message.includes("Unauthorized distributor") ||
    message.includes("No distributor linked")
  );
}

function IndustryGateSplash(): ReactElement {
  return (
    <div className="flex h-screen items-center justify-center bg-bg">
      <p className="text-sm text-text2">Carregando acesso…</p>
    </div>
  );
}

function IndustryGateError({ onRetry }: { onRetry: () => void }): ReactElement {
  return (
    <div className="flex h-screen items-center justify-center bg-bg p-4">
      <div className="card w-full max-w-md p-6 text-center">
        <h1 className="text-lg font-semibold text-text1">Erro ao carregar acesso</h1>
        <p className="mt-2 text-sm text-text2">
          Não foi possível validar seu acesso. Verifique a conexão e tente novamente.
        </p>
        <Button className="mt-4" onClick={onRetry}>
          Tentar novamente
        </Button>
      </div>
    </div>
  );
}

function NoAccessScreen(): ReactElement {
  const router = useRouter();

  async function handleSignOut(): Promise<void> {
    const supabase = getSupabaseBrowserClient();
    if (supabase) await supabase.auth.signOut();
    router.replace(LOGIN_ROUTE);
    router.refresh();
  }

  return (
    <div className="flex h-screen items-center justify-center bg-bg p-4">
      <div className="card w-full max-w-md p-6 text-center">
        <h1 className="text-lg font-semibold text-text1">{INDUSTRY_LABELS.noAccessTitle}</h1>
        <p className="mt-2 text-sm text-text2">{INDUSTRY_LABELS.noAccessDescription}</p>
        <Button className="mt-4" onClick={handleSignOut}>
          Sair
        </Button>
      </div>
    </div>
  );
}

/**
 * Resolves which industry the session operates on before any portal screen
 * renders, so scoped queries never run without their industry:
 * admins skip the gate (global view), a single link is auto-selected, and
 * users with several links go through /selecionar-industria.
 */
export function IndustryProvider({ children }: { children: ReactNode }): ReactElement {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [selectedDistributorId, setSelectedDistributorId] = useState<string | null>(null);

  const accessQuery = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const access = accessQuery.data;
  const isIndustryUser = access !== undefined && !access.isAdmin;

  const distributorsQuery = useQuery({
    queryKey: MY_DISTRIBUTORS_QUERY_KEY,
    queryFn: fetchMyDistributors,
    enabled: isIndustryUser,
  });
  const distributors = distributorsQuery.data;

  const selectIndustry = useCallback(
    (distributorId: string) => {
      storeIndustryId(distributorId);
      setSelectedDistributorId(distributorId);
      // Anything fetched under the previous industry is out of scope now;
      // keep only the gate queries so the switch does not flash the splash.
      queryClient.removeQueries({
        predicate: (query) =>
          query.queryKey[0] !== CURRENT_USER_ACCESS_QUERY_KEY[0] &&
          query.queryKey[0] !== MY_DISTRIBUTORS_QUERY_KEY[0],
      });
    },
    [queryClient],
  );

  useEffect(() => {
    if (!isIndustryUser || !distributors) return;

    const isSelectionValid =
      selectedDistributorId !== null &&
      distributors.some((distributor) => distributor.id === selectedDistributorId);
    if (isSelectionValid) return;

    if (selectedDistributorId !== null) {
      // The selected industry disappeared (link revoked or inactivated);
      // clearing it re-runs this resolution from scratch.
      setSelectedDistributorId(null);
      return;
    }

    if (distributors.length === 0) return;

    const storedId = readStoredIndustryId();
    if (storedId && distributors.some((distributor) => distributor.id === storedId)) {
      setSelectedDistributorId(storedId);
      return;
    }

    if (distributors.length === 1) {
      storeIndustryId(distributors[0].id);
      setSelectedDistributorId(distributors[0].id);
      return;
    }

    router.replace(SELECT_INDUSTRY_ROUTE);
  }, [isIndustryUser, distributors, selectedDistributorId, router]);

  useEffect(() => {
    // A revoked link surfaces as an authorization error on any scoped query;
    // refreshing the gate queries makes the resolution effect react to it.
    const cache = queryClient.getQueryCache();
    return cache.subscribe((event) => {
      if (event.type !== "updated") return;
      if (!isIndustryAccessError(event.query.state.error)) return;
      queryClient.invalidateQueries({ queryKey: MY_DISTRIBUTORS_QUERY_KEY });
      queryClient.invalidateQueries({ queryKey: CURRENT_USER_ACCESS_QUERY_KEY });
    });
  }, [queryClient]);

  const scope = useMemo<IndustryScope>(() => {
    if (access?.isAdmin) {
      return {
        distributors: [],
        selectedDistributorId: null,
        hasMultipleIndustries: false,
        selectIndustry: ADMIN_SELECT_INDUSTRY,
      };
    }
    return {
      distributors: distributors ?? [],
      selectedDistributorId,
      hasMultipleIndustries: (distributors ?? []).length > 1,
      selectIndustry,
    };
  }, [access?.isAdmin, distributors, selectedDistributorId, selectIndustry]);

  if (accessQuery.isError) {
    return <IndustryGateError onRetry={() => accessQuery.refetch()} />;
  }
  if (!access) return <IndustryGateSplash />;

  if (access.isAdmin) {
    return (
      <IndustryScopeContext.Provider value={scope}>{children}</IndustryScopeContext.Provider>
    );
  }

  if (distributorsQuery.isError) {
    return <IndustryGateError onRetry={() => distributorsQuery.refetch()} />;
  }
  if (!distributors) return <IndustryGateSplash />;
  if (distributors.length === 0) return <NoAccessScreen />;
  if (!selectedDistributorId) return <IndustryGateSplash />;

  return (
    <IndustryScopeContext.Provider value={scope}>{children}</IndustryScopeContext.Provider>
  );
}
