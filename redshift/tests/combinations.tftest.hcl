# Offline tests: every cloud provider is mocked (random runs for real, locally),
# so these run with no cloud accounts or credentials via `terraform test`. They
# check that each supported combination wires together and creates exactly the
# components it should.

mock_provider "aws" {
  source = "../tests/mocks/aws"
}
mock_provider "redshift" {}
mock_provider "fivetran" {}

# Every input is set explicitly below so results don't depend on a local
# terraform.tfvars, which `terraform test` would otherwise also load.
variables {
  use_fivetran                 = true
  use_airflow                  = false
  airflow_type                 = "mwaa"
  aws_prefix                   = "etl"
  aws_region                   = "eu-west-2"
  redshift_allowed_cidrs       = ["203.0.113.10/32"]
  redshift_publicly_accessible = false
  redshift_skip_final_snapshot = false
  ec2_inbound_cidr_restriction = null
  airflow_ec2_enable_https     = false
  airflow_ec2_domain           = null
  airflow_ec2_route53_zone_id  = null
  fivetran_group_id            = null
  fivetran_api_key             = "key"
  fivetran_api_secret          = "secret"
  fivetran_region              = "AWS_EU_WEST_2"
}

run "redshift_and_fivetran_default" {
  assert {
    condition     = length(module.fivetran) == 1
    error_message = "Fivetran should be deployed by default"
  }
  assert {
    condition     = length(module.airflow_mwaa) == 0 && length(module.airflow_ec2) == 0
    error_message = "Airflow should not be deployed by default"
  }
}

run "redshift_only" {
  variables {
    use_fivetran = false
  }
  assert {
    condition     = length(module.fivetran) == 0
    error_message = "Fivetran should not be deployed"
  }
}

run "redshift_with_mwaa" {
  variables {
    use_airflow  = true
    airflow_type = "mwaa"
  }
  assert {
    condition     = length(module.airflow_mwaa) == 1 && length(module.airflow_ec2) == 0
    error_message = "Only MWAA should be deployed"
  }
}

run "redshift_with_ec2_airflow" {
  variables {
    use_airflow                  = true
    airflow_type                 = "ec2"
    ec2_inbound_cidr_restriction = "203.0.113.0/24"
  }
  assert {
    condition     = length(module.airflow_ec2) == 1 && length(module.airflow_mwaa) == 0
    error_message = "Only EC2 Airflow should be deployed"
  }
}

run "open_cidr_rejected" {
  command = plan
  variables {
    redshift_allowed_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.redshift_allowed_cidrs]
}

run "final_snapshot_kept_by_default" {
  assert {
    condition     = length(module.aws.final_snapshot_notice) == 1
    error_message = "A final snapshot (and destroy notice) should be configured by default"
  }
}

run "final_snapshot_skippable" {
  variables {
    redshift_skip_final_snapshot = true
  }
  assert {
    condition     = length(module.aws.final_snapshot_notice) == 0
    error_message = "No snapshot notice should exist when the final snapshot is skipped"
  }
}

run "hyphenated_prefix_gives_valid_database_name" {
  variables {
    aws_prefix = "redshift-infra-test"
  }
  assert {
    condition     = module.aws.redshift.database == "redshift_infra_test_database"
    error_message = "Hyphens in aws_prefix should become underscores in the Redshift database name"
  }
}

run "invalid_prefix_rejected" {
  command = plan
  variables {
    aws_prefix = "Acme_Co"
  }
  expect_failures = [var.aws_prefix]
}
