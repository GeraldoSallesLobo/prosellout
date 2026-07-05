# Work queue between the validator (producer) and the loader (consumer).
# One message = one file part (bounded row count), so a huge file becomes N
# parallelizable, retriable units of work.

locals {
  # Queue visibility must exceed the consumer Lambda timeout (AWS requirement).
  loader_timeout_seconds   = 900
  queue_visibility_seconds = 960
}

resource "aws_sqs_queue" "etl_dlq" {
  name                      = "${local.prefix}-etl-dlq"
  message_retention_seconds = 1209600 # 14 days to investigate failures
}

resource "aws_sqs_queue" "etl" {
  name                       = "${local.prefix}-etl"
  visibility_timeout_seconds = local.queue_visibility_seconds
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.etl_dlq.arn
    maxReceiveCount     = 3
  })
}
