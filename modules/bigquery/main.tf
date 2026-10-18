terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

# APIs. Left enabled on destroy: other workloads in the project may rely on them.
resource "google_project_service" "this" {
  for_each = toset([
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com", # project-level IAM grants
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # service account impersonation
    "sts.googleapis.com",            # workload identity federation
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Datasets: BigQuery's equivalent of schemas. The project plays the role of the
# Snowflake database / Redshift cluster.
locals {
  datasets = {
    extract   = var.extract_dataset
    transform = var.transform_dataset
    analysis  = var.analysis_dataset
  }
  descriptions = {
    extract   = "Raw data landed by extract jobs"
    transform = "dbt staging and intermediate models"
    analysis  = "dbt marts for BI tools and analysts"
  }
}

resource "google_bigquery_dataset" "this" {
  for_each    = local.datasets
  project     = var.project_id
  dataset_id  = each.value
  location    = var.location
  description = local.descriptions[each.key]

  # Safety net: destroy fails while a dataset still holds tables, unless this is
  # explicitly enabled (useful for throwaway test deployments).
  delete_contents_on_destroy = var.delete_contents_on_destroy

  depends_on = [google_project_service.this]
}

# Service accounts, one per stage (BigQuery has no warehouses to separate, so
# isolation is purely IAM). Fivetran uses its own Google-managed service
# account, granted access in the stack, so EXTRACT is for Airflow/custom loads.
resource "google_service_account" "this" {
  for_each     = toset(["extract", "transform", "load"])
  project      = var.project_id
  account_id   = "${var.service_account_prefix}-${each.key}"
  display_name = "${upper(each.key)} service account"
  description  = "Data platform ${each.key} stage, managed by Terraform"

  depends_on = [google_project_service.this]
}

locals {
  sa = { for k, v in google_service_account.this : k => "serviceAccount:${v.email}" }

  # Project-level roles. jobUser lets a principal run queries and load jobs.
  # TRANSFORM gets BigQuery User instead, which adds creating datasets (dbt makes
  # its own for seeds, snapshots and test failures, as it creates schemas on
  # Snowflake and Redshift), and reads every dataset because Fivetran creates one
  # per connector, with names not known in advance.
  project_roles = merge(
    {
      extract_jobs   = { member = local.sa.extract, role = "roles/bigquery.jobUser" }
      transform_jobs = { member = local.sa.transform, role = "roles/bigquery.user" }
      transform_read = { member = local.sa.transform, role = "roles/bigquery.dataViewer" }
      load_jobs      = { member = local.sa.load, role = "roles/bigquery.jobUser" }
    },
    { for m in var.analyst_members : "analyst_jobs_${m}" => { member = m, role = "roles/bigquery.jobUser" } },
    { for m in var.admin_members : "admin_jobs_${m}" => { member = m, role = "roles/bigquery.jobUser" } },
    { for m in var.admin_members : "admin_read_${m}" => { member = m, role = "roles/bigquery.dataViewer" } },
  )

  # Dataset-level roles. Unlike Snowflake and Redshift, these cover tables
  # created later automatically, so no future grants are needed.
  dataset_roles = merge(
    {
      extract_writes_extract     = { dataset = "extract", member = local.sa.extract, role = "roles/bigquery.dataEditor" }
      transform_writes_transform = { dataset = "transform", member = local.sa.transform, role = "roles/bigquery.dataEditor" }
      transform_writes_analysis  = { dataset = "analysis", member = local.sa.transform, role = "roles/bigquery.dataEditor" }
      load_reads_analysis        = { dataset = "analysis", member = local.sa.load, role = "roles/bigquery.dataViewer" }
    },
    { for m in var.analyst_members : "analyst_reads_analysis_${m}" => { dataset = "analysis", member = m, role = "roles/bigquery.dataViewer" } },
  )
}

resource "google_project_iam_member" "this" {
  for_each = local.project_roles
  project  = var.project_id
  member   = each.value.member
  role     = each.value.role

  depends_on = [google_project_service.this]
}

resource "google_bigquery_dataset_iam_member" "this" {
  for_each   = local.dataset_roles
  project    = var.project_id
  dataset_id = google_bigquery_dataset.this[each.value.dataset].dataset_id
  member     = each.value.member
  role       = each.value.role
}

# Keyless access for dbt (laptops, CI): listed principals may impersonate the
# TRANSFORM service account instead of downloading a key.
resource "google_service_account_iam_member" "transform_impersonators" {
  for_each           = toset(var.transform_impersonators)
  service_account_id = google_service_account.this["transform"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.key
}
