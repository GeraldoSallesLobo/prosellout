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
  const random = createSeededRandom(303);
  let id = 0;
  return DEMO_DISTRIBUTORS.flatMap((distributor) =>
    DEMO_PRODUCTS.map((product) => {
      id += 1;
      const quantity = 50 + Math.floor(random() * 800);
      return {
        id,
        distributorName: distributor.name,
        ean: product.ean,
        productName: product.name,
        snapshotDate: new Date().toISOString().slice(0, 10),
        quantity,
        grossValue: Math.round(quantity * AVG_UNIT_PRICE * 0.78 * 100) / 100,
      };
    }),
  );
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
  { id: "ftc-1", code: "SELL_OUT", name: "Sell Out Distribuidor", targetTable: "sell_out", processingRoutine: "process_sell_out_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-2", code: "SELL_IN", name: "Sell In Indústria", targetTable: "sell_in", processingRoutine: "process_sell_in_staging", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-3", code: "CUSTOMERS", name: "Base de Clientes", targetTable: "customers", processingRoutine: "upsert_customers", fileFormat: "csv", origin: "upload", status: "active" },
  { id: "ftc-4", code: "TARGETS", name: "Metas por Cliente/SKU", targetTable: "sales_targets", processingRoutine: "upsert_targets", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-5", code: "STOCK", name: "Estoque Distribuidor", targetTable: "stock_snapshots", processingRoutine: "upsert_stock", fileFormat: "csv", origin: "upload", status: "inactive" },
  { id: "ftc-6", code: "PLANNER", name: "Planificador", targetTable: "planner_entries", processingRoutine: "upsert_planner_entries", fileFormat: "xlsx", origin: "upload", status: "active" },
  { id: "ftc-7", code: "PRODUCTS", name: "Base de Produtos", targetTable: "products", processingRoutine: "upsert_products", fileFormat: "xlsx", origin: "upload", status: "active" },
];

/** Fontes cíclicas do histórico demo, para o filtro "Tipo Arquivo" ter resultados variados. */
const DEMO_IMPORT_SOURCES = [
  { filePrefix: "sellout", typeName: "Sell Out Distribuidor", sheetName: "Base" },
  { filePrefix: "produtos", typeName: "Base de Produtos", sheetName: "Produtos" },
  { filePrefix: "planificador", typeName: "Planificador", sheetName: "Plano" },
] as const;

export const DEMO_FILE_IMPORTS: FileImport[] = (() => {
  const now = Date.now();
  const dayMs = 86_400_000;
  return Array.from({ length: 9 }, (_, index) => {
    const source = DEMO_IMPORT_SOURCES[index % DEMO_IMPORT_SOURCES.length];
    const date = new Date(now - index * dayMs);
    const total = 18_000 + index * 977;
    const hasErrors = index === 0;
    return {
      id: `import-${index + 1}`,
      fileName: `${source.filePrefix}_${date.toISOString().slice(0, 10).replaceAll("-", "")}.xlsx`,
      sheetName: source.sheetName,
      typeName: source.typeName,
      status: hasErrors ? "completed_with_errors" : "completed",
      totalRecords: total,
      processedRecords: total - (hasErrors ? 12 : 0),
      errorCount: hasErrors ? 12 : 0,
      createdAt: date.toISOString(),
      importedBy: "geraldo@barkreply.com",
    };
  });
})();

export const DEMO_IMPORT_LOGS: FileImportLog[] = Array.from({ length: 12 }, (_, index) => ({
  id: index + 1,
  lineNumber: 40 + index * 3,
  level: "error",
  message: `unknown product ean: 78910001999${index}`,
  createdAt: new Date().toISOString(),
}));
