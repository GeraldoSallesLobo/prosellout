"use client";

import { Download } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toast";

interface ExportButtonProps {
  fileName: string;
  /** Returns the rows to export (already filtered). */
  getRows?: () => Record<string, unknown>[];
  getSections?: () => ExportSection[];
}

export interface ExportSection {
  title?: string;
  rows: Record<string, unknown>[];
}

const CSV_SEPARATOR = ";";

/** Caracteres que o Excel interpreta como início de fórmula (CSV injection). */
const FORMULA_TRIGGER_PATTERN = /^[=+\-@\t\r]/;

function toCsvCell(value: unknown): string {
  let text = value === null || value === undefined ? "" : String(value);
  // Neutraliza injeção de fórmula ao abrir o CSV em Excel/Sheets.
  if (FORMULA_TRIGGER_PATTERN.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

function buildCsvRows(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return "";
  const headers = Object.keys(rows[0]);
  const lines = rows.map((row) =>
    headers.map((header) => toCsvCell(row[header])).join(CSV_SEPARATOR),
  );
  return [headers.map(toCsvCell).join(CSV_SEPARATOR), ...lines].join("\n");
}

function buildCsvSection(section: ExportSection): string {
  const csvRows = buildCsvRows(section.rows);
  return [section.title ? toCsvCell(section.title) : "", csvRows]
    .filter((part) => part.length > 0)
    .join("\n");
}

function buildCsv(sections: ExportSection[]): string {
  return sections
    .map(buildCsvSection)
    .filter((section) => section.length > 0)
    .join("\n\n");
}

/** Export with user feedback, as required by the proposal (toast + download). */
export function ExportButton({ fileName, getRows, getSections }: ExportButtonProps) {
  const [isExporting, setIsExporting] = useState(false);
  const { showToast } = useToast();

  function handleExport() {
    setIsExporting(true);
    try {
      const sections = getSections?.() ?? [{ rows: getRows?.() ?? [] }];
      if (!sections.some((section) => section.rows.length > 0)) {
        showToast("info", "Nada para exportar com os filtros atuais.");
        return;
      }
      const csv = buildCsv(sections);
      const blob = new Blob([`﻿${csv}`], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `${fileName}.csv`;
      anchor.click();
      URL.revokeObjectURL(url);
      showToast("success", `Exportação concluída: ${fileName}.csv`);
    } catch {
      showToast("error", "Falha ao exportar. Tente novamente.");
    } finally {
      setIsExporting(false);
    }
  }

  return (
    <Button variant="secondary" onClick={handleExport} disabled={isExporting}>
      <Download size={14} />
      {isExporting ? "Exportando..." : "Exportar"}
    </Button>
  );
}
