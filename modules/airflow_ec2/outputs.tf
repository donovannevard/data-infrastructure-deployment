output "airflow_url" {
  description = "URL for the Airflow webserver"
  value       = "${var.airflow_ec2_enable_https ? "https" : "http"}://${aws_lb.airflow.dns_name}"
}

output "airflow_type" {
  description = "Airflow deployment type"
  value       = "ec2"
}

output "admin_username" {
  description = "Username for the Airflow UI admin account"
  value       = "admin"
}

output "admin_password" {
  description = "Password for the Airflow UI admin account"
  value       = random_password.admin.result
  sensitive   = true
}

output "acm_validation_record" {
  description = "DNS record to create manually if airflow_ec2_enable_https = true and route53_zone_id was not supplied. Null otherwise."
  value = (var.airflow_ec2_enable_https && var.route53_zone_id == null) ? {
    name  = tolist(aws_acm_certificate.airflow[0].domain_validation_options)[0].resource_record_name
    type  = tolist(aws_acm_certificate.airflow[0].domain_validation_options)[0].resource_record_type
    value = tolist(aws_acm_certificate.airflow[0].domain_validation_options)[0].resource_record_value
  } : null
}

output "iam_role_name" {
  description = "IAM role Airflow runs as (trusted by BigQuery workload identity federation)"
  value       = aws_iam_role.airflow_ec2.name
}
