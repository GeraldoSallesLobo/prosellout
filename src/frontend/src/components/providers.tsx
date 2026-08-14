"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { ThemeProvider } from "@/components/theme-provider";
import { ToastProvider } from "@/components/ui/toast";
import { clearStoredIndustryId } from "@/lib/industry";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const STALE_TIME_MS = 60_000;

interface AuthCacheSyncProps {
  queryClient: QueryClient;
}

function getSessionUserId(session: Session | null): string | null {
  return session?.user?.id ?? null;
}

function AuthCacheSync({ queryClient }: AuthCacheSyncProps) {
  const router = useRouter();
  const activeUserIdRef = useRef<string | null | undefined>(undefined);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    if (!supabase) return undefined;

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      const nextUserId = getSessionUserId(session);

      // The first observed event is the baseline, never a user switch. When a
      // stored session is restored, the client emits SIGNED_IN (or
      // TOKEN_REFRESHED near expiry) from inside the initialization that
      // INITIAL_SESSION awaits, so it arrives first — comparing it against an
      // unset ref would read a routine refresh as "another user" and reset the
      // session mid-navigation.
      if (activeUserIdRef.current === undefined) {
        activeUserIdRef.current = nextUserId;
        return;
      }

      if (activeUserIdRef.current === nextUserId) return;

      activeUserIdRef.current = nextUserId;
      // Reaching here means the signed-in user really changed (sign in, sign
      // out or account switch). The industry in scope belongs to the session
      // that picked it, so the next login goes through the selection again.
      clearStoredIndustryId();
      queryClient.clear();
      router.refresh();
    });

    return () => subscription.unsubscribe();
  }, [queryClient, router]);

  return null;
}

export function AppProviders({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: STALE_TIME_MS,
            refetchOnWindowFocus: false,
            retry: 1,
          },
        },
      }),
  );

  return (
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <AuthCacheSync queryClient={queryClient} />
        <ToastProvider>{children}</ToastProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
}
