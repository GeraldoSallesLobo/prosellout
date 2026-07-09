# The three functions of the ingestion pipeline.
# Build the zips before `terraform apply`: ./build.sh (installs each lambda's
# node_modules and lets archive_file pick everything up).

locals {
  lambda_runtime = "nodejs20.x"
  lambda_arch    = ["arm64"]
}

data "archive_file" "upload_url" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/upload-url"
  output_path = "${path.module}/.build/upload-url.zip"
}

data "archive_file" "file_validator" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/file-validator"
  output_path = "${path.module}/.build/file-validator.zip"
}

data "archive_file" "etl_loader" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/etl-loader"
  output_path = "${path.module}/.build/etl-loader.zip"
}

# ---------------------------------------------------------------------------
# upload-url: presigned PUT for the portal (Function URL)
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "upload_url" {
  function_name    = "${local.prefix}-upload-url"
  role             = aws_iam_role.upload_url.arn
  runtime          = local.lambda_runtime
  architectures    = local.lambda_arch
  handler          = "index.handler"
  filename         = data.archive_file.upload_url.output_path
  source_code_hash = data.archive_file.upload_url.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME       = aws_s3_bucket.imports.bucket
      DATABASE_URL      = var.database_url
      SUPABASE_ANON_KEY = var.supabase_anon_key
      SUPABASE_URL      = var.supabase_url
    }
  }
}

resource "aws_lambda_function_url" "upload_url" {
  function_name      = aws_lambda_function.upload_url.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = local.allowed_upload_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
  }
}

resource "terraform_data" "allow_public_invoke_upload_url_function" {
  input = {
    function_name = aws_lambda_function.upload_url.function_name
    statement_id  = "FunctionURLInvokeAllowPublicAccess"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      if aws lambda get-policy --function-name '${self.input.function_name}' --query Policy --output text 2>/dev/null | grep -q '${self.input.statement_id}'; then
        exit 0
      fi

      aws lambda add-permission \
        --function-name '${self.input.function_name}' \
        --statement-id '${self.input.statement_id}' \
        --action lambda:InvokeFunction \
        --principal '*' >/dev/null
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws lambda remove-permission \
        --function-name '${self.input.function_name}' \
        --statement-id '${self.input.statement_id}' >/dev/null 2>&1 || true
    EOT
  }
}

# ---------------------------------------------------------------------------
# file-validator: S3 trigger — validates, splits into parts, enqueues
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "file_validator" {
  function_name    = "${local.prefix}-file-validator"
  role             = aws_iam_role.file_validator.arn
  runtime          = local.lambda_runtime
  architectures    = local.lambda_arch
  handler          = "index.handler"
  filename         = data.archive_file.file_validator.output_path
  source_code_hash = data.archive_file.file_validator.output_base64sha256
  timeout          = 900
  memory_size      = 2048

  environment {
    variables = {
      QUEUE_URL     = aws_sqs_queue.etl.url
      DATABASE_URL  = var.database_url
      PART_MAX_ROWS = tostring(var.part_max_rows)
    }
  }
}

resource "aws_lambda_permission" "allow_s3_invoke_validator" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_validator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.imports.arn
}

# ---------------------------------------------------------------------------
# etl-loader: SQS consumer — COPY into staging + merge
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "etl_loader" {
  function_name    = "${local.prefix}-etl-loader"
  role             = aws_iam_role.etl_loader.arn
  runtime          = local.lambda_runtime
  architectures    = local.lambda_arch
  handler          = "index.handler"
  filename         = data.archive_file.etl_loader.output_path
  source_code_hash = data.archive_file.etl_loader.output_base64sha256
  timeout          = local.loader_timeout_seconds
  memory_size      = 2048

  environment {
    variables = {
      DATABASE_URL = var.database_url
    }
  }
}

resource "aws_lambda_event_source_mapping" "etl_loader" {
  event_source_arn = aws_sqs_queue.etl.arn
  function_name    = aws_lambda_function.etl_loader.arn
  batch_size       = 1

  scaling_config {
    # Bounds parallel COPY sessions against the database.
    maximum_concurrency = 8
  }
}
