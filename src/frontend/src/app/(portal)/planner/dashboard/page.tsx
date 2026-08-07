"use client";

import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";
import { useTheme } from "@/components/theme-provider";
import {
  PlannerDistributorField,
  usePlannerScope,
} from "@/components/planner/planner-scope";
import { Badge } from "@/components/ui/badge";
import { DataTable, type DataTableColumn } from "@/components/ui/data-table";
import { ExportButton } from "@/components/ui/export-button";
import { DateField, SelectField } from "@/components/ui/field";
import { KpiCard } from "@/components/ui/kpi-card";
import { PageHeader } from "@/components/ui/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { ToggleBadges } from "@/components/ui/toggle-badges";
import { fetchPlannerDashboard, fetchPlannerPlans } from "@/lib/data/planner";
import {
  formatCurrency,
  formatDecimal,
  formatInteger,
  formatIsoDate,
  formatPercent,
  formatVariation,
} from "@/lib/format";
import { formatPlanCode, PLANNER_MODEL_LABELS } from "@/lib/planner";
import { CHART_COLORS } from "@/lib/theme";
import type {
  PlannerDashboardDimension,
  PlannerDashboardGroupRow,
} from "@/types/planner";

const WEEKLY_MODELS = new Set(["automatic", "battleship_volume", "battleship_positivation"]);
const PIE_CHART_HEIGHT = 220;
/** Mirrors customer_group_limit in the planner_dashboard RPC. */
const CUSTOMER_GROUP_LIMIT = 50;

const DIMENSION_OPTIONS: { value: PlannerDashboardDimension; label: string }[] = [
  { value: "seller", label: "Por vendedor" },
  { value: "customer", label: "Por cliente" },
  { value: "channel", label: "Por canal" },
  { value: "product", label: "Por SKU" },
];

const GROUP_COLUMNS: DataTableColumn<PlannerDashboardGroupRow>[] = [
  {
    key: "name",
    header: "Grupo",
    render: (row) => row.groupName ?? "—",
    sortValue: (row) => row.groupName,
  },
  {
    key: "lines",
    header: "Planos",
    align: "right",
    render: (row) => formatInteger(row.totalLines),
    sortValue: (row) => row.totalLines,
  },
  {
    key: "achieved",
    header: "Atingidos",
    align: "right",
    render: (row) => formatInteger(row.achievedLines),
    sortValue: (row) => row.achievedLines,
  },
  {
    key: "rate",
    header: "% Atingimento",
    align: "right",
    render: (row) =>
      row.achievementRate === null ? "—" : formatPercent(row.achievementRate),
    sortValue: (row) => row.achievementRate,
  },
  {
    key: "plannedQty",
    header: "Volume planejado",
    align: "right",
    render: (row) =>
      row.plannedQuantity === null ? "—" : formatDecimal(row.plannedQuantity),
    sortValue: (row) => row.plannedQuantity,
  },
  {
    key: "realizedQty",
    header: "Volume realizado",
    align: "right",
    render: (row) =>
      row.realizedQuantity === null ? "—" : formatDecimal(row.realizedQuantity),
    sortValue: (row) => row.realizedQuantity,
  },
  {
    key: "plannedValue",
    header: "Valor planejado",
    align: "right",
    render: (row) => (row.plannedValue === null ? "—" : formatCurrency(row.plannedValue)),
    sortValue: (row) => row.plannedValue,
  },
  {
    key: "realizedValue",
    header: "Valor realizado",
    align: "right",
    render: (row) => (row.realizedValue === null ? "—" : formatCurrency(row.realizedValue)),
    sortValue: (row) => row.realizedValue,
  },
  {
    key: "variation",
    header: "Variação",
    align: "right",
    render: (row) => {
      const variation = row.quantityVariation ?? row.valueVariation;
      return variation === null ? "—" : formatVariation(variation);
    },
    sortValue: (row) => row.quantityVariation ?? row.valueVariation,
  },
];

export default function PlannerDashboardPage() {
  const scope = usePlannerScope();
  const { theme } = useTheme();
  const colors = CHART_COLORS[theme];

  const [planId, setPlanId] = useState("");
  const [evalStart, setEvalStart] = useState("");
  const [evalEnd, setEvalEnd] = useState("");
  const [dimension, setDimension] = useState<PlannerDashboardDimension>("seller");

  const { data: plans } = useQuery({
    queryKey: ["planner-plans", scope.distributorId],
    queryFn: () => fetchPlannerPlans(scope.distributorId),
  });

  // Admins can switch distributors; a plan from the previous one must not
  // stay selected.
  useEffect(() => {
    setPlanId("");
  }, [scope.distributorId]);

  const selectedPlan = (plans ?? []).find((plan) => plan.id === planId);
  const isWeeklyPlan = selectedPlan ? WEEKLY_MODELS.has(selectedPlan.model) : false;

  const { data: dashboard, isLoading } = useQuery({
    queryKey: ["planner-dashboard", planId, evalStart, evalEnd],
    queryFn: () =>
      fetchPlannerDashboard(planId, evalStart || undefined, evalEnd || undefined),
    enabled: Boolean(planId),
  });

  const planOptions = useMemo(
    () =>
      (plans ?? []).map((plan) => ({
        value: plan.id,
        label: `${formatPlanCode(plan.code)} v${plan.version} · ${PLANNER_MODEL_LABELS[plan.model]}${plan.status === "replaced" ? " (substituído)" : ""}`,
      })),
    [plans],
  );

  const groupRows =
    dimension === "seller"
      ? dashboard?.bySeller
      : dimension === "customer"
        ? dashboard?.byCustomer
        : dimension === "channel"
          ? dashboard?.byChannel
          : dashboard?.byProduct;

  const pieData = dashboard
    ? [
        { name: "Atingidos", value: dashboard.summary.achievedLines },
        {
          name: "Não atingidos",
          value: dashboard.summary.totalLines - dashboard.summary.achievedLines,
        },
      ]
    : [];

  function buildExportSections() {
    if (!dashboard) return [];
    return [
      {
        title: `Dashboard ${formatPlanCode(dashboard.plan.code)}`,
        rows: [
          {
            Planificador: formatPlanCode(dashboard.plan.code),
            Modelo: PLANNER_MODEL_LABELS[dashboard.plan.model],
            Versão: dashboard.plan.version,
            "Período de avaliação": `${dashboard.evalPeriod.startDate} a ${dashboard.evalPeriod.endDate}`,
            "Total de planos": dashboard.summary.totalLines,
            Atingidos: dashboard.summary.achievedLines,
            "% Atingimento":
              dashboard.summary.achievementRate === null
                ? ""
                : formatPercent(dashboard.summary.achievementRate),
          },
        ],
      },
      {
        title: DIMENSION_OPTIONS.find((option) => option.value === dimension)?.label ?? "",
        rows: (groupRows ?? []).map((row) => ({
          Grupo: row.groupName ?? "—",
          Planos: row.totalLines,
          Atingidos: row.achievedLines,
          "% Atingimento":
            row.achievementRate === null ? "" : formatPercent(row.achievementRate),
          "Volume planejado": row.plannedQuantity ?? "",
          "Volume realizado": row.realizedQuantity ?? "",
          "Valor planejado": row.plannedValue ?? "",
          "Valor realizado": row.realizedValue ?? "",
          Variação:
            (row.quantityVariation ?? row.valueVariation) === null
              ? ""
              : formatVariation((row.quantityVariation ?? row.valueVariation) as number),
        })),
      },
    ];
  }

  return (
    <div>
      <PageHeader
        title="Dashboard do Planner"
        description="Avaliação planejado × realizado de cada planificador gerado, no estilo Fast Facts."
        actions={
          dashboard ? (
            <ExportButton
              fileName={`dashboard-${formatPlanCode(dashboard.plan.code)}`}
              getSections={buildExportSections}
            />
          ) : undefined
        }
      />

      <div className="card mb-5 grid gap-3 p-4 md:grid-cols-4">
        <PlannerDistributorField scope={scope} />
        <SelectField
          label="Planificador"
          allLabel="Selecione"
          value={planId}
          onChange={(event) => setPlanId(event.target.value)}
          options={planOptions}
        />
        {planId && !isWeeklyPlan ? (
          <>
            <DateField
              label="Avaliar de"
              value={evalStart}
              onChange={(event) => setEvalStart(event.target.value)}
            />
            <DateField
              label="Avaliar até"
              value={evalEnd}
              onChange={(event) => setEvalEnd(event.target.value)}
            />
            <p className="self-end pb-2 text-xs text-text2 md:col-span-4">
              Deixe as datas vazias para avaliar no prazo de execução definido na geração do
              plano
              {dashboard
                ? ` (avaliando ${formatIsoDate(dashboard.evalPeriod.startDate)} a ${formatIsoDate(dashboard.evalPeriod.endDate)})`
                : ""}
              .
            </p>
          </>
        ) : null}
        {planId && isWeeklyPlan ? (
          <p className="self-end pb-2 text-xs text-text2 md:col-span-2">
            Planos semanais são avaliados dentro das datas de cada semana configurada.
          </p>
        ) : null}
      </div>

      {!planId ? (
        <p className="text-sm text-text2">
          Selecione um planificador para avaliar. Cada linha do plano conta como um
          &quot;plano&quot; — o dashboard mostra quantos foram atingidos, os melhores e
          piores vendedores e a variação por cliente, canal e SKU.
        </p>
      ) : isLoading || !dashboard ? (
        <div className="grid gap-3">
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-64 w-full" />
        </div>
      ) : (
        <div className="grid gap-5">
          <div className="grid grid-cols-[repeat(auto-fit,minmax(min(100%,13.5rem),1fr))] gap-3">
            <KpiCard
              label="Planos (linhas)"
              value={formatInteger(dashboard.summary.totalLines)}
            />
            <KpiCard
              label="Planos atingidos"
              value={formatInteger(dashboard.summary.achievedLines)}
              footer={
                dashboard.summary.achievementRate === null
                  ? undefined
                  : `${formatPercent(dashboard.summary.achievementRate)} de atingimento`
              }
            />
            <KpiCard
              label="Volume não realizado"
              value={
                dashboard.summary.missedQuantity === null
                  ? "—"
                  : formatDecimal(dashboard.summary.missedQuantity)
              }
            />
            <KpiCard
              label="Valor não realizado"
              value={
                dashboard.summary.missedValue === null
                  ? "—"
                  : formatCurrency(dashboard.summary.missedValue)
              }
            />
          </div>

          <div className="grid gap-4 lg:grid-cols-3">
            <div className="card p-4">
              <h2 className="mb-2 text-sm font-bold text-text1">Atingido × não atingido</h2>
              <ResponsiveContainer width="100%" height={PIE_CHART_HEIGHT}>
                <PieChart>
                  <Pie
                    data={pieData}
                    dataKey="value"
                    nameKey="name"
                    innerRadius={48}
                    outerRadius={80}
                    strokeWidth={0}
                  >
                    <Cell fill={colors.seriesCurrent} />
                    <Cell fill={colors.seriesPrevious} />
                  </Pie>
                  <Tooltip
                    contentStyle={{
                      backgroundColor: colors.tooltipBg,
                      border: `1px solid ${colors.tooltipBorder}`,
                      borderRadius: 8,
                      color: colors.tooltipText,
                      fontSize: 12,
                    }}
                    formatter={(value: number, name: string) => [formatInteger(value), name]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </div>

            <SellerHighlightCard
              title="Melhor vendedor"
              row={dashboard.bestSeller}
              badgeVariant="green"
            />
            <SellerHighlightCard
              title="Pior vendedor"
              row={dashboard.worstSeller}
              badgeVariant="red"
            />
          </div>

          <div className="grid gap-3">
            <ToggleBadges
              options={DIMENSION_OPTIONS}
              value={dimension}
              onChange={setDimension}
            />
            {dimension === "customer" && (groupRows?.length ?? 0) >= CUSTOMER_GROUP_LIMIT ? (
              <p className="text-xs text-text2">
                Mostrando os {CUSTOMER_GROUP_LIMIT} clientes com maior valor planejado.
              </p>
            ) : null}
            <DataTable
              columns={GROUP_COLUMNS}
              rows={groupRows ?? []}
              rowKey={(row) => row.groupId ?? row.groupName ?? "—"}
              emptyMessage="Sem dados para o recorte selecionado"
            />
          </div>
        </div>
      )}
    </div>
  );
}

function SellerHighlightCard({
  title,
  row,
  badgeVariant,
}: {
  title: string;
  row: PlannerDashboardGroupRow | null;
  badgeVariant: "green" | "red";
}) {
  return (
    <div className="card p-4">
      <h2 className="mb-2 text-sm font-bold text-text1">{title}</h2>
      {!row ? (
        <p className="text-sm text-text2">Sem vendedores avaliados neste plano.</p>
      ) : (
        <div className="grid gap-2">
          <div className="flex items-center gap-2">
            <span className="text-base font-bold text-text1">{row.groupName ?? "—"}</span>
            <Badge variant={badgeVariant}>
              {row.achievementRate === null ? "—" : formatPercent(row.achievementRate)}
            </Badge>
          </div>
          <p className="text-xs text-text2">
            {formatInteger(row.achievedLines)} de {formatInteger(row.totalLines)} planos
            atingidos
          </p>
        </div>
      )}
    </div>
  );
}
