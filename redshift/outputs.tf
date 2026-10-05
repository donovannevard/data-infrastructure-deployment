output "redshift" {
  description = "All outputs from the Redshift warehouse module"
  value       = module.redshift
  sensitive   = true
}

output "redshift_connection" {
  description = "Cluster endpoint and admin (master) credentials"
  value = {
    host           = module.aws.redshift.host
    port           = module.aws.redshift.port
    database       = module.aws.redshift.database
    admin_username = module.aws.redshift.username
    admin_password = module.aws.redshift.password
  }
  sensitive = true
}

output "fivetran_group_id" {
  description = "Fivetran group the warehouse destination belongs to (if enabled)"
  value       = try(module.fivetran[0].fivetran_group_id, null)
}

output "fivetran_destination_id" {
  description = "Fivetran destination ID (if enabled)"
  value       = try(module.fivetran[0].fivetran_destination_id, null)
}

output "airflow_mwaa_webserver_url" {
  description = "MWAA webserver URL (if enabled)"
  value       = try(module.airflow_mwaa[0].mwaa_webserver_url, null)
}

output "airflow_ec2_url" {
  description = "EC2 Airflow webserver URL (if enabled)"
  value       = try(module.airflow_ec2[0].airflow_url, null)
}

output "airflow_ec2_acm_validation_record" {
  description = "DNS record to add manually if EC2 Airflow HTTPS is enabled without a Route53 zone ID"
  value       = try(module.airflow_ec2[0].acm_validation_record, null)
}

output "airflow_ec2_admin_username" {
  description = "Username for the EC2 Airflow UI admin account (if enabled)"
  value       = try(module.airflow_ec2[0].admin_username, null)
}

output "airflow_ec2_admin_password" {
  description = "Password for the EC2 Airflow UI admin account (if enabled)"
  value       = try(module.airflow_ec2[0].admin_password, null)
  sensitive   = true
}

output "next_steps" {
  description = "Important next steps after terraform apply"
  value       = <<EOT
1. Save all sensitive outputs (passwords, tokens, etc.) securely — the local state
   file also contains them in plaintext, so treat terraform.tfstate itself as a secret.
2. Connect your BI tool (Sigma, QuickSight, etc.) using the warehouse outputs.
3. If using Fivetran: add source connectors to the Fivetran group above (Fivetran UI).
4. If using Airflow: push your DAGs to the correct location (S3 for MWAA, or the DAG
   bucket synced by the EC2 instance every 5 minutes).
5. If using EC2 Airflow with HTTPS and no Route53 zone ID: add the DNS record from
   airflow_ec2_acm_validation_record with your DNS provider, then re-apply once it validates.
EOT
}
