# Google - authenticates with Application Default Credentials:
#   gcloud auth application-default login
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  # Bill API quota to the target project. Without this, personal (gcloud)
  # credentials with no quota project set are rejected by some Google APIs.
  billing_project       = var.gcp_project_id
  user_project_override = true
}

# AWS - only used here if use_airflow = true. Credential validation is skipped
# entirely when Airflow isn't deployed, so a pure BigQuery + Fivetran client
# needs no AWS account at all.
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = !local.needs_aws
  skip_region_validation      = !local.needs_aws
  skip_requesting_account_id  = !local.needs_aws
}

# Fivetran - only used when use_fivetran = true
provider "fivetran" {
  api_key    = var.use_fivetran ? var.fivetran_api_key : "unused"
  api_secret = var.use_fivetran ? var.fivetran_api_secret : "unused"
}

# Random provider - pool suffixes, bucket names and Airflow passwords
provider "random" {
}
