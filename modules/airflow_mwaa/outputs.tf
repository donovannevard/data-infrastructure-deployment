output "mwaa_webserver_url" {
  description = "MWAA webserver URL"
  value       = aws_mwaa_environment.main.webserver_url
}

output "airflow_type" {
  description = "Airflow deployment type"
  value       = "mwaa"
}

output "iam_role_name" {
  description = "IAM role Airflow runs as (trusted by BigQuery workload identity federation)"
  value       = aws_iam_role.mwaa_execution.name
}

output "log_group_names" {
  description = "Terraform-managed CloudWatch log groups (empty when log_retention_days is null)"
  value       = [for g in aws_cloudwatch_log_group.mwaa : g.name]
}
