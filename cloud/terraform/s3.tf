# Bucket that receives raw import files (uploads/) and canonical CSV parts
# produced by the validator (parts/). The portal uploads directly with a
# presigned URL, so file traffic never touches the frontend servers.

resource "aws_s3_bucket" "imports" {
  bucket = "${local.prefix}-imports"
}

resource "aws_s3_bucket_public_access_block" "imports" {
  bucket                  = aws_s3_bucket.imports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "imports" {
  bucket = aws_s3_bucket.imports.id

  rule {
    id     = "expire-raw-uploads"
    status = "Enabled"
    filter {
      prefix = "uploads/"
    }
    expiration {
      days = 30
    }
  }

  rule {
    id     = "expire-parts"
    status = "Enabled"
    filter {
      prefix = "parts/"
    }
    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "imports" {
  bucket = aws_s3_bucket.imports.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = [var.portal_origin, "http://localhost:3000"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}

# New object under uploads/ -> validator Lambda.
resource "aws_s3_bucket_notification" "imports" {
  bucket = aws_s3_bucket.imports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_validator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_validator]
}
