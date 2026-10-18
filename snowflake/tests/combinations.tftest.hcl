# Offline tests: every cloud provider is mocked (random runs for real, locally),
# so these run with no cloud accounts or credentials via `terraform test`. They
# check that each supported combination wires together and creates exactly the
# components it should.

mock_provider "snowflake" {}
mock_provider "fivetran" {}
mock_provider "aws" {
  source = "../tests/mocks/aws"
}

# Every input is set explicitly below so results don't depend on a local
# terraform.tfvars, which `terraform test` would otherwise also load.
variables {
  use_fivetran                 = true
  use_airflow                  = false
  airflow_type                 = "mwaa"
  aws_prefix                   = "etl"
  aws_region                   = "eu-west-2"
  ec2_inbound_cidr_restriction = null
  airflow_ec2_enable_https     = false
  airflow_ec2_domain           = null
  airflow_ec2_route53_zone_id  = null
  fivetran_group_id            = null
  snowflake_account_identifier = "TESTORG-TESTACCOUNT"
  snowflake_username           = "terraform"
  snowflake_password           = "not-a-real-password"
  snowflake_private_key_path   = null
  fivetran_api_key             = "key"
  fivetran_api_secret          = "secret"
  fivetran_region              = "AWS_EU_WEST_2"
}

run "snowflake_and_fivetran_default" {
  assert {
    condition     = length(module.fivetran) == 1
    error_message = "Fivetran should be deployed by default"
  }
  assert {
    condition     = length(module.aws) == 0 && length(module.airflow_mwaa) == 0 && length(module.airflow_ec2) == 0
    error_message = "No AWS resources should be created without Airflow"
  }
  assert {
    condition     = module.fivetran[0].fivetran_destination_id != null
    error_message = "Fivetran destination should be created"
  }
}

run "snowflake_only" {
  variables {
    use_fivetran = false
  }
  assert {
    condition     = length(module.fivetran) == 0 && length(module.aws) == 0
    error_message = "A bare warehouse deploy should create no Fivetran or AWS resources"
  }
}

run "snowflake_with_mwaa" {
  variables {
    use_airflow  = true
    airflow_type = "mwaa"
  }
  assert {
    condition     = length(module.airflow_mwaa) == 1 && length(module.airflow_ec2) == 0
    error_message = "Only MWAA should be deployed"
  }
}

run "snowflake_with_ec2_airflow" {
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
    condition     = startswith(output.airflow_ec2_url, "http://")
    error_message = "EC2 Airflow should default to plain HTTP"
  }
}

run "ec2_airflow_requires_cidr" {
  command = plan
  variables {
    use_airflow  = true
    airflow_type = "ec2"
  }
  expect_failures = [var.ec2_inbound_cidr_restriction]
}

run "invalid_airflow_type_rejected" {
  command = plan
  variables {
    airflow_type = "kubernetes"
  }
  expect_failures = [var.airflow_type]
}

run "fivetran_requires_credentials" {
  command = plan
  variables {
    fivetran_api_key = null
  }
  expect_failures = [var.fivetran_api_key]
}

run "snowflake_key_pair_auth" {
  command = plan
  variables {
    snowflake_password         = null
    snowflake_private_key_path = "/tmp/key.p8"
  }
}

run "snowflake_requires_exactly_one_auth_method" {
  command = plan
  variables {
    snowflake_private_key_path = "/tmp/key.p8"
  }
  expect_failures = [var.snowflake_private_key_path]
}
