import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { UPLOAD_API_URL } from "@/lib/env";
import { getImportDisplayName } from "@/lib/import-layouts";
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

const UPLOADABLE_TARGET_TABLES = new Set([
  "sell_out",
  "sell_in",
  "customers",
  "products",
  "sales_reps",
  "sales_targets",
]);

const READY_IMPORT_STATUSES = new Set<ImportStatus>(["completed", "completed_with_errors"]);

export function canUploadFileType(config: FileTypeConfig): boolean {
  return config.status === "active" && UPLOADABLE_TARGET_TABLES.has(config.targetTable);
}

export async function fetchCompletedImportCodes(): Promise<string[]> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) {
    const codeByTypeName = new Map(
      DEMO_FILE_TYPE_CONFIGS.map((config) => [config.name, config.code]),
    );
    const completedCodes = DEMO_FILE_IMPORTS.flatMap((row) => {
      if (!READY_IMPORT_STATUSES.has(row.status)) return [];
      const code = codeByTypeName.get(row.typeName);
      return code ? [code] : [];
    });
    return simulateLatency(Array.from(new Set(completedCodes)));
  }

  const { data, error } = await supabase
    .from("file_imports")
    .select("status, file_type_configs(code)")
    .in("status", Array.from(READY_IMPORT_STATUSES));
  if (error) throw error;

  const completedCodes = (data ?? []).flatMap((row) => {
    const record = row as Record<string, unknown>;
    const typeConfig = record.file_type_configs as { code?: string } | null;
    return typeConfig?.code ? [typeConfig.code] : [];
  });

  return Array.from(new Set(completedCodes));
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
    .select("id, file_name, sheet_name, status, total_records, processed_records, error_count, created_at, imported_by, file_type_configs(code, name, target_table)")
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
    const typeConfig = record.file_type_configs as {
      code?: string;
      name?: string;
      target_table?: string;
    } | null;
    const typeName = typeConfig?.code && typeConfig.name && typeConfig.target_table
      ? getImportDisplayName({
          code: typeConfig.code,
          name: typeConfig.name,
          targetTable: typeConfig.target_table,
        })
      : "—";

    return {
      id: String(record.id),
      fileName: String(record.file_name),
      sheetName: (record.sheet_name as string) ?? null,
      typeName,
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

async function fetchCurrentDistributorId(): Promise<string> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return "demo-distributor-id";

  const { data, error } = await supabase
    .from("distributor_users")
    .select("distributor_id")
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(1)
    .single();
  if (error) throw error;

  return String(data.distributor_id);
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
  const distributorId = await fetchCurrentDistributorId();
  const { data, error } = await supabase
    .from("file_imports")
    .insert({
      file_name: input.fileName,
      sheet_name: input.sheetName,
      file_type_id: input.fileTypeId,
      imported_by: userData.user?.id ?? null,
      distributor_id: distributorId,
    })
    .select("id")
    .single();
  if (error) throw error;
  return data.id;
}

async function uploadFileToStorage(importId: string, file: File): Promise<void> {
  const supabase = getSupabaseBrowserClient();
  if (!supabase) return;
  if (!UPLOAD_API_URL) {
    throw new Error("A URL da API de upload não está configurada.");
  }

  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw sessionError;

  const accessToken = sessionData.session?.access_token;
  if (!accessToken) throw new Error("Sessão autenticada ausente.");

  const uploadUrlResponse = await fetch(UPLOAD_API_URL, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      importId,
      fileName: file.name,
      contentType: file.type || "application/octet-stream",
    }),
  });

  if (!uploadUrlResponse.ok) {
    const responseText = await uploadUrlResponse.text();
    throw new Error(responseText || "Could not create upload URL");
  }

  const { uploadUrl } = (await uploadUrlResponse.json()) as { uploadUrl: string };
  const uploadResponse = await fetch(uploadUrl, {
    method: "PUT",
    headers: {
      "content-type": file.type || "application/octet-stream",
    },
    body: file,
  });

  if (!uploadResponse.ok) {
    throw new Error("Could not upload file");
  }
}

export async function registerAndUploadFileImport(input: {
  file: File;
  sheetName: string | null;
  fileTypeId: string;
}): Promise<string> {
  const supabase = getSupabaseBrowserClient();
  if (supabase && !UPLOAD_API_URL) {
    throw new Error("A URL da API de upload não está configurada.");
  }

  const importId = await registerFileImport({
    fileName: input.file.name,
    sheetName: input.sheetName,
    fileTypeId: input.fileTypeId,
  });

  await uploadFileToStorage(importId, input.file);
  return importId;
}
