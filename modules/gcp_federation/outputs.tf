output "workload_identity_provider" {
  description = "Full resource name of the workload identity provider"
  value       = google_iam_workload_identity_pool_provider.aws.name
}

output "credential_config_keys" {
  description = "S3 keys of the credential configurations, per stage"
  value       = { for k, v in aws_s3_object.credential_config : k => v.key }
}

output "mwaa_requirements" {
  description = "requirements.txt key and object version for MWAA (null for EC2)"
  value       = var.airflow_type == "mwaa" ? { path = aws_s3_object.mwaa_requirements[0].key, version = aws_s3_object.mwaa_requirements[0].version_id } : null
}

output "mwaa_plugins" {
  description = "plugins.zip key and object version for MWAA (null for EC2)"
  value       = var.airflow_type == "mwaa" ? { path = aws_s3_object.mwaa_plugins[0].key, version = aws_s3_object.mwaa_plugins[0].version_id } : null
}
