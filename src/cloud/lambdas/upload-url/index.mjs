import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import pg from "pg";

const URL_EXPIRATION_SECONDS = 900;
const ALLOWED_EXTENSIONS = [".xlsx", ".csv"];
const BEARER_PREFIX = "Bearer ";

const s3 = new S3Client({});

function sanitizeFileName(fileName) {
  return fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  };
}

function getHeader(headers, name) {
  const expectedName = name.toLowerCase();
  const entry = Object.entries(headers ?? {}).find(
    ([key]) => key.toLowerCase() === expectedName,
  );
  return entry?.[1];
}

function getBearerToken(event) {
  const authorization = getHeader(event.headers, "authorization");
  if (!authorization?.startsWith(BEARER_PREFIX)) return null;
  return authorization.slice(BEARER_PREFIX.length).trim();
}

async function getAuthenticatedUserId(accessToken) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) {
    throw new Error("missing Supabase Auth configuration");
  }

  const response = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: process.env.SUPABASE_ANON_KEY,
      authorization: `${BEARER_PREFIX}${accessToken}`,
    },
  });

  if (!response.ok) return null;

  const user = await response.json();
  return typeof user.id === "string" ? user.id : null;
}

async function connectDatabase() {
  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  return client;
}

async function canUploadImport(database, importId, userId) {
  const { rows } = await database.query(
    `select 1
     from file_imports fi
     join distributor_users du
       on du.user_id = $2
      and du.distributor_id = fi.distributor_id
      and du.status = 'active'
     where fi.id = $1
       and fi.imported_by = $2
       and fi.status = 'pending'
     limit 1`,
    [importId, userId],
  );

  return rows.length > 0;
}

async function updateImportStorageKey(database, importId, storageKey) {
  await database.query(
    "update file_imports set storage_key = $2 where id = $1",
    [importId, storageKey],
  );
}

/**
 * POST { importId, fileName, contentType } -> { uploadUrl, key }
 * The portal registers the import in Supabase first (file_imports insert) and
 * then PUTs the file straight to S3 — file bytes never cross the frontend.
 */
export async function handler(event) {
  const accessToken = getBearerToken(event);
  if (!accessToken) {
    return jsonResponse(401, { error: "missing bearer token" });
  }

  let payload;
  try {
    payload = JSON.parse(event.body ?? "{}");
  } catch {
    return jsonResponse(400, { error: "invalid JSON body" });
  }

  const { importId, fileName, contentType } = payload;
  if (!importId || !fileName) {
    return jsonResponse(400, { error: "importId and fileName are required" });
  }

  const hasAllowedExtension = ALLOWED_EXTENSIONS.some((extension) =>
    fileName.toLowerCase().endsWith(extension),
  );
  if (!hasAllowedExtension) {
    return jsonResponse(400, { error: `extension must be one of ${ALLOWED_EXTENSIONS.join(", ")}` });
  }

  const key = `uploads/${importId}/${sanitizeFileName(fileName)}`;
  const command = new PutObjectCommand({
    Bucket: process.env.BUCKET_NAME,
    Key: key,
    ContentType: contentType ?? "application/octet-stream",
  });

  let database;
  try {
    const userId = await getAuthenticatedUserId(accessToken);
    if (!userId) {
      return jsonResponse(401, { error: "invalid bearer token" });
    }

    database = await connectDatabase();
    const hasImportAccess = await canUploadImport(database, importId, userId);
    if (!hasImportAccess) {
      return jsonResponse(403, { error: "import does not belong to current user or is not pending" });
    }

    const uploadUrl = await getSignedUrl(s3, command, {
      expiresIn: URL_EXPIRATION_SECONDS,
    });
    await updateImportStorageKey(database, importId, key);

    return jsonResponse(200, { uploadUrl, key });
  } finally {
    await database?.end();
  }
}
