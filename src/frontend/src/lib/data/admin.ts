import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { simulateLatency } from "./demo/random";

export interface DistributorUser {
  userId: string;
  email: string;
  distributorId: string;
  distributorCode: string;
  distributorName: string;
  status: "active" | "inactive";
  createdAt: string;
}

interface DistributorUserRow {
  user_id: string;
  email: string;
  distributor_id: string;
  distributor_code: string;
  distributor_name: string;
  status: "active" | "inactive";
  created_at: string;
}

export interface CreateDistributorUserInput {
  email: string;
  password: string;
  distributorCode: string;
  distributorName: string;
  distributorCnpj: string;
  city: string;
  state: string;
}

export async function fetchDistributorUsers(): Promise<DistributorUser[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency([]);

  const { data, error } = await supabase.rpc("list_distributor_users");
  if (error) throw error;

  return ((data ?? []) as DistributorUserRow[]).map((row) => ({
    userId: row.user_id,
    email: row.email,
    distributorId: row.distributor_id,
    distributorCode: row.distributor_code,
    distributorName: row.distributor_name,
    status: row.status,
    createdAt: row.created_at,
  }));
}

export async function createDistributorUser(input: CreateDistributorUserInput): Promise<void> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    await simulateLatency(null);
    return;
  }

  const { error } = await supabase.rpc("create_distributor_user", {
    p_email: input.email,
    p_password: input.password,
    p_distributor_code: input.distributorCode,
    p_distributor_name: input.distributorName,
    p_distributor_cnpj: input.distributorCnpj || null,
    p_city: input.city || null,
    p_state: input.state || null,
  });

  if (error) throw error;
}
