output "imports_bucket" {
  value       = aws_s3_bucket.imports.bucket
  description = "Bucket that receives import files"
}

output "etl_queue_url" {
  value       = aws_sqs_queue.etl.url
  description = "Work queue between validator and loader"
}

output "upload_api_url" {
  value       = aws_lambda_function_url.upload_url.function_url
  description = "Set as NEXT_PUBLIC_UPLOAD_API_URL in the frontend"
}
