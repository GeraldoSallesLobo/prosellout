import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { matchesSearch, type SearchState } from "@/lib/search";
import { sortByValue, type SortState } from "@/lib/sort";
import type {
  Customer,
  NamedEntity,
  Paginated,
  SalesRep,
  SellInRow,
  SellOutRow,
  StockRow,
  TargetRow,
} from "@/types/domain";
import { DEMO_CHANNELS, DEMO_CLUSTERS, DEMO_CUSTOMERS, DEMO_SELLERS } from "./demo/catalog";
import {
  DEMO_SELL_IN_ROWS,
  DEMO_SELL_OUT_ROWS,
  DEMO_STOCK_ROWS,
  DEMO_TARGET_ROWS,
} from "./demo/tables";
import { simulateLatency } from "./demo/random";

export const DATA_PAGE_SIZE = 25;

export interface TableQuery {
  page: number;
  pageSize: number;
  sort?: SortState | null;
  search?: SearchState | null;
}

/** Extratores de valor por coluna, usados no modo demo (ordenação/busca em memória). */
type DemoSortMap<T> = Record<string, (row: T) => string | number | null>;

/** Coluna PostgREST usada na busca server-side; `relation` exige join !inner. */
type SearchColumnMap = Record<string, { column: string; relation?: string }>;

function sortDemoRows<T>(
  rows: T[],
  sort: SortState | null | undefined,
  map: DemoSortMap<T>,
): T[] {
  return sortByValue(rows, sort ?? null, sort ? map[sort.key] : undefined);
}

function searchDemoRows<T>(
  rows: T[],
  search: SearchState | null | undefined,
  map: DemoSortMap<T>,
): T[] {
  const getValue = search?.text ? map[search.key] : undefined;
  if (!search || !getValue) return rows;
  return rows.filter((row) => matchesSearch(getValue(row), search.text));
}

/** Escapa curingas do LIKE (`%`, `_`) no texto digitado pelo usuário. */
function escapeLikePattern(text: string): string {
  return text.replace(/[\\%_]/g, "\\$&");
}

/** Marca a relação usada na busca como !inner para o filtro alcançar a tabela pai. */
function withInnerJoin(select: string, relation?: string): string {
  if (!relation) return select;
  return select.replace(`${relation}(`, `${relation}!inner(`);
}

function resolveSearch(
  tableQuery: TableQuery,
  map: SearchColumnMap,
): { target: { column: string; relation?: string }; pattern: string } | undefined {
  const search = tableQuery.search;
  if (!search?.text) return undefined;
  const target = map[search.key];
  if (!target) return undefined;
  return { target, pattern: `%${escapeLikePattern(search.text)}%` };
}

function paginate<T>(rows: T[], { page, pageSize }: TableQuery): Paginated<T> {
  const start = (page - 1) * pageSize;
  return { rows: rows.slice(start, start + pageSize), total: rows.length };
}

function pageRange({ page, pageSize }: TableQuery): { from: number; to: number } {
  const from = (page - 1) * pageSize;
  return { from, to: from + pageSize - 1 };
}

export interface CustomerFilters {
  channelIds?: string[];
  clusterId?: string;
}

/** Resolves entity ids to their names, or null when no id is selected. */
function namesForIds(entities: NamedEntity[], ids: string[]): string[] | null {
  if (ids.length === 0) return null;
  const idSet = new Set(ids);
  return entities.filter((entity) => idSet.has(entity.id)).map((entity) => entity.name);
}

/** Applies the same filters as the Supabase query to the in-memory demo rows. */
function filterDemoCustomers(filters: CustomerFilters): Customer[] {
  const channelNames = namesForIds(DEMO_CHANNELS, filters.channelIds ?? []);
  const clusterNames = namesForIds(DEMO_CLUSTERS, filters.clusterId ? [filters.clusterId] : []);
  return DEMO_CUSTOMERS.filter((customer) => {
    const isChannelMatch = !channelNames || channelNames.includes(customer.channelName ?? "");
    const isClusterMatch = !clusterNames || clusterNames.includes(customer.clusterName ?? "");
    return isChannelMatch && isClusterMatch;
  });
}

/**
 * Colunas de ordenação server-side (chave da coluna → coluna PostgREST).
 * Colunas de tabelas relacionadas usam a sintaxe "tabela(coluna)".
 */
const CUSTOMER_SORT_COLUMNS: Record<string, string> = {
  cnpj: "cnpj",
  name: "legal_name",
  district: "district",
  city: "city",
  state: "state",
  zip: "zip_code",
  channel: "channels(name)",
  cluster: "clusters(name)",
  status: "status",
};

const CUSTOMER_DEMO_SORTS: DemoSortMap<Customer> = {
  cnpj: (row) => row.cnpj,
  name: (row) => row.legalName,
  district: (row) => row.district,
  city: (row) => row.city,
  state: (row) => row.state,
  zip: (row) => row.zipCode,
  channel: (row) => row.channelName,
  cluster: (row) => row.clusterName,
  status: (row) => row.status,
};

const CUSTOMER_SEARCH_COLUMNS: SearchColumnMap = {
  cnpj: { column: "cnpj" },
  name: { column: "legal_name" },
  district: { column: "district" },
  city: { column: "city" },
  state: { column: "state" },
  zip: { column: "zip_code" },
  channel: { column: "name", relation: "channels" },
  cluster: { column: "name", relation: "clusters" },
};

const CUSTOMER_SELECT =
  "id, cnpj, legal_name, district, city, state, zip_code, status, channels(name), clusters(name), sales_reps(name)";

export async function fetchCustomers(
  tableQuery: TableQuery,
  filters: CustomerFilters,
): Promise<Paginated<Customer>> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const demoRows = sortDemoRows(
      searchDemoRows(filterDemoCustomers(filters), tableQuery.search, CUSTOMER_DEMO_SORTS),
      tableQuery.sort,
      CUSTOMER_DEMO_SORTS,
    );
    return simulateLatency(paginate(demoRows, tableQuery));
  }

  const { from, to } = pageRange(tableQuery);
  const sortColumn = tableQuery.sort ? CUSTOMER_SORT_COLUMNS[tableQuery.sort.key] : undefined;
  const search = resolveSearch(tableQuery, CUSTOMER_SEARCH_COLUMNS);
  let query = supabase
    .from("customers")
    .select(withInnerJoin(CUSTOMER_SELECT, search?.target.relation), { count: "exact" });
  if (search) {
    const { column, relation } = search.target;
    query = query.ilike(relation ? `${relation}.${column}` : column, search.pattern);
  }
  query =
    sortColumn && tableQuery.sort
      ? query.order(sortColumn, { ascending: tableQuery.sort.direction === "asc" })
      : query.order("legal_name");
  query = query.range(from, to);
  if (filters.channelIds?.length) query = query.in("channel_id", filters.channelIds);
  if (filters.clusterId) query = query.eq("cluster_id", filters.clusterId);

  const { data, error, count } = await query;
  if (error) throw error;

  return {
    total: count ?? 0,
    rows: (data ?? []).map((row) => {
      const record = row as unknown as Record<string, unknown>;
      return {
        id: String(record.id),
        cnpj: String(record.cnpj),
        legalName: String(record.legal_name),
        district: (record.district as string) ?? null,
        city: (record.city as string) ?? null,
        state: (record.state as string) ?? null,
        zipCode: (record.zip_code as string) ?? null,
        channelName: (record.channels as { name: string } | null)?.name ?? null,
        clusterName: (record.clusters as { name: string } | null)?.name ?? null,
        salesRepName: (record.sales_reps as { name: string } | null)?.name ?? null,
        status: record.status as Customer["status"],
      };
    }),
  };
}

export interface PeriodFilters {
  start?: string;
  end?: string;
  distributorId?: string;
}

const SELL_OUT_SORT_COLUMNS: Record<string, string> = {
  distributor: "distributors(name)",
  customer: "customers(legal_name)",
  ean: "products(ean)",
  product: "products(name)",
  date: "invoice_date",
  quantity: "quantity",
  value: "gross_value",
};

const SELL_OUT_DEMO_SORTS: DemoSortMap<SellOutRow> = {
  distributor: (row) => row.distributorName,
  customer: (row) => row.customerName,
  ean: (row) => row.ean,
  product: (row) => row.productName,
  date: (row) => row.invoiceDate,
  quantity: (row) => row.quantity,
  value: (row) => row.grossValue,
};

const SELL_OUT_SEARCH_COLUMNS: SearchColumnMap = {
  distributor: { column: "name", relation: "distributors" },
  customer: { column: "legal_name", relation: "customers" },
  ean: { column: "ean", relation: "products" },
  product: { column: "name", relation: "products" },
};

const SELL_OUT_SELECT =
  "id, invoice_date, quantity, gross_value, distributors(name), customers(legal_name), products(ean, name)";

export async function fetchSellOutRows(
  tableQuery: TableQuery,
  filters: PeriodFilters,
): Promise<Paginated<SellOutRow>> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const demoRows = sortDemoRows(
      searchDemoRows(DEMO_SELL_OUT_ROWS, tableQuery.search, SELL_OUT_DEMO_SORTS),
      tableQuery.sort,
      SELL_OUT_DEMO_SORTS,
    );
    return simulateLatency(paginate(demoRows, tableQuery));
  }

  const { from, to } = pageRange(tableQuery);
  const sortColumn = tableQuery.sort ? SELL_OUT_SORT_COLUMNS[tableQuery.sort.key] : undefined;
  const search = resolveSearch(tableQuery, SELL_OUT_SEARCH_COLUMNS);
  let query = supabase
    .from("sell_out")
    .select(withInnerJoin(SELL_OUT_SELECT, search?.target.relation), { count: "exact" });
  if (search) {
    const { column, relation } = search.target;
    query = query.ilike(relation ? `${relation}.${column}` : column, search.pattern);
  }
  query =
    sortColumn && tableQuery.sort
      ? query.order(sortColumn, { ascending: tableQuery.sort.direction === "asc" })
      : query.order("invoice_date", { ascending: false });
  query = query.range(from, to);
  if (filters.start) query = query.gte("invoice_date", filters.start);
  if (filters.end) query = query.lte("invoice_date", filters.end);
  if (filters.distributorId) query = query.eq("distributor_id", filters.distributorId);

  const { data, error, count } = await query;
  if (error) throw error;

  return {
    total: count ?? 0,
    rows: (data ?? []).map((row) => {
      const record = row as unknown as Record<string, unknown>;
      const product = record.products as { ean: string; name: string } | null;
      return {
        id: Number(record.id),
        distributorName: (record.distributors as { name: string } | null)?.name ?? "—",
        customerName: (record.customers as { legal_name: string } | null)?.legal_name ?? "—",
        ean: product?.ean ?? "—",
        productName: product?.name ?? "—",
        invoiceDate: String(record.invoice_date),
        quantity: Number(record.quantity),
        grossValue: Number(record.gross_value),
      };
    }),
  };
}

const SELL_IN_SORT_COLUMNS: Record<string, string> = {
  distributor: "distributors(name)",
  ean: "products(ean)",
  product: "products(name)",
  date: "invoice_date",
  quantity: "quantity",
  value: "gross_value",
};

const SELL_IN_DEMO_SORTS: DemoSortMap<SellInRow> = {
  distributor: (row) => row.distributorName,
  ean: (row) => row.ean,
  product: (row) => row.productName,
  date: (row) => row.invoiceDate,
  quantity: (row) => row.quantity,
  value: (row) => row.grossValue,
};

const SELL_IN_SEARCH_COLUMNS: SearchColumnMap = {
  distributor: { column: "name", relation: "distributors" },
  ean: { column: "ean", relation: "products" },
  product: { column: "name", relation: "products" },
};

const SELL_IN_SELECT =
  "id, invoice_date, quantity, gross_value, distributors(name), products(ean, name)";

export async function fetchSellInRows(
  tableQuery: TableQuery,
  filters: PeriodFilters,
): Promise<Paginated<SellInRow>> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const demoRows = sortDemoRows(
      searchDemoRows(DEMO_SELL_IN_ROWS, tableQuery.search, SELL_IN_DEMO_SORTS),
      tableQuery.sort,
      SELL_IN_DEMO_SORTS,
    );
    return simulateLatency(paginate(demoRows, tableQuery));
  }

  const { from, to } = pageRange(tableQuery);
  const sortColumn = tableQuery.sort ? SELL_IN_SORT_COLUMNS[tableQuery.sort.key] : undefined;
  const search = resolveSearch(tableQuery, SELL_IN_SEARCH_COLUMNS);
  let query = supabase
    .from("sell_in")
    .select(withInnerJoin(SELL_IN_SELECT, search?.target.relation), { count: "exact" });
  if (search) {
    const { column, relation } = search.target;
    query = query.ilike(relation ? `${relation}.${column}` : column, search.pattern);
  }
  query =
    sortColumn && tableQuery.sort
      ? query.order(sortColumn, { ascending: tableQuery.sort.direction === "asc" })
      : query.order("invoice_date", { ascending: false });
  query = query.range(from, to);
  if (filters.start) query = query.gte("invoice_date", filters.start);
  if (filters.end) query = query.lte("invoice_date", filters.end);
  if (filters.distributorId) query = query.eq("distributor_id", filters.distributorId);

  const { data, error, count } = await query;
  if (error) throw error;

  return {
    total: count ?? 0,
    rows: (data ?? []).map((row) => {
      const record = row as unknown as Record<string, unknown>;
      const product = record.products as { ean: string; name: string } | null;
      return {
        id: Number(record.id),
        distributorName: (record.distributors as { name: string } | null)?.name ?? "—",
        ean: product?.ean ?? "—",
        productName: product?.name ?? "—",
        invoiceDate: String(record.invoice_date),
        quantity: Number(record.quantity),
        grossValue: Number(record.gross_value),
      };
    }),
  };
}

const STOCK_SORT_COLUMNS: Record<string, string> = {
  distributor: "distributors(name)",
  ean: "products(ean)",
  product: "products(name)",
  date: "snapshot_date",
  quantity: "quantity",
  value: "gross_value",
};

const STOCK_DEMO_SORTS: DemoSortMap<StockRow> = {
  distributor: (row) => row.distributorName,
  ean: (row) => row.ean,
  product: (row) => row.productName,
  date: (row) => row.snapshotDate,
  quantity: (row) => row.quantity,
  value: (row) => row.grossValue,
};

const STOCK_SEARCH_COLUMNS: SearchColumnMap = {
  distributor: { column: "name", relation: "distributors" },
  ean: { column: "ean", relation: "products" },
  product: { column: "name", relation: "products" },
};

const STOCK_SELECT =
  "id, snapshot_date, quantity, gross_value, distributors(name), products(ean, name)";

export async function fetchStockRows(
  tableQuery: TableQuery,
  filters: PeriodFilters,
): Promise<Paginated<StockRow>> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const demoRows = sortDemoRows(
      searchDemoRows(DEMO_STOCK_ROWS, tableQuery.search, STOCK_DEMO_SORTS),
      tableQuery.sort,
      STOCK_DEMO_SORTS,
    );
    return simulateLatency(paginate(demoRows, tableQuery));
  }

  const { from, to } = pageRange(tableQuery);
  const sortColumn = tableQuery.sort ? STOCK_SORT_COLUMNS[tableQuery.sort.key] : undefined;
  const search = resolveSearch(tableQuery, STOCK_SEARCH_COLUMNS);
  let query = supabase
    .from("stock_snapshots")
    .select(withInnerJoin(STOCK_SELECT, search?.target.relation), { count: "exact" });
  if (search) {
    const { column, relation } = search.target;
    query = query.ilike(relation ? `${relation}.${column}` : column, search.pattern);
  }
  query =
    sortColumn && tableQuery.sort
      ? query.order(sortColumn, { ascending: tableQuery.sort.direction === "asc" })
      : query.order("snapshot_date", { ascending: false });
  query = query.range(from, to);
  if (filters.start) query = query.gte("snapshot_date", filters.start);
  if (filters.end) query = query.lte("snapshot_date", filters.end);
  if (filters.distributorId) query = query.eq("distributor_id", filters.distributorId);

  const { data, error, count } = await query;
  if (error) throw error;

  return {
    total: count ?? 0,
    rows: (data ?? []).map((row) => {
      const record = row as unknown as Record<string, unknown>;
      const product = record.products as { ean: string; name: string } | null;
      return {
        id: Number(record.id),
        distributorName: (record.distributors as { name: string } | null)?.name ?? "—",
        ean: product?.ean ?? "—",
        productName: product?.name ?? "—",
        snapshotDate: String(record.snapshot_date),
        quantity: Number(record.quantity),
        grossValue: Number(record.gross_value),
      };
    }),
  };
}

const TARGET_SORT_COLUMNS: Record<string, string> = {
  customer: "customers(legal_name)",
  ean: "products(ean)",
  product: "products(name)",
  date: "target_date",
  quantity: "quantity",
  value: "gross_value",
};

const TARGET_DEMO_SORTS: DemoSortMap<TargetRow> = {
  customer: (row) => row.customerName,
  ean: (row) => row.ean,
  product: (row) => row.productName,
  date: (row) => row.targetDate,
  quantity: (row) => row.quantity,
  value: (row) => row.grossValue,
};

const TARGET_SEARCH_COLUMNS: SearchColumnMap = {
  customer: { column: "legal_name", relation: "customers" },
  ean: { column: "ean", relation: "products" },
  product: { column: "name", relation: "products" },
};

const TARGET_SELECT =
  "id, target_date, quantity, gross_value, customers(legal_name), products(ean, name)";

export async function fetchTargetRows(
  tableQuery: TableQuery,
  filters: PeriodFilters,
): Promise<Paginated<TargetRow>> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const demoRows = sortDemoRows(
      searchDemoRows(DEMO_TARGET_ROWS, tableQuery.search, TARGET_DEMO_SORTS),
      tableQuery.sort,
      TARGET_DEMO_SORTS,
    );
    return simulateLatency(paginate(demoRows, tableQuery));
  }

  const { from, to } = pageRange(tableQuery);
  const sortColumn = tableQuery.sort ? TARGET_SORT_COLUMNS[tableQuery.sort.key] : undefined;
  const search = resolveSearch(tableQuery, TARGET_SEARCH_COLUMNS);
  let query = supabase
    .from("sales_targets")
    .select(withInnerJoin(TARGET_SELECT, search?.target.relation), { count: "exact" });
  if (search) {
    const { column, relation } = search.target;
    query = query.ilike(relation ? `${relation}.${column}` : column, search.pattern);
  }
  query =
    sortColumn && tableQuery.sort
      ? query.order(sortColumn, { ascending: tableQuery.sort.direction === "asc" })
      : query.order("target_date", { ascending: false });
  query = query.range(from, to);
  if (filters.start) query = query.gte("target_date", filters.start);
  if (filters.end) query = query.lte("target_date", filters.end);

  const { data, error, count } = await query;
  if (error) throw error;

  return {
    total: count ?? 0,
    rows: (data ?? []).map((row) => {
      const record = row as unknown as Record<string, unknown>;
      const product = record.products as { ean: string; name: string } | null;
      return {
        id: Number(record.id),
        customerName: (record.customers as { legal_name: string } | null)?.legal_name ?? "—",
        ean: product?.ean ?? "—",
        productName: product?.name ?? "—",
        targetDate: String(record.target_date),
        quantity: Number(record.quantity),
        grossValue: Number(record.gross_value),
      };
    }),
  };
}

export async function fetchSellersBySupervisor(supervisorId?: string): Promise<SalesRep[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const sellers = supervisorId
      ? DEMO_SELLERS.filter((seller) => seller.supervisorId === supervisorId)
      : DEMO_SELLERS;
    return simulateLatency(sellers);
  }

  let query = supabase.from("sales_reps").select("*").eq("role", "seller").order("name");
  if (supervisorId) query = query.eq("supervisor_id", supervisorId);
  const { data, error } = await query;
  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    role: row.role,
    supervisorId: row.supervisor_id,
    status: row.status,
  }));
}
