import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type {
  Distributor,
  EntityStatus,
  HierarchyNode,
  SalesRep,
} from "@/types/domain";
import {
  DEMO_DISTRIBUTORS,
  DEMO_PRODUCT_TREE,
  DEMO_SELLERS,
  DEMO_SUPERVISORS,
} from "./demo/catalog";
import { simulateLatency } from "./demo/random";

export type StatusFilter = "all" | EntityStatus;

function matchesStatus(status: EntityStatus, filter: StatusFilter): boolean {
  return filter === "all" || status === filter;
}

export async function fetchDistributors(statusFilter: StatusFilter): Promise<Distributor[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    return simulateLatency(
      DEMO_DISTRIBUTORS.filter((distributor) => matchesStatus(distributor.status, statusFilter)),
    );
  }

  let query = supabase.from("distributors").select("*").order("name");
  if (statusFilter !== "all") query = query.eq("status", statusFilter);
  const { data, error } = await query;
  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    cnpj: row.cnpj,
    city: row.city,
    state: row.state,
    status: row.status,
  }));
}

export async function createDistributor(input: {
  code: string;
  name: string;
  cnpj: string;
  city: string;
  state: string;
}): Promise<void> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    await simulateLatency(null);
    return;
  }
  const { error } = await supabase.from("distributors").insert(input);
  if (error) throw error;
}

interface HierarchyRow {
  id: string;
  parent_id: string | null;
  level: HierarchyNode["level"];
  name: string;
  status: EntityStatus;
}

function buildTree(rows: HierarchyRow[]): HierarchyNode[] {
  const nodes = new Map<string, HierarchyNode>();
  rows.forEach((row) => {
    nodes.set(row.id, {
      id: row.id,
      parentId: row.parent_id,
      level: row.level,
      name: row.name,
      status: row.status,
      children: [],
    });
  });

  const roots: HierarchyNode[] = [];
  nodes.forEach((node) => {
    if (node.parentId && nodes.has(node.parentId)) {
      nodes.get(node.parentId)!.children.push(node);
    } else {
      roots.push(node);
    }
  });
  return roots;
}

export async function fetchProductHierarchy(statusFilter: StatusFilter): Promise<HierarchyNode[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    if (statusFilter === "all") return simulateLatency(DEMO_PRODUCT_TREE);
    const filterTree = (nodes: HierarchyNode[]): HierarchyNode[] =>
      nodes
        .filter((node) => matchesStatus(node.status, statusFilter))
        .map((node) => ({ ...node, children: filterTree(node.children) }));
    return simulateLatency(filterTree(DEMO_PRODUCT_TREE));
  }

  let query = supabase.from("product_hierarchy").select("*").order("name");
  if (statusFilter !== "all") query = query.eq("status", statusFilter);
  const { data, error } = await query;
  if (error) throw error;
  return buildTree((data ?? []) as HierarchyRow[]);
}

export async function createHierarchyNode(input: {
  parentId: string | null;
  level: HierarchyNode["level"];
  name: string;
}): Promise<void> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    await simulateLatency(null);
    return;
  }
  const { error } = await supabase.from("product_hierarchy").insert({
    parent_id: input.parentId,
    level: input.level,
    name: input.name,
  });
  if (error) throw error;
}

export interface CommercialTree {
  supervisors: SalesRep[];
  sellersBySupervisor: Map<string, SalesRep[]>;
}

export async function fetchCommercialHierarchy(statusFilter: StatusFilter): Promise<CommercialTree> {
  const supabase = getSupabaseBrowserClient();

  let supervisors: SalesRep[];
  let sellers: SalesRep[];

  if (!supabase) {
    supervisors = DEMO_SUPERVISORS;
    sellers = DEMO_SELLERS;
    await simulateLatency(null);
  } else {
    const { data, error } = await supabase.from("sales_reps").select("*").order("name");
    if (error) throw error;
    const reps: SalesRep[] = (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      role: row.role,
      supervisorId: row.supervisor_id,
      status: row.status,
    }));
    supervisors = reps.filter((rep) => rep.role === "supervisor");
    sellers = reps.filter((rep) => rep.role === "seller");
  }

  if (statusFilter !== "all") {
    sellers = sellers.filter((seller) => matchesStatus(seller.status, statusFilter));
    supervisors = supervisors.filter((supervisor) =>
      matchesStatus(supervisor.status, statusFilter),
    );
  }

  const sellersBySupervisor = new Map<string, SalesRep[]>();
  sellers.forEach((seller) => {
    if (!seller.supervisorId) return;
    const list = sellersBySupervisor.get(seller.supervisorId) ?? [];
    list.push(seller);
    sellersBySupervisor.set(seller.supervisorId, list);
  });

  return { supervisors, sellersBySupervisor };
}

export async function createSalesRep(input: {
  name: string;
  role: SalesRep["role"];
  supervisorId: string | null;
}): Promise<void> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    await simulateLatency(null);
    return;
  }
  const { error } = await supabase.from("sales_reps").insert({
    name: input.name,
    role: input.role,
    supervisor_id: input.supervisorId,
  });
  if (error) throw error;
}
