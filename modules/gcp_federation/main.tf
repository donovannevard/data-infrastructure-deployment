terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.79"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# Keyless access from Airflow on AWS to BigQuery, via workload identity
# federation: Google trusts tokens signed for one specific AWS IAM role, which
# may then impersonate the EXTRACT and TRANSFORM service accounts. No Google
# keys exist anywhere.

data "aws_caller_identity" "current" {}

locals {
  aws_role_arn = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${var.aws_role_name}"
}

# Deleted pools are retained by Google for 30 days and their IDs can't be reused
# in that time, so each deployment gets a fresh suffix.
resource "random_id" "pool" {
  byte_length = 4
}

resource "google_iam_workload_identity_pool" "airflow" {
  project                   = var.project_id
  workload_identity_pool_id = "airflow-${random_id.pool.hex}"
  display_name              = "Airflow on AWS"
  description               = "Lets the Airflow IAM role act as BigQuery service accounts"

  depends_on = [var.apis_enabled]
}

resource "google_iam_workload_identity_pool_provider" "aws" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.airflow.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-airflow"
  display_name                       = "AWS account"

  aws {
    account_id = data.aws_caller_identity.current.account_id
  }

  # Google's standard AWS mapping: normalises "assumed-role/<role>/<session>"
  # to the role, so the binding below doesn't depend on session names.
  attribute_mapping = {
    "google.subject"     = "assertion.arn"
    "attribute.aws_role" = "assertion.arn.contains('assumed-role') ? assertion.arn.extract('{account_arn}assumed-role/') + 'assumed-role/' + assertion.arn.extract('assumed-role/{role_name}/') : assertion.arn"
  }
  # Only the Airflow role can use this provider at all
  attribute_condition = "attribute.aws_role == '${local.aws_role_arn}'"
}

resource "google_service_account_iam_member" "airflow" {
  for_each           = var.service_accounts
  service_account_id = each.value.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.airflow.name}/attribute.aws_role/${local.aws_role_arn}"
}

# Credential configurations (not secrets: they only say where to exchange the
# AWS identity for a Google token), synced to Airflow with the DAGs.
locals {
  credential_configs = {
    for stage, sa in var.service_accounts : stage => jsonencode({
      type                              = "external_account"
      audience                          = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.aws.name}"
      subject_token_type                = "urn:ietf:params:aws:token-type:aws4_request"
      token_url                         = "https://sts.googleapis.com/v1/token"
      service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${sa.email}:generateAccessToken"
      credential_source = {
        environment_id                 = "aws1"
        region_url                     = "http://169.254.169.254/latest/meta-data/placement/availability-zone"
        url                            = "http://169.254.169.254/latest/meta-data/iam/security-credentials"
        regional_cred_verification_url = "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15"
        imdsv2_session_token_url       = "http://169.254.169.254/latest/api/token"
      }
    })
  }
}

resource "aws_s3_object" "credential_config" {
  for_each     = local.credential_configs
  bucket       = var.dag_bucket_name
  key          = "dags/gcp/${each.key}_credentials.json"
  content      = each.value
  content_type = "application/json"
}

resource "aws_s3_object" "helper" {
  bucket       = var.dag_bucket_name
  key          = "dags/gcp/gcp_federation.py"
  content      = templatefile("${path.module}/gcp_federation.py.tftpl", { project_id = var.project_id })
  content_type = "text/x-python"
}

# MWAA only: install the BigQuery client library, and a plugin that runs the
# helper above before every task (Google's libraries can't read Fargate's role
# credentials themselves). EC2 Airflow needs neither: its image includes the
# library and the credentials come from the instance metadata service.
resource "aws_s3_object" "mwaa_requirements" {
  count        = var.airflow_type == "mwaa" ? 1 : 0
  bucket       = var.dag_bucket_name
  key          = "requirements.txt"
  content      = "google-cloud-bigquery\n" # version pinned by MWAA's Airflow constraints
  content_type = "text/plain"
}

data "archive_file" "mwaa_plugins" {
  count       = var.airflow_type == "mwaa" ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/gcp_federation_plugin.py"
  output_path = "${path.root}/.terraform/tmp/mwaa_plugins.zip"
}

resource "aws_s3_object" "mwaa_plugins" {
  count        = var.airflow_type == "mwaa" ? 1 : 0
  bucket       = var.dag_bucket_name
  key          = "plugins.zip"
  source       = data.archive_file.mwaa_plugins[0].output_path
  source_hash  = data.archive_file.mwaa_plugins[0].output_md5
  content_type = "application/zip"
}
