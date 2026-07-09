import { Badge } from "@/components/ui/badge";
import {
  getImportLayoutSpec,
  getImportPrerequisiteSpecs,
  getMissingImportPrerequisiteCodes,
} from "@/lib/import-layouts";
import type { FileTypeConfig } from "@/types/domain";

interface ImportLayoutHelpProps {
  config: FileTypeConfig | null;
  completedImportCodes?: Set<string>;
  emptyMessage?: string;
}

function ColumnList({ columns }: { columns: string[] }) {
  if (columns.length === 0) return <span className="text-xs text-text2">Nenhuma.</span>;

  return (
    <div className="flex flex-wrap gap-1.5">
      {columns.map((column) => (
        <Badge key={column} variant="neutral">
          {column}
        </Badge>
      ))}
    </div>
  );
}

export function ImportLayoutHelp({
  config,
  completedImportCodes,
  emptyMessage,
}: ImportLayoutHelpProps) {
  const spec = getImportLayoutSpec(config);

  if (!spec) {
    return (
      <div className="rounded-md border border-line bg-bg px-3 py-2 text-sm text-text2">
        {emptyMessage ?? "Selecione um tipo para ver o layout esperado."}
      </div>
    );
  }

  const statusLabel = spec.status === "ready" ? "Suportado" : "Planejado";
  const statusVariant = spec.status === "ready" ? "green" : "yellow";
  const prerequisiteSpecs = getImportPrerequisiteSpecs(spec);
  const missingPrerequisiteCodes = completedImportCodes
    ? new Set(getMissingImportPrerequisiteCodes(spec, completedImportCodes))
    : null;

  return (
    <div className="rounded-md border border-line bg-bg p-3">
      <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
        <div>
          <div className="text-sm font-semibold text-text1">{spec.title}</div>
          <div className="text-xs text-text2">{spec.screen}</div>
        </div>
        <Badge variant={statusVariant}>{statusLabel}</Badge>
      </div>

      <p className="mb-3 text-xs text-text2">{spec.summary}</p>

      <div className="space-y-3">
        <div>
          <div className="mb-1 text-xs font-semibold uppercase text-text2">
            Pré-requisitos
          </div>
          {prerequisiteSpecs.length > 0 ? (
            <div className="flex flex-wrap gap-1.5">
              {prerequisiteSpecs.map((prerequisite) => {
                const isMissing = missingPrerequisiteCodes?.has(prerequisite.code) ?? false;
                const variant = isMissing ? "yellow" : "neutral";
                const suffix = missingPrerequisiteCodes ? (isMissing ? " pendente" : " ok") : "";

                return (
                  <Badge key={prerequisite.code} variant={variant}>
                    {prerequisite.title}{suffix}
                  </Badge>
                );
              })}
            </div>
          ) : (
            <span className="text-xs text-text2">Nenhum. Pode ser importado primeiro.</span>
          )}
        </div>

        <div>
          <div className="mb-1 text-xs font-semibold uppercase text-text2">
            Colunas obrigatórias
          </div>
          <ColumnList columns={spec.requiredColumns} />
        </div>

        <div>
          <div className="mb-1 text-xs font-semibold uppercase text-text2">
            Colunas opcionais
          </div>
          <ColumnList columns={spec.optionalColumns} />
        </div>

        {spec.notes.length > 0 ? (
          <div className="space-y-1 text-xs text-text2">
            {spec.notes.map((note) => (
              <p key={note}>{note}</p>
            ))}
          </div>
        ) : null}
      </div>
    </div>
  );
}
