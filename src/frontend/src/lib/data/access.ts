import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { DEMO_DISTRIBUTORS } from "./demo/catalog";
import { simulateLatency } from "./demo/random";

export const CURRENT_USER_ACCESS_QUERY_KEY = ["current-user-access"] as const;
export const MY_DISTRIBUTORS_QUERY_KEY = ["my-distributors"] as const;

export interface CurrentUserAccess {
  isAdmin: boolean;
  distributorCount: number;
}

export interface DistributorOption {
  id: string;
  code: string;
  name: string;
}

interface CurrentUserAccessRow {
  is_admin: boolean;
  distributor_count: number;
}

const ACTIVE_DEMO_DISTRIBUTORS = DEMO_DISTRIBUTORS.filter(
  (distributor) => distributor.status === "active",
);

const DEMO_ACCESS: CurrentUserAccess = {
  isAdmin: false,
  distributorCount: ACTIVE_DEMO_DISTRIBUTORS.length,
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

/**
 * Active industries the current user can access. RLS already limits the
 * distributors table to the user's links, so a plain select is enough.
 */
export async function fetchMyDistributors(): Promise<DistributorOption[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    return simulateLatency(
      ACTIVE_DEMO_DISTRIBUTORS.map(({ id, code, name }) => ({ id, code, name })),
    );
  }

  const { data, error } = await supabase
    .from("distributors")
    .select("id, code, name")
    .eq("status", "active")
    .order("name");
  if (error) throw error;

  return (data ?? []) as DistributorOption[];
}
