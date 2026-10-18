# AWS - used for the Redshift cluster + both Airflow options (MWAA or EC2).
provider "aws" {
  region = var.aws_region
}

# Redshift - connection details come from the cluster created by module.aws
# in this same apply. First-apply note: on a brand-new deployment, if this
# ever produces a provider-configuration timing error, run
# `terraform apply -target=module.aws` once, then a plain `terraform apply`
# to finish everything else — a defensive fallback around a well-known
# Terraform limitation (a provider configured from a resource that doesn't
# exist yet). This has not been observed in testing.
provider "redshift" {
  host     = module.aws.redshift.host
  port     = module.aws.redshift.port
  username = module.aws.redshift.username
  password = module.aws.redshift.password
  database = module.aws.redshift.database
}

# Fivetran - only used when use_fivetran = true
provider "fivetran" {
  api_key    = var.use_fivetran ? var.fivetran_api_key : "unused"
  api_secret = var.use_fivetran ? var.fivetran_api_secret : "unused"
}

# Random provider - always needed for generated passwords
provider "random" {
}
