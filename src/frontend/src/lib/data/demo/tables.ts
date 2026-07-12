import type {
  FileImport,
  FileImportLog,
  FileTypeConfig,
  SellInRow,
  SellOutRow,
  StockRow,
  TargetRow,
} from "@/types/domain";
import { getMonthStart } from "@/lib/periods";
import {
  DEMO_CUSTOMERS,
  DEMO_DISTRIBUTORS,
  DEMO_PRODUCTS,
} from "./catalog";
import { createSeededRandom } from "./random";

const SELL_OUT_ROW_COUNT = 1240;
const SELL_IN_ROW_COUNT = 320;
const AVG_UNIT_PRICE = 27.4;

function isoDateWithinCurrentMonth(random: () => number): string {
  const now = new Date();
  const day = 1 + Math.floor(random() * now.getDate());
  return `${getMonthStart().slice(0, 8)}${String(day).padStart(2, "0")}`;
}

export const DEMO_SELL_OUT_ROWS: SellOutRow[] = (() => {
  const random = createSeededRandom(101);
  return Array.from({ length: SELL_OUT_ROW_COUNT }, (_, index) => {
    const product = DEMO_PRODUCTS[Math.floor(random() * DEMO_PRODUCTS.length)];
    const quantity = 1 + Math.floor(random() * 18);
    return {
      id: index + 1,
      distributorName: DEMO_DISTRIBUTORS[index % DEMO_DISTRIBUTORS.length].name,
      customerName: DEMO_CUSTOMERS[Math.floor(random() * DEMO_CUSTOMERS.length)].legalName,
      ean: product.ean,
      productName: product.name,
      invoiceDate: isoDateWithinCurrentMonth(random),
      quantity,
      grossValue: Math.round(quantity * AVG_UNIT_PRICE * (0.8 + random() * 0.6) * 100) / 100,
    };
  });
})();

export const DEMO_SELL_IN_ROWS: SellInRow[] = (() => {
  const random = createSeededRandom(202);
  return Array.from({ length: SELL_IN_ROW_COUNT }, (_, index) => {
    const product = DEMO_PRODUCTS[Math.floor(random() * DEMO_PRODUCTS.length)];
    const quantity = 200 + Math.floor(random() * 1400);
    return {
      id: index + 1,
      distributorName: DEMO_DISTRIBUTORS[index % DEMO_DISTRIBUTORS.length].name,
      ean: product.ean,
      productName: product.name,
      invoiceDate: isoDateWithinCurrentMonth(random),
      quantity,
      grossValue: Math.round(quantity * AVG_UNIT_PRICE * 0.78 * 100) / 100,
    };
  });
})();

export const DEMO_STOCK_ROWS: StockRow[] = (() => {
  const snapshotDate = new Date().toISOString().slice(0, 10);
  const rowsByKey = new Map<string, StockRow>();

  for (const row of DEMO_SELL_IN_ROWS) {
    const key = `${row.distributorName}:${row.ean}`;
    const current = rowsByKey.get(key) ?? {
      id: key,
      distributorName: row.distributorName,
      ean: row.ean,
      productName: row.productName,
      snapshotDate,
      quantity: 0,
      grossValue: 0,
    };
    current.quantity += row.quantity;
    current.grossValue += row.grossValue;
    rowsByKey.set(key, current);
  }

  for (const row of DEMO_SELL_OUT_ROWS) {
    const key = `${row.distributorName}:${row.ean}`;
    const current = rowsByKey.get(key) ?? {
      id: key,
      distributorName: row.distributorName,
      ean: row.ean,
      productName: row.productName,
      snapshotDate,
      quantity: 0,
      grossValue: 0,
    };
    current.quantity -= row.quantity;
    rowsByKey.set(key, current);
  }

  return Array.from(rowsByKey.values()).map((row) => ({
    ...row,
    grossValue: Math.round(row.grossValue * 100) / 100,
  }));
})();

export const DEMO_TARGET_ROWS: TargetRow[] = (() => {
  const random = createSeededRandom(404);
  let id = 0;
  return DEMO_CUSTOMERS.flatMap((customer) =>
    DEMO_PRODUCTS.filter(() => random() < 0.4).map((product) => {
      id += 1;
      const quantity = 40 + Math.floor(random() * 60);
      return {
        id,
        customerName: customer.legalName,
        ean: product.ean,
        productName: product.name,
        targetDate: getMonthStart(),
        quantity,
        grossValue: Math.round(quantity * AVG_UNIT_PRICE * 1.02 * 100) / 100,
      };
    }),
  );
})();

export const DEMO_FILE_TYPE_CONFIGS: FileTypeConfig[] = [
  { id: "ftc-1", code: "SELL_OUT", name: "Sell Out", targetTable: "sell_out", processingRoutine: "process_sell_out_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-2", code: "SELL_IN", name: "Sell In", targetTable: "sell_in", processingRoutine: "process_sell_in_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-3", code: "CUSTOMERS", name: "Clientes", targetTable: "customers", processingRoutine: "process_customers_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-4", code: "PRODUCTS", name: "Hier. Produtos", targetTable: "products", processingRoutine: "process_products_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-5", code: "SELLERS", name: "Vendedores", targetTable: "sales_reps", processingRoutine: "process_sellers_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-6", code: "TARGETS", name: "Meta", targetTable: "sales_targets", processingRoutine: "process_targets_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-7", code: "STOCK", name: "Estoque", targetTable: "stock_snapshots", processingRoutine: "upsert_stock", fileFormat: "csv", origin: "upload", status: "inactive" },
  { id: "ftc-8", code: "PLANNER", name: "Batalha Naval", targetTable: "planner_entries", processingRoutine: "upsert_planner_entries", fileFormat: "xlsx", origin: "upload", status: "inactive" },
];

/** Fontes cíclicas do histórico demo, para o filtro "Tipo Arquivo" ter resultados variados. */
const DEMO_IMPORT_SOURCES = [
  { filePrefix: "produtos", typeName: "Hier. Produtos", sheetName: "Produtos" },
  { filePrefix: "vendedores", typeName: "Vendedores", sheetName: "Planilha1" },
  { filePrefix: "clientes", typeName: "Clientes", sheetName: "Planilha1" },
  { filePrefix: "meta", typeName: "Meta", sheetName: "Planilha1" },
  { filePrefix: "sellin", typeName: "Sell In", sheetName: "Planilha1" },
  { filePrefix: "sellout", typeName: "Sell Out", sheetName: "Planilha1" },
] as const;

export const DEMO_FILE_IMPORTS: FileImport[] = (() => {
  const now = Date.now();
  const dayMs = 86_400_000;
  return Array.from({ length: 9 }, (_, index) => {
    const source = DEMO_IMPORT_SOURCES[index % DEMO_IMPORT_SOURCES.length];
    const date = new Date(now - index * dayMs);
    const total = 18_000 + index * 977;
    return {
      id: `import-${index + 1}`,
      fileName: `${source.filePrefix}_${date.toISOString().slice(0, 10).replaceAll("-", "")}.xlsx`,
      sheetName: source.sheetName,
      typeName: source.typeName,
      status: "completed",
      totalRecords: total,
      processedRecords: total,
      errorCount: 0,
      createdAt: date.toISOString(),
      importedBy: "geraldo@barkreply.com",
    };
  });
})();

export const DEMO_IMPORT_LOGS: FileImportLog[] = [];
