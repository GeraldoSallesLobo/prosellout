"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight, Factory } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { BrandLogo } from "@/components/ui/brand-logo";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/ui/theme-toggle";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  MY_DISTRIBUTORS_QUERY_KEY,
  fetchCurrentUserAccess,
  fetchMyDistributors,
} from "@/lib/data/access";
import { INDUSTRY_LABELS, storeIndustryId } from "@/lib/industry";
import { HOME_ROUTE, LOGIN_ROUTE } from "@/lib/routes";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const THEME_ICON_SIZE = 18;

/**
 * Post-login industry picker for users linked to more than one industry.
 * Admins and single-link users never stay here: they are forwarded straight
 * to the portal home.
 */
export default function SelectIndustryPage() {
  const router = useRouter();

  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });
  const isIndustryUser = access !== undefined && !access.isAdmin;

  const { data: distributors } = useQuery({
    queryKey: MY_DISTRIBUTORS_QUERY_KEY,
    queryFn: fetchMyDistributors,
    enabled: isIndustryUser,
  });

  useEffect(() => {
    if (access?.isAdmin) {
      router.replace(HOME_ROUTE);
      return;
    }
    if (!distributors || distributors.length !== 1) return;
    storeIndustryId(distributors[0].id);
    router.replace(HOME_ROUTE);
  }, [access, distributors, router]);

  function handleSelectIndustry(distributorId: string): void {
    storeIndustryId(distributorId);
    router.replace(HOME_ROUTE);
  }

  async function handleSignOut(): Promise<void> {
    const supabase = getSupabaseBrowserClient();
    if (supabase) await supabase.auth.signOut();
    router.replace(LOGIN_ROUTE);
    router.refresh();
  }

  const hasNoAccess = isIndustryUser && distributors !== undefined && distributors.length === 0;
  const isChoiceReady = isIndustryUser && distributors !== undefined && distributors.length > 1;

  return (
    <div className="login-bg relative flex min-h-screen items-center justify-center p-4">
      <ThemeToggle
        iconSize={THEME_ICON_SIZE}
        className="absolute right-4 top-4 rounded-md p-2 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
      />
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <BrandLogo className="mx-auto" priority size="login" />
          <p className="mt-1 text-sm text-text2">Portal de gestão de Sell Out</p>
        </div>

        {hasNoAccess ? (
          <div className="card p-6 text-center">
            <h1 className="text-lg font-semibold text-text1">{INDUSTRY_LABELS.noAccessTitle}</h1>
            <p className="mt-2 text-sm text-text2">{INDUSTRY_LABELS.noAccessDescription}</p>
            <Button className="mt-4" onClick={handleSignOut}>
              Sair
            </Button>
          </div>
        ) : isChoiceReady ? (
          <div className="card p-6">
            <h1 className="text-base font-semibold text-text1">{INDUSTRY_LABELS.selectTitle}</h1>
            <p className="mt-1 text-sm text-text2">{INDUSTRY_LABELS.selectDescription}</p>
            <ul className="mt-4 space-y-2">
              {distributors.map((distributor) => (
                <li key={distributor.id}>
                  <button
                    type="button"
                    onClick={() => handleSelectIndustry(distributor.id)}
                    className="flex w-full items-center gap-3 rounded-md border border-line bg-field px-3 py-2.5 text-left transition-colors hover:border-blue hover:bg-text1/5"
                  >
                    <Factory size={16} className="shrink-0 text-text2" aria-hidden />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium text-text1">
                        {distributor.name}
                      </span>
                      <Badge variant="blue">{distributor.code}</Badge>
                    </span>
                    <ChevronRight size={16} className="shrink-0 text-text2" aria-hidden />
                  </button>
                </li>
              ))}
            </ul>
            <button
              type="button"
              onClick={handleSignOut}
              className="mt-4 w-full text-center text-xs text-text2 transition-colors hover:text-text1"
            >
              Entrar com outro usuário
            </button>
          </div>
        ) : (
          <div className="card p-6 text-center">
            <p className="text-sm text-text2">Carregando acesso…</p>
          </div>
        )}
      </div>
    </div>
  );
}
