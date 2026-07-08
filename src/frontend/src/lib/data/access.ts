import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { simulateLatency } from "./demo/random";

export const CURRENT_USER_ACCESS_QUERY_KEY = ["current-user-access"] as const;

export interface CurrentUserAccess {
  isAdmin: boolean;
  distributorCount: number;
}

interface CurrentUserAccessRow {
  is_admin: boolean;
  distributor_count: number;
}

const DEMO_ACCESS: CurrentUserAccess = {
  isAdmin: false,
  distributorCount: 1,
};

export async function fetchCurrentUserAccess(): Promise<CurrentUserAccess> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(DEMO_ACCESS);

  const { data, error } = await supabase.rpc("get_current_user_access");
  if (error) throw error;

  const rows = (data ?? []) as CurrentUserAccessRow[];
  const access = rows[0];

  return {
    isAdmin: Boolean(access?.is_admin),
    distributorCount: Number(access?.distributor_count ?? 0),
  };
}
