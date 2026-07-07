"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { PageHeader } from "@/components/ui/page-header";
import { SelectField } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { fetchFilterOptions } from "@/lib/data/reports";
import { DEMO_CUSTOMERS, DEMO_PRODUCTS } from "@/lib/data/demo/catalog";
import { createSeededRandom } from "@/lib/data/demo/random";

type RecommendationLevel = "high" | "medium" | "low" | "none";

interface RecommendationCell {
  customerId: string;
  productId: string;
  level: RecommendationLevel;
}

const LEVEL_STYLES: Record<RecommendationLevel, string> = {
  high: "bg-red/70 hover:bg-red",
  medium: "bg-yellow/60 hover:bg-yellow",
  low: "bg-green/50 hover:bg-green",
  none: "bg-bg3/60",
};

const LEVEL_LABELS: Record<RecommendationLevel, string> = {
  high: "Prioridade alta — cliente sem compra do SKU há 60+ dias",
  medium: "Prioridade média — queda de volume no período",
  low: "Positivado — manter frequência",
  none: "Sem recomendação",
};

const CUSTOMER_SAMPLE_SIZE = 16;
const HIGH_THRESHOLD = 0.82;
const MEDIUM_THRESHOLD = 0.62;
const LOW_THRESHOLD = 0.34;

/**
 * "Batalha Naval": customers × SKUs grid with positivation recommendations.
 * Demo matrix is deterministic; with Supabase connected this screen will read
 * a recommendation RPC (planned for phase 2, per the proposal).
 */
function buildDemoMatrix(sellerSeed: number): RecommendationCell[] {
  const random = createSeededRandom(500 + sellerSeed);
  return DEMO_CUSTOMERS.slice(0, CUSTOMER_SAMPLE_SIZE).flatMap((customer) =>
    DEMO_PRODUCTS.map((product) => {
      const roll = random();
      const level: RecommendationLevel =
        roll > HIGH_THRESHOLD
          ? "high"
          : roll > MEDIUM_THRESHOLD
            ? "medium"
            : roll > LOW_THRESHOLD
              ? "low"
              : "none";
      return { customerId: customer.id, productId: product.id, level };
    }),
  );
}

export default function BattleshipPlannerPage() {
  const [sellerId, setSellerId] = useState("");

  const { data: options, isLoading } = useQuery({
    queryKey: ["filter-options"],
    queryFn: fetchFilterOptions,
  });

  const matrix = useMemo(() => buildDemoMatrix(sellerId.length), [sellerId]);
  const customers = DEMO_CUSTOMERS.slice(0, CUSTOMER_SAMPLE_SIZE);

  const cellByKey = useMemo(() => {
    const map = new Map<string, RecommendationLevel>();
    matrix.forEach((cell) => map.set(`${cell.customerId}:${cell.productId}`, cell.level));
    return map;
  }, [matrix]);

  return (
    <div>
      <PageHeader
        title="Batalha Naval"
        description="Recomendações de positivação por cliente × SKU para a carteira do vendedor"
      />

      <div className="card mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4">
        <SelectField
          label="Vendas (Vendedor)"
          options={(options?.sellers ?? []).map((seller) => ({
            value: seller.id,
            label: seller.name,
          }))}
          value={sellerId}
          onChange={(event) => setSellerId(event.target.value)}
        />
      </div>

      <div className="mb-4 flex flex-wrap gap-4 text-xs text-text2">
        {(Object.keys(LEVEL_LABELS) as RecommendationLevel[]).map((level) => (
          <span key={level} className="flex items-center gap-1.5">
            <span className={clsx("h-3 w-3 rounded-sm", LEVEL_STYLES[level])} />
            {LEVEL_LABELS[level]}
          </span>
        ))}
      </div>

      {isLoading ? (
        <Skeleton className="h-96 w-full rounded-card" />
      ) : (
        <div className="card overflow-x-auto p-4">
          <table className="border-separate border-spacing-1">
            <thead>
              <tr>
                <th className="sticky left-0 bg-card pr-3 text-left text-[11px] font-bold uppercase tracking-wide text-text2">
                  Cliente
                </th>
                {DEMO_PRODUCTS.map((product) => (
                  <th
                    key={product.id}
                    className="h-28 min-w-7 align-bottom text-[10px] font-semibold text-text2"
                  >
                    <span className="inline-block origin-bottom-left -rotate-45 whitespace-nowrap">
                      {product.name}
                    </span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {customers.map((customer) => (
                <tr key={customer.id}>
                  <td className="sticky left-0 max-w-56 truncate bg-card pr-3 text-xs text-text3">
                    {customer.legalName}
                  </td>
                  {DEMO_PRODUCTS.map((product) => {
                    const level =
                      cellByKey.get(`${customer.id}:${product.id}`) ?? "none";
                    return (
                      <td key={product.id}>
                        <div
                          className={clsx(
                            "h-6 w-6 cursor-pointer rounded-sm transition-colors",
                            LEVEL_STYLES[level],
                          )}
                          title={`${customer.legalName} × ${product.name}\n${LEVEL_LABELS[level]}`}
                        />
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
