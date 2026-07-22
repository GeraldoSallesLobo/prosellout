import { S3Client, GetObjectCommand, DeleteObjectCommand } from "@aws-sdk/client-s3";
import { pipeline } from "node:stream/promises";
import pg from "pg";
import copyStreams from "pg-copy-streams";

const s3 = new S3Client({});

/**
 * Whitelist of staging targets. Never build SQL from message contents that is
 * not present here.
 */
const TABLE_SPECS = {
  sell_out: {
    stagingTable: "staging_sell_out",
    processFunction: "process_sell_out_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "customer_pdv_code",
      "customer_cnpj", "sales_rep_code", "product_ean", "invoice_number",
      "invoice_date", "delivery_date", "quantity", "gross_value", "unit_cost",
      "channel_name", "cluster_name",
    ],
  },
  sell_in: {
    stagingTable: "staging_sell_in",
    processFunction: "process_sell_in_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "product_ean",
      "invoice_number", "invoice_date", "quantity", "gross_value", "unit_cost",
    ],
  },
  sell_in_targets: {
    stagingTable: "staging_sell_in_targets",
    processFunction: "process_sell_in_targets_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "product_ean",
      "target_date", "quantity", "gross_value",
    ],
  },
  customers: {
    stagingTable: "staging_customers",
    processFunction: "process_customers_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "customer_pdv_code",
      "customer_cnpj", "legal_name", "trade_name", "address", "district",
      "city", "state", "zip_code", "channel_name", "cluster_name",
    ],
  },
  products: {
    stagingTable: "staging_products",
    processFunction: "process_products_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "product_ean",
      "product_name", "box_count", "units_per_pack", "subcategory_name",
      "category_name", "macro_category_name", "sku_code",
    ],
  },
  sales_reps: {
    stagingTable: "staging_sellers",
    processFunction: "process_sellers_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "seller_code",
      "seller_name", "portfolio_size", "supervisor_code", "supervisor_name",
      "manager_code", "manager_name",
    ],
  },
  sales_targets: {
    stagingTable: "staging_targets",
    processFunction: "process_targets_staging",
    columns: [
      "import_id", "line_number", "distributor_code", "customer_pdv_code",
      "customer_cnpj", "sales_rep_code", "product_ean", "target_date",
      "delivery_date", "quantity", "gross_value", "channel_name", "cluster_name",
    ],
  },
};

async function connectDatabase() {
  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  return client;
}

/**
 * COPY the canonical CSV part straight from S3 into the UNLOGGED staging
 * table — no per-row round trips — then run the set-based merge function.
 */
async function loadPart(database, { bucket, partKey, importId, spec }) {
  const object = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: partKey }));

  const copySql = `copy ${spec.stagingTable} (${spec.columns.join(", ")}) from stdin with (format csv)`;
  const copyStream = database.query(copyStreams.from(copySql));
  await pipeline(object.Body, copyStream);

  // spec.processFunction comes from TABLE_SPECS (whitelisted), never from input.
  const { rows } = await database.query(
    `select inserted_count, rejected_count from ${spec.processFunction}($1)`,
    [importId],
  );
  return rows[0];
}

async function finishImportIfComplete(database, importId) {
  const { rows } = await database.query(
    `select processed_records + error_count as done_records, total_records
     from file_imports where id = $1`,
    [importId],
  );
  if (rows.length === 0) return;

  const { done_records: doneRecords, total_records: totalRecords } = rows[0];
  const isComplete = Number(doneRecords) >= Number(totalRecords) && Number(totalRecords) > 0;
  if (!isComplete) return;

  await database.query("select finish_file_import($1)", [importId]);
  await database.query("select refresh_report_views()");
  console.log(`import ${importId} finished (${doneRecords}/${totalRecords})`);
}

export async function handler(event) {
  const database = await connectDatabase();
  try {
    for (const record of event.Records ?? []) {
      const message = JSON.parse(record.body);
      const { importId, partKey, bucket, targetTable } = message;

      const spec = TABLE_SPECS[targetTable];
      if (!spec) throw new Error(`no ETL spec for target table ${targetTable}`);

      const result = await loadPart(database, { bucket, partKey, importId, spec });
      console.log(
        `part ${partKey}: inserted=${result.inserted_count} rejected=${result.rejected_count}`,
      );

      await finishImportIfComplete(database, importId);
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: partKey }));
    }
  } finally {
    await database.end();
  }
}
