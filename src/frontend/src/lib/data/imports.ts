import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type { FileImport, FileImportLog, FileTypeConfig, ImportStatus } from "@/types/domain";
import {
  DEMO_FILE_IMPORTS,
  DEMO_FILE_TYPE_CONFIGS,
  DEMO_IMPORT_LOGS,
} from "./demo/tables";
import { simulateLatency } from "./demo/random";

export interface ImportFilters {
  typeId?: string;
  status?: ImportStatus;
  start?: string;
  end?: string;
}

export async function fetchFileImports(filters: ImportFilters): Promise<FileImport[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    // Espelha os filtros da query Supabase sobre o histórico demo.
    const typeName = filters.typeId
      ? DEMO_FILE_TYPE_CONFIGS.find((config) => config.id === filters.typeId)?.name
      : undefined;
    const rows = DEMO_FILE_IMPORTS.filter((row) => {
      if (filters.status && row.status !== filters.status) return false;
      if (typeName && row.typeName !== typeName) return false;
      if (filters.start && row.createdAt < filters.start) return false;
      if (filters.end && row.createdAt > `${filters.end}T23:59:59`) return false;
      return true;
    });
    return simulateLatency(rows);
  }

  let query = supabase
    .from("file_imports")
    .select("id, file_name, sheet_name, status, total_records, processed_records, error_count, created_at, imported_by, file_type_configs(name)")
    .order("created_at", { ascending: false })
    .limit(100);
  if (filters.typeId) query = query.eq("file_type_id", filters.typeId);
  if (filters.status) query = query.eq("status", filters.status);
  if (filters.start) query = query.gte("created_at", filters.start);
  if (filters.end) query = query.lte("created_at", `${filters.end}T23:59:59`);

  const { data, error } = await query;
  if (error) throw error;

  return (data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    return {
      id: String(record.id),
      fileName: String(record.file_name),
      sheetName: (record.sheet_name as string) ?? null,
      typeName: (record.file_type_configs as { name: string } | null)?.name ?? "—",
      status: record.status as ImportStatus,
      totalRecords: Number(record.total_records ?? 0),
      processedRecords: Number(record.processed_records ?? 0),
      errorCount: Number(record.error_count ?? 0),
      createdAt: String(record.created_at),
      importedBy: (record.imported_by as string) ?? null,
    };
  });
}

export async function fetchImportLogs(importId: string): Promise<FileImportLog[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(DEMO_IMPORT_LOGS);

  const { data, error } = await supabase
    .from("file_import_logs")
    .select("*")
    .eq("import_id", importId)
    .order("id")
    .limit(500);
  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: Number(row.id),
    lineNumber: row.line_number,
    level: row.level,
    message: row.message,
    createdAt: row.created_at,
  }));
}

export async function fetchFileTypeConfigs(): Promise<FileTypeConfig[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return simulateLatency(DEMO_FILE_TYPE_CONFIGS);

  const { data, error } = await supabase.from("file_type_configs").select("*").order("code");
  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    targetTable: row.target_table,
    processingRoutine: row.processing_routine,
    fileFormat: row.file_format,
    origin: row.origin,
    status: row.status,
  }));
}

export async function updateFileTypeConfig(input: FileTypeConfig): Promise<void> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    // Modo demo: aplica a edição em memória para refletir na listagem.
    const index = DEMO_FILE_TYPE_CONFIGS.findIndex((config) => config.id === input.id);
    if (index >= 0) DEMO_FILE_TYPE_CONFIGS[index] = { ...input };
    await simulateLatency(null);
    return;
  }

  const { error } = await supabase
    .from("file_type_configs")
    .update({
      code: input.code,
      name: input.name,
      target_table: input.targetTable,
      processing_routine: input.processingRoutine,
      file_format: input.fileFormat,
      origin: input.origin,
      status: input.status,
    })
    .eq("id", input.id);
  if (error) throw error;
}

/**
 * Registers an import and returns its id. The actual file goes to S3 through
 * a presigned URL (cloud repo); the ETL takes over from there.
 */
export async function registerFileImport(input: {
  fileName: string;
  sheetName: string | null;
  fileTypeId: string;
}): Promise<string> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    await simulateLatency(null);
    return "demo-import-id";
  }

  const { data: userData } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("file_imports")
    .insert({
      file_name: input.fileName,
      sheet_name: input.sheetName,
      file_type_id: input.fileTypeId,
      imported_by: userData.user?.id ?? null,
    })
    .select("id")
    .single();
  if (error) throw error;
  return data.id;
}
