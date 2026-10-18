# Offline tests: every cloud provider is mocked (random runs for real, locally),
# so these run with no cloud accounts or credentials via `terraform test`. They
# check that each supported combination wires together and creates exactly the
# components it should.

mock_provider "google" {
  source = "../tests/mocks/google"
}
mock_provider "fivetran" {}
mock_provider "aws" {
  source = "../tests/mocks/aws"
}

# Every input is set explicitly below so results don't depend on a local
# terraform.tfvars, which `terraform test` would otherwise also load.
variables {
  use_fivetran                        = true
  use_airflow                         = false
  airflow_type                        = "mwaa"
  aws_prefix                          = "etl"
  aws_region                          = "eu-west-2"
  ec2_inbound_cidr_restriction        = null
  airflow_ec2_enable_https            = false
  airflow_ec2_domain                  = null
  airflow_ec2_route53_zone_id         = null
  gcp_project_id                      = "test-project"
  bigquery_location                   = "EU"
  bigquery_delete_contents_on_destroy = false
  bigquery_service_account_prefix     = "dwh"
  bigquery_analyst_members            = []
  bigquery_admin_members              = []
  bigquery_transform_impersonators    = []
  fivetran_group_id                   = null
  fivetran_api_key                    = "key"
  fivetran_api_secret                 = "secret"
  fivetran_region                     = "GCP_EUROPE_WEST2"
  airflow_mwaa_log_retention_days     = 30
}

run "bigquery_and_fivetran_default" {
  variables {
    bigquery_transform_impersonators = ["user:dbt-dev@example.com"]
    bigquery_analyst_members         = ["group:analysts@example.com"]
  }
  assert {
    condition     = length(module.fivetran) == 1 && length(google_project_iam_member.fivetran) == 1
    error_message = "Fivetran should be deployed, with its service account granted BigQuery access"
  }
  assert {
    condition     = length(module.aws) == 0 && length(module.gcp_federation) == 0
    error_message = "No AWS or federation resources should be created without Airflow"
  }
  assert {
    condition     = output.bigquery.datasets == { extract = "extract", transform = "transform", analysis = "analysis" }
    error_message = "The three layer datasets should be created"
  }
}

run "bigquery_only" {
  variables {
    use_fivetran = false
  }
  assert {
    condition     = length(module.fivetran) == 0 && length(fivetran_group.bigquery) == 0 && length(module.aws) == 0
    error_message = "A bare warehouse deploy should create no Fivetran or AWS resources"
  }
}

run "existing_fivetran_group_reused" {
  variables {
    fivetran_group_id = "existing_group"
  }
  assert {
    condition     = length(fivetran_group.bigquery) == 0 && output.fivetran_group_id == "existing_group"
    error_message = "An existing Fivetran group should be used instead of creating one"
  }
}

run "bigquery_with_mwaa" {
  variables {
    use_airflow  = true
    airflow_type = "mwaa"
  }
  assert {
    condition     = length(module.airflow_mwaa) == 1 && length(module.airflow_ec2) == 0
    error_message = "Only MWAA should be deployed"
  }
  assert {
    condition     = length(module.gcp_federation) == 1 && length(module.gcp_federation[0].credential_config_keys) == 2
    error_message = "Airflow should get keyless access as the EXTRACT and TRANSFORM service accounts"
  }
  assert {
    condition     = module.gcp_federation[0].mwaa_requirements.path == "requirements.txt" && module.gcp_federation[0].mwaa_plugins.path == "plugins.zip"
    error_message = "MWAA should get the BigQuery client library and the credentials plugin automatically"
  }
  assert {
    condition     = length(module.airflow_mwaa[0].log_group_names) == 5
    error_message = "MWAA's five log groups should be Terraform-managed by default, so destroy removes them"
  }
}

run "mwaa_logs_kept_indefinitely_when_retention_is_null" {
  command = plan
  variables {
    use_airflow                     = true
    airflow_type                    = "mwaa"
    airflow_mwaa_log_retention_days = null
  }
  assert {
    condition     = length(module.airflow_mwaa[0].log_group_names) == 0
    error_message = "With retention null, MWAA should create and keep its own log groups"
  }
}

run "invalid_log_retention_rejected" {
  command = plan
  variables {
    airflow_mwaa_log_retention_days = 31
  }
  expect_failures = [var.airflow_mwaa_log_retention_days]
}

run "bigquery_with_ec2_airflow" {
  variables {
    use_airflow                  = true
    airflow_type                 = "ec2"
    ec2_inbound_cidr_restriction = "203.0.113.0/24"
  }
  assert {
    condition     = length(module.airflow_ec2) == 1 && length(module.airflow_mwaa) == 0
    error_message = "Only EC2 Airflow should be deployed"
  }
  assert {
    condition     = module.gcp_federation[0].credential_config_keys.transform == "dags/gcp/transform_credentials.json"
    error_message = "The TRANSFORM credential configuration should be synced with the DAGs"
  }
  assert {
    condition     = module.gcp_federation[0].mwaa_requirements == null && module.gcp_federation[0].mwaa_plugins == null
    error_message = "EC2 Airflow needs no requirements.txt or plugin"
  }
}

run "invalid_service_account_prefix_rejected" {
  command = plan
  variables {
    bigquery_service_account_prefix = "Data_Warehouse"
  }
  expect_failures = [var.bigquery_service_account_prefix]
}
