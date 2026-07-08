"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { ThemeProvider } from "@/components/theme-provider";
import { ToastProvider } from "@/components/ui/toast";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const STALE_TIME_MS = 60_000;

interface AuthCacheSyncProps {
  queryClient: QueryClient;
}

function getSessionUserId(session: Session | null): string | null {
  return session?.user.id ?? null;
}

function AuthCacheSync({ queryClient }: AuthCacheSyncProps) {
  const router = useRouter();
  const activeUserIdRef = useRef<string | null | undefined>(undefined);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    if (!supabase) return undefined;

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      const nextUserId = getSessionUserId(session);

      if (event === "INITIAL_SESSION") {
        activeUserIdRef.current = nextUserId;
        return;
      }

      if (activeUserIdRef.current === nextUserId) return;

      activeUserIdRef.current = nextUserId;
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
