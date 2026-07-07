import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const URL_EXPIRATION_SECONDS = 900;
const ALLOWED_EXTENSIONS = [".xlsx", ".csv"];

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

/**
 * POST { importId, fileName, contentType } -> { uploadUrl, key }
 * The portal registers the import in Supabase first (file_imports insert) and
 * then PUTs the file straight to S3 — file bytes never cross the frontend.
 */
export async function handler(event) {
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

  const uploadUrl = await getSignedUrl(s3, command, {
    expiresIn: URL_EXPIRATION_SECONDS,
  });

  return jsonResponse(200, { uploadUrl, key });
}
