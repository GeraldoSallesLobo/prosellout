import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { parse } from "csv-parse";
import { stringify } from "csv-stringify/sync";
import ExcelJS from "exceljs";
import pg from "pg";

const PART_MAX_ROWS = Number(process.env.PART_MAX_ROWS ?? 50000);

const s3 = new S3Client({});
const sqs = new SQSClient({});

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
      "quantity", "gross_value", "unit_cost",
    ],
    optionalColumns: [
      "customer_pdv_code", "customer_cnpj", "invoice_number", "delivery_date", "unit_cost",
    ],
    aliases: {
      distribuidor: "distributor_code",
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
      data_faturamento: "invoice_date",
      data_entrega: "delivery_date",
      entrega: "delivery_date",
      volume: "quantity",
      quantidade: "quantity",
      qtd: "quantity",
      valor: "gross_value",
      valor_bruto: "gross_value",
      custo: "unit_cost",
      custo_unitario: "unit_cost",
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
      cod_distribuidor: "distributor_code",
      ean: "product_ean",
      nf: "invoice_number",
      nota_fiscal: "invoice_number",
      data: "invoice_date",
      data_faturamento: "invoice_date",
      volume: "quantity",
      quantidade: "quantity",
      qtd: "quantity",
      valor: "gross_value",
      custo: "unit_cost",
    },
  },
};

function normalizeHeader(header) {
  return String(header ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .replace(/\s+/g, "_");
}

/** "31/12/2026" -> "2026-12-31"; Date -> ISO; ISO passes through. */
function normalizeDate(value) {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  const text = String(value ?? "").trim();
  const brazilianDate = text.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (brazilianDate) return `${brazilianDate[3]}-${brazilianDate[2]}-${brazilianDate[1]}`;
  return text.slice(0, 10);
}

/** "1.234,56" -> "1234.56". */
function normalizeNumber(value) {
  if (typeof value === "number") return String(value);
  const text = String(value ?? "").trim();
  if (text.includes(",")) return text.replaceAll(".", "").replace(",", ".");
  return text;
}

function normalizeCell(column, value) {
  if (["invoice_date", "delivery_date"].includes(column)) return normalizeDate(value);
  if (["quantity", "gross_value", "unit_cost"].includes(column)) return normalizeNumber(value);
  return String(value ?? "").trim();
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
      const isEmptyRow = rawRow.every((cell) => String(cell ?? "").trim() === "");
      if (isEmptyRow) continue;
      await writer.add([importId, lineNumber, ...mapColumns(rawRow)]);
    }
    await writer.flush();

    await database.query(
      "update file_imports set status = 'processing', total_records = $2 where id = $1",
      [importId, writer.totalRows],
    );

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
