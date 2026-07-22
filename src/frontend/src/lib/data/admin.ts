import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type { SearchState } from "@/lib/search";
import type { Paginated } from "@/types/domain";
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

export type PlatformDataDataset =
  | "customers"
  | "sales_reps"
  | "sell_out"
  | "sell_in"
  | "sales_targets"
  | "product_hierarchy"
  | "commercial_hierarchy"
  | "distributors";

export interface DeletePlatformDataInput {
  dataset: PlatformDataDataset;
  rowIds?: Array<string | number>;
  start?: string;
  end?: string;
  distributorId?: string;
  search?: SearchState | null;
  channelIds?: string[];
  clusterId?: string;
  supervisorId?: string;
}

interface DeletePlatformDataRow {
  deleted_count: number;
}

export interface PlatformDeletionLog {
  id: number;
  adminUserId: string;
  adminEmail: string | null;
  dataset: PlatformDataDataset;
  filters: Record<string, unknown>;
  deletedCount: number;
  createdAt: string;
}

interface PlatformDeletionLogRow {
  id: number;
  admin_user_id: string;
  admin_email: string | null;
  dataset: PlatformDataDataset;
  filters: Record<string, unknown>;
  deleted_count: number;
  created_at: string;
  total_count: number;
}

export interface PlatformDeletionLogQuery {
  page: number;
  pageSize: number;
  dataset?: PlatformDataDataset;
  start?: string;
  end?: string;
}

export async function deletePlatformData(input: DeletePlatformDataInput): Promise<number> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(0);

  const { data, error } = await supabase.rpc("delete_platform_data", {
    p_dataset: input.dataset,
    p_row_ids: input.rowIds?.length ? input.rowIds.map(String) : null,
    p_start: input.start || null,
    p_end: input.end || null,
    p_distributor_id: input.distributorId || null,
    p_search_key: input.search?.key ?? null,
    p_search_text: input.search?.text ?? null,
    p_channel_ids: input.channelIds?.length ? input.channelIds : null,
    p_cluster_id: input.clusterId || null,
    p_supervisor_id: input.supervisorId || null,
  });

  if (error) throw error;

  const rows = (data ?? []) as DeletePlatformDataRow[];
  return Number(rows[0]?.deleted_count ?? 0);
}

interface SetDistributorStatusRow {
  affected_count: number;
}

export async function setDistributorStatus(
  distributorId: string,
  status: "active" | "inactive",
): Promise<number> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(0);

  const { data, error } = await supabase.rpc("set_distributor_status", {
    p_distributor_id: distributorId,
    p_status: status,
  });

  if (error) throw error;

  const rows = (data ?? []) as SetDistributorStatusRow[];
  return Number(rows[0]?.affected_count ?? 0);
}

export async function inactivateDistributor(distributorId: string): Promise<number> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(0);

  const { data, error } = await supabase.rpc("inactivate_distributor", {
    p_distributor_id: distributorId,
  });

  if (error) throw error;

  const rows = (data ?? []) as SetDistributorStatusRow[];
  return Number(rows[0]?.affected_count ?? 0);
}

export async function fetchPlatformDeletionLogs(
  query: PlatformDeletionLogQuery,
): Promise<Paginated<PlatformDeletionLog>> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency({ rows: [], total: 0 });

  const { data, error } = await supabase.rpc("list_platform_data_deletion_logs", {
    p_dataset: query.dataset ?? null,
    p_start: query.start || null,
    p_end: query.end || null,
    p_limit: query.pageSize,
    p_offset: (query.page - 1) * query.pageSize,
  });

  if (error) throw error;

  const rows = (data ?? []) as PlatformDeletionLogRow[];

  return {
    total: Number(rows[0]?.total_count ?? 0),
    rows: rows.map((row) => ({
      id: Number(row.id),
      adminUserId: row.admin_user_id,
      adminEmail: row.admin_email,
      dataset: row.dataset,
      filters: row.filters ?? {},
      deletedCount: Number(row.deleted_count),
      createdAt: row.created_at,
    })),
  };
}
