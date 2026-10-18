output "project_id" {
  value = var.project_id
}

output "location" {
  value = var.location
}

output "datasets" {
  # From the configured names rather than the resources, so the map is always
  # complete (e.g. while importing a pre-existing dataset into state)
  value      = local.datasets
  depends_on = [google_bigquery_dataset.this]
}

output "service_accounts" {
  description = "Service account emails per stage. No keys are created: impersonate them instead."
  value       = { for k, v in google_service_account.this : k => v.email }
}

output "service_account_names" {
  description = "Fully qualified service account resource names (for IAM bindings)"
  value       = { for k, v in google_service_account.this : k => v.name }
}

output "apis_enabled" {
  description = "Enabled API names; depend on this before using them outside the module"
  value       = [for s in google_project_service.this : s.service]
}
