# AWS - only used here if use_airflow = true. Credential validation is skipped
# entirely when Airflow isn't deployed, so a pure Snowflake + Fivetran client
# needs no AWS account at all.
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = !local.needs_aws
  skip_region_validation      = !local.needs_aws
  skip_requesting_account_id  = !local.needs_aws
}

# Authenticates with a key pair if snowflake_private_key_path is set (recommended,
# and required where Snowflake blocks password-only sign-in), otherwise a password.
provider "snowflake" {
  account          = var.snowflake_account_identifier
  user             = var.snowflake_username
  password         = var.snowflake_password
  private_key_path = var.snowflake_private_key_path != null ? pathexpand(var.snowflake_private_key_path) : null
  authenticator    = var.snowflake_private_key_path != null ? "JWT" : null
  role             = var.snowflake_role
}

# Fivetran - only used when use_fivetran = true
provider "fivetran" {
  api_key    = var.use_fivetran ? var.fivetran_api_key : "unused"
  api_secret = var.use_fivetran ? var.fivetran_api_secret : "unused"
}

# Random provider - always needed for generated passwords
provider "random" {
}
