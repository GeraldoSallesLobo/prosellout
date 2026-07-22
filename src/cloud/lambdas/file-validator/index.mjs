import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { parse } from "csv-parse";
import { stringify } from "csv-stringify/sync";
import ExcelJS from "exceljs";
import pg from "pg";

const PART_MAX_ROWS = Number(process.env.PART_MAX_ROWS ?? 50000);

const s3 = new S3Client({});
const sqs = new SQSClient({});
const EXCEL_DATE_EPOCH_UTC_MS = Date.UTC(1899, 11, 30);
const MAX_SUPPORTED_EXCEL_DATE_SERIAL = 60000;
const MILLISECONDS_PER_DAY = 86_400_000;

/**
 * Canonical column order per target table. Must match the staging tables in
 * the database repo (minus import_id/line_number, which are prepended here).
 */
const TABLE_SPECS = {
  sell_out: {
    stagingTable: "staging_sell_out",
    processFunction: "process_sell_out_staging",
    columns: [
      "distributor_code", "customer_pdv_code", "customer_cnpj", "sales_rep_code",
      "product_ean", "invoice_number", "invoice_date", "delivery_date",
      "quantity", "gross_value", "unit_cost", "channel_name", "cluster_name",
    ],
    optionalColumns: [
      "customer_pdv_code", "customer_cnpj", "invoice_number", "delivery_date", "unit_cost",
      "channel_name", "cluster_name",
    ],
    positionalFallbacks: {
      channel_name: 9,
      cluster_name: 10,
    },
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      codigo_distribuidor: "distributor_code",
      cod_pdv: "customer_pdv_code",
      codigo_pdv: "customer_pdv_code",
      pdv: "customer_pdv_code",
      cnpj: "customer_cnpj",
      cnpj_cliente: "customer_cnpj",
      vendedor: "sales_rep_code",
      cod_vendedor: "sales_rep_code",
      codigo_vendedor: "sales_rep_code",
      ean: "product_ean",
      nf: "invoice_number",
      nota_fiscal: "invoice_number",
      numero_nf: "invoice_number",
      data: "invoice_date",
      data_de_faturamento: "invoice_date",
      data_faturamento: "invoice_date",
      data_de_entrega: "delivery_date",
      data_entrega: "delivery_date",
      entrega: "delivery_date",
      volume: "quantity",
      volume_total_de_unidades_nf: "quantity",
      quantidade: "quantity",
      qtd: "quantity",
      valor: "gross_value",
      valor_total_r_nf: "gross_value",
      valor_bruto: "gross_value",
      custo: "unit_cost",
      custo_unitario: "unit_cost",
      canal_do_pdv: "channel_name",
      canal: "channel_name",
      cluster: "cluster_name",
    },
  },
  sell_in: {
    stagingTable: "staging_sell_in",
    processFunction: "process_sell_in_staging",
    columns: [
      "distributor_code", "product_ean", "invoice_number",
      "invoice_date", "quantity", "gross_value", "unit_cost",
    ],
    optionalColumns: ["invoice_number", "unit_cost"],
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      ean: "product_ean",
      nf: "invoice_number",
      nota_fiscal: "invoice_number",
      data: "invoice_date",
      data_de_faturamento: "invoice_date",
      data_faturamento: "invoice_date",
      volume: "quantity",
      volume_total_de_unidades_nf: "quantity",
      quantidade: "quantity",
      qtd: "quantity",
      valor: "gross_value",
      valor_total_r_nf: "gross_value",
      custo: "unit_cost",
    },
  },
  sell_in_targets: {
    stagingTable: "staging_sell_in_targets",
    processFunction: "process_sell_in_targets_staging",
    columns: [
      "distributor_code", "product_ean", "target_date", "quantity", "gross_value",
    ],
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      ean: "product_ean",
      data: "target_date",
      data_de_faturamento: "target_date",
      data_faturamento: "target_date",
      volume: "quantity",
      volume_total_de_unidades_nf: "quantity",
      quantidade: "quantity",
      qtd: "quantity",
      valor: "gross_value",
      valor_total_r_nf: "gross_value",
      valor_bruto: "gross_value",
    },
  },
  customers: {
    stagingTable: "staging_customers",
    processFunction: "process_customers_staging",
    columns: [
      "distributor_code", "customer_pdv_code", "customer_cnpj", "legal_name",
      "trade_name", "address", "district", "city", "state", "zip_code",
      "channel_name", "cluster_name",
    ],
    optionalColumns: [
      "customer_cnpj", "trade_name", "address", "district", "city", "state",
      "zip_code", "channel_name", "cluster_name",
    ],
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      codigo_distribuidor: "distributor_code",
      cod_pdv: "customer_pdv_code",
      codigo_pdv: "customer_pdv_code",
      pdv: "customer_pdv_code",
      cnpj_cpf: "customer_cnpj",
      cnpj: "customer_cnpj",
      cpf: "customer_cnpj",
      razao_social: "legal_name",
      nome_fantasia: "trade_name",
      endereco: "address",
      bairro: "district",
      cidade: "city",
      uf: "state",
      estado: "state",
      cep: "zip_code",
      canal_do_pdv: "channel_name",
      canal: "channel_name",
      cluster: "cluster_name",
    },
  },
  products: {
    stagingTable: "staging_products",
    processFunction: "process_products_staging",
    columns: [
      "distributor_code", "product_ean", "product_name", "box_count",
      "units_per_pack", "subcategory_name", "category_name",
      "macro_category_name", "sku_code",
    ],
    optionalColumns: ["box_count", "units_per_pack", "sku_code"],
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      codigo_distribuidor: "distributor_code",
      ean: "product_ean",
      descricao: "product_name",
      produto: "product_name",
      nome_produto: "product_name",
      caixa: "box_count",
      unidades: "units_per_pack",
      unidades_por_caixa: "units_per_pack",
      subcategoria: "subcategory_name",
      categoria: "category_name",
      macrocategoria: "macro_category_name",
      cod_sku: "sku_code",
      codigo_sku: "sku_code",
      sku: "sku_code",
    },
  },
  sales_reps: {
    stagingTable: "staging_sellers",
    processFunction: "process_sellers_staging",
    columns: [
      "distributor_code", "seller_code", "seller_name", "portfolio_size",
      "supervisor_code", "supervisor_name", "manager_code", "manager_name",
    ],
    optionalColumns: ["portfolio_size", "supervisor_name", "manager_code", "manager_name"],
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      codigo_distribuidor: "distributor_code",
      cod_vendedor: "seller_code",
      codigo_vendedor: "seller_code",
      vendedor: "seller_code",
      nome_vendedor: "seller_name",
      quantidade_clientes_carteira: "portfolio_size",
      carteira: "portfolio_size",
      portfolio_size: "portfolio_size",
      cod_supervisor: "supervisor_code",
      codigo_supervisor: "supervisor_code",
      supervisor: "supervisor_code",
      nome_supervisor: "supervisor_name",
      cod_gerente: "manager_code",
      codigo_gerente: "manager_code",
      gerente: "manager_code",
      nome_gerente: "manager_name",
    },
  },
  sales_targets: {
    stagingTable: "staging_targets",
    processFunction: "process_targets_staging",
    columns: [
      "distributor_code", "customer_pdv_code", "customer_cnpj", "sales_rep_code",
      "product_ean", "target_date", "delivery_date", "quantity", "gross_value",
      "channel_name", "cluster_name",
    ],
    optionalColumns: ["customer_cnpj", "delivery_date", "channel_name", "cluster_name"],
    positionalFallbacks: {
      channel_name: 9,
      cluster_name: 10,
    },
    aliases: {
      distribuidor: "distributor_code",
      cnpj_distribuidor: "distributor_code",
      cod_distribuidor: "distributor_code",
      codigo_distribuidor: "distributor_code",
      cod_pdv: "customer_pdv_code",
      codigo_pdv: "customer_pdv_code",
      pdv: "customer_pdv_code",
      cnpj: "customer_cnpj",
      cnpj_cliente: "customer_cnpj",
      vendedor: "sales_rep_code",
      cod_vendedor: "sales_rep_code",
      codigo_vendedor: "sales_rep_code",
      ean: "product_ean",
      data: "target_date",
      data_de_faturamento: "target_date",
      data_faturamento: "target_date",
      data_de_entrega: "delivery_date",
      data_entrega: "delivery_date",
      entrega: "delivery_date",
      volume: "quantity",
      volume_total_de_unidades_nf: "quantity",
      quantidade: "quantity",
      qtd: "quantity",
      valor: "gross_value",
      valor_total_r_nf: "gross_value",
      valor_bruto: "gross_value",
      canal_do_pdv: "channel_name",
      canal: "channel_name",
      cluster: "cluster_name",
    },
  },
};

function getCellValue(value) {
  if (value === null || value === undefined) return "";
  if (value instanceof Date) return value;
  if (Array.isArray(value)) return value.map(getCellValue).join("");
  if (typeof value !== "object") return value;

  if ("result" in value && value.result !== undefined) return getCellValue(value.result);
  if ("text" in value && value.text !== undefined) return getCellValue(value.text);
  if ("richText" in value && Array.isArray(value.richText)) {
    return value.richText.map((part) => getCellValue(part?.text)).join("");
  }
  if ("hyperlink" in value && "text" in value) return getCellValue(value.text);
  if ("error" in value && value.error !== undefined) return getCellValue(value.error);

  return "";
}

function normalizeHeader(header) {
  return String(getCellValue(header))
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function parseExcelDateSerial(value) {
  if (value === null || value === undefined || value === "") return null;
  const cellValue = getCellValue(value);
  const serial = typeof cellValue === "number" ? cellValue : Number(String(cellValue).trim());
  const isExcelSerial =
    Number.isFinite(serial) &&
    serial > 0 &&
    serial <= MAX_SUPPORTED_EXCEL_DATE_SERIAL;
  if (!isExcelSerial) return null;

  return new Date(EXCEL_DATE_EPOCH_UTC_MS + Math.floor(serial) * MILLISECONDS_PER_DAY)
    .toISOString()
    .slice(0, 10);
}

/** "31/12/2026" -> "2026-12-31"; Excel serial -> ISO; Date -> ISO; ISO passes through. */
function normalizeDate(value) {
  const cellValue = getCellValue(value);
  if (cellValue instanceof Date) return cellValue.toISOString().slice(0, 10);
  const excelSerialDate = parseExcelDateSerial(cellValue);
  if (excelSerialDate) return excelSerialDate;

  const text = String(cellValue ?? "").trim();
  const brazilianDate = text.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (brazilianDate) return `${brazilianDate[3]}-${brazilianDate[2]}-${brazilianDate[1]}`;
  return text.slice(0, 10);
}

/** "1.234,56" -> "1234.56". */
function normalizeNumber(value) {
  const cellValue = getCellValue(value);
  if (typeof cellValue === "number") return String(cellValue);
  const text = String(cellValue ?? "").trim();
  if (text.includes(",")) return text.replaceAll(".", "").replace(",", ".");
  return text;
}

function normalizeCell(column, value) {
  if (["invoice_date", "delivery_date", "target_date"].includes(column)) return normalizeDate(value);
  if ([
    "quantity", "gross_value", "unit_cost", "box_count",
    "units_per_pack", "portfolio_size",
  ].includes(column)) return normalizeNumber(value);
  return String(getCellValue(value) ?? "").trim();
}

async function connectDatabase() {
  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  return client;
}

class PartWriter {
  constructor({ bucket, importId, spec }) {
    this.bucket = bucket;
    this.importId = importId;
    this.spec = spec;
    this.rows = [];
    this.partNumber = 0;
    this.totalRows = 0;
    this.partKeys = [];
  }

  async add(row) {
    this.rows.push(row);
    this.totalRows += 1;
    if (this.rows.length >= PART_MAX_ROWS) await this.flush();
  }

  async flush() {
    if (this.rows.length === 0) return;
    this.partNumber += 1;
    const key = `parts/${this.importId}/part-${String(this.partNumber).padStart(4, "0")}.csv`;
    await s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: stringify(this.rows),
        ContentType: "text/csv",
      }),
    );
    this.partKeys.push(key);
    this.rows = [];
  }
}

function buildColumnMapper(spec, headerRow) {
  const positions = new Map();
  headerRow.forEach((header, index) => {
    const normalized = normalizeHeader(header);
    const column = spec.aliases[normalized] ?? (spec.columns.includes(normalized) ? normalized : null);
    if (column && !positions.has(column)) positions.set(column, index);
  });

  for (const [column, index] of Object.entries(spec.positionalFallbacks ?? {})) {
    if (!positions.has(column)) positions.set(column, index);
  }

  const optionalColumns = new Set(spec.optionalColumns ?? []);
  const requiredColumns = spec.columns.filter((column) => !optionalColumns.has(column));
  const missing = requiredColumns.filter((column) => !positions.has(column));
  if (missing.length > 0) {
    throw new Error(`missing required columns: ${missing.join(", ")}`);
  }

  return (rawRow) =>
    spec.columns.map((column) => {
      const index = positions.get(column);
      return index === undefined ? "" : normalizeCell(column, rawRow[index]);
    });
}

async function* iterateCsvRows(body) {
  const parser = body.pipe(parse({ relax_column_count: true, bom: true }));
  for await (const record of parser) yield record;
}

async function* iterateXlsxRows(body, sheetName) {
  const workbookReader = new ExcelJS.stream.xlsx.WorkbookReader(body, {
    entries: "emit",
    sharedStrings: "cache",
    styles: "ignore",
    hyperlinks: "ignore",
    worksheets: "emit",
  });
  let isFirstSheet = true;
  for await (const worksheet of workbookReader) {
    const matchesRequestedSheet = sheetName
      ? worksheet.name === sheetName
      : isFirstSheet;
    isFirstSheet = false;
    if (!matchesRequestedSheet) continue;
    for await (const row of worksheet) {
      // ExcelJS values are 1-indexed; align to a plain 0-indexed array.
      yield (row.values ?? []).slice(1);
    }
    return;
  }
}

async function processUpload(bucket, key) {
  const importId = key.split("/")[1];
  const database = await connectDatabase();

  try {
    const { rows } = await database.query(
      `select fi.id, fi.sheet_name, ftc.target_table
       from file_imports fi
       join file_type_configs ftc on ftc.id = fi.file_type_id
       where fi.id = $1`,
      [importId],
    );
    if (rows.length === 0) throw new Error(`import ${importId} not found`);

    const { target_table: targetTable, sheet_name: sheetName } = rows[0];
    const spec = TABLE_SPECS[targetTable];
    if (!spec) throw new Error(`no ETL spec for target table ${targetTable}`);

    await database.query(
      "update file_imports set status = 'validating' where id = $1",
      [importId],
    );

    const object = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const isXlsx = key.toLowerCase().endsWith(".xlsx");
    const rowIterator = isXlsx
      ? iterateXlsxRows(object.Body, sheetName)
      : iterateCsvRows(object.Body);

    const writer = new PartWriter({ bucket, importId, spec });
    let mapColumns = null;
    let lineNumber = 0;

    for await (const rawRow of rowIterator) {
      lineNumber += 1;
      if (!mapColumns) {
        mapColumns = buildColumnMapper(spec, rawRow);
        continue;
      }
      const isEmptyRow = rawRow.every((cell) => String(getCellValue(cell) ?? "").trim() === "");
      if (isEmptyRow) continue;
      await writer.add([importId, lineNumber, ...mapColumns(rawRow)]);
    }
    await writer.flush();

    await database.query(
      "update file_imports set status = 'processing', total_records = $2 where id = $1",
      [importId, writer.totalRows],
    );

    if (writer.totalRows === 0) {
      await database.query(
        `update file_imports set status = 'failed', finished_at = now() where id = $1`,
        [importId],
      );
      await database.query(
        `insert into file_import_logs (import_id, level, message) values ($1, 'error', $2)`,
        [importId, "validator: no data rows found"],
      );
      console.log(`import ${importId}: no data rows found`);
      return;
    }

    for (const partKey of writer.partKeys) {
      await sqs.send(
        new SendMessageCommand({
          QueueUrl: process.env.QUEUE_URL,
          MessageBody: JSON.stringify({
            importId,
            partKey,
            bucket,
            targetTable,
          }),
        }),
      );
    }

    console.log(
      `import ${importId}: ${writer.totalRows} rows split into ${writer.partKeys.length} parts`,
    );
  } catch (error) {
    await database.query(
      `update file_imports set status = 'failed', finished_at = now() where id = $1`,
      [importId],
    );
    await database.query(
      `insert into file_import_logs (import_id, level, message) values ($1, 'error', $2)`,
      [importId, `validator: ${error.message}`],
    );
    throw error;
  } finally {
    await database.end();
  }
}

export async function handler(event) {
  for (const record of event.Records ?? []) {
    const bucket = record.s3.bucket.name;
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    await processUpload(bucket, key);
  }
}
