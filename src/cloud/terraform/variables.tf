variable "project_name" {
  description = "Project slug used to prefix resources"
  type        = string
  default     = "prosellout"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "sa-east-1"
}

variable "database_url" {
  description = <<-EOT
    Postgres connection string used by the ETL (Supabase).
    Use the SESSION mode pooler URI (port 5432) or the direct connection —
    COPY streaming is not supported by the transaction-mode pooler (6543).
  EOT
  type        = string
  sensitive   = true
}

variable "portal_origin" {
  description = "Frontend origin allowed to upload via presigned URLs (CORS)"
  type        = string
  default     = "https://portal.prosellout.com.br"
}

variable "part_max_rows" {
  description = "Maximum rows per file part enqueued for the loader"
  type        = number
  default     = 50000
}

variable "alarm_email" {
  description = "E-mail subscribed to processing alarms (empty disables SNS)"
  type        = string
  default     = ""
}
