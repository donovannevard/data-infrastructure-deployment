output "bigquery" {
  description = "Project, location, datasets and service account emails (no secrets: BigQuery access is keyless)"
  value       = module.bigquery
}

output "dbt_profile_hint" {
  description = "Starting point for a keyless dbt-bigquery profile (requires your principal in bigquery_transform_impersonators)"
  value = {
    type                        = "bigquery"
    method                      = "oauth"
    project                     = module.bigquery.project_id
    dataset                     = module.bigquery.datasets.transform
    location                    = module.bigquery.location
    impersonate_service_account = module.bigquery.service_accounts.transform
  }
}

output "fivetran_group_id" {
  description = "Fivetran group the warehouse destination belongs to (if enabled)"
  value       = local.fivetran_group_id
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

output "airflow_gcp_workload_identity_provider" {
  description = "Workload identity provider Airflow federates through (if Airflow is enabled)"
  value       = try(module.gcp_federation[0].workload_identity_provider, null)
}

output "next_steps" {
  description = "Important next steps after terraform apply"
  value       = <<EOT
1. BigQuery access is keyless: no passwords or keys were created. For dbt, add your
   principal to bigquery_transform_impersonators and use the dbt_profile_hint output.
2. Grant analysts access by adding their group to bigquery_analyst_members (and
   bigquery_admin_members for read access to every dataset), then re-apply.
3. If using Fivetran: add source connectors to the Fivetran group above (Fivetran UI).
   Each connector lands in its own dataset in the same project.
4. If using Airflow: every task is already authenticated to BigQuery as the TRANSFORM
   service account, with no keys. A task that needs EXTRACT instead calls
   use_aws_role_for_gcp("extract") from dags/gcp/gcp_federation.py.
5. If using EC2 Airflow with HTTPS and no Route53 zone ID: add the DNS record from
   airflow_ec2_acm_validation_record with your DNS provider, then re-apply once it validates.
EOT
}
