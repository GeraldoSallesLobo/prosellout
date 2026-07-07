# Operational alarms: anything landing in the DLQ or repeated loader errors
# means an import needs attention.

resource "aws_sns_topic" "alarms" {
  count = var.alarm_email == "" ? 0 : 1
  name  = "${local.prefix}-etl-alarms"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = var.alarm_email == "" ? [] : [aws_sns_topic.alarms[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${local.prefix}-etl-dlq-not-empty"
  alarm_description   = "Import parts failed after retries and reached the DLQ"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions

  dimensions = {
    QueueName = aws_sqs_queue.etl_dlq.name
  }
}

resource "aws_cloudwatch_metric_alarm" "loader_errors" {
  alarm_name          = "${local.prefix}-etl-loader-errors"
  alarm_description   = "ETL loader invocations failing"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = local.alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.etl_loader.function_name
  }
}
