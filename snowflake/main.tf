terraform {
  required_version = ">= 1.9.0"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.92.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.79"
    }
    fivetran = {
      source  = "fivetran/fivetran"
      version = "~> 1.9.17"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state by default so a brand-new client engagement needs zero external
  # accounts to get started. See README "Remote state" for how to switch to
  # S3 or Terraform Cloud once you want locking/collaboration for a client.
  backend "local" {}
}

locals {
  # AWS is only needed here at all if you're also deploying Airflow.
  needs_aws = var.use_airflow
}

# Warehouse
module "snowflake" {
  source = "../modules/snowflake"

  admin_user_name  = var.db_admin_user_name
  extract_schema   = var.db_extract_schema
  transform_schema = var.db_transform_schema
  analysis_schema  = var.db_analysis_schema

  snowflake_extract_wh_size   = var.snowflake_extract_wh_size
  snowflake_transform_wh_size = var.snowflake_transform_wh_size
  snowflake_analysis_wh_size  = var.snowflake_analysis_wh_size
}

# Fivetran
module "fivetran" {
  count  = var.use_fivetran ? 1 : 0
  source = "../modules/fivetran"

  warehouse_type            = "snowflake"
  fivetran_group_id         = var.fivetran_group_id
  fivetran_group_name       = var.fivetran_group_name
  fivetran_region           = var.fivetran_region
  fivetran_time_zone_offset = var.fivetran_time_zone_offset

  host     = "${var.snowflake_account_identifier}.snowflakecomputing.com"
  port     = 443
  database = module.snowflake.databases.extract
  user     = module.snowflake.service_users.extract.name
  password = module.snowflake.service_users.extract.password
  role     = module.snowflake.roles.extract
}

# Network + Airflow DAG bucket (only stood up if use_airflow = true)
module "aws" {
  count  = local.needs_aws ? 1 : 0
  source = "../modules/aws"

  warehouse_type       = "snowflake"
  use_airflow          = var.use_airflow
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  aws_prefix           = var.aws_prefix
  admin_user_name      = var.db_admin_user_name
  aws_region           = var.aws_region
  aws_vpc_cidr         = var.aws_vpc_cidr
}

# Airflow
module "airflow_mwaa" {
  count  = var.use_airflow && var.airflow_type == "mwaa" ? 1 : 0
  source = "../modules/airflow_mwaa"

  warehouse_type     = "snowflake"
  aws_prefix         = var.aws_prefix
  aws_vpc_id         = module.aws[0].vpc_id
  aws_vpc_cidr       = var.aws_vpc_cidr
  private_subnet_ids = module.aws[0].private_subnet_ids

  mwaa_environment      = var.airflow_mwaa_environment
  webserver_access_mode = var.airflow_mwaa_webserver_access_mode
  aws_s3_bucket_name    = module.aws[0].aws_s3_bucket.airflow[0].bucket
  aws_s3_bucket_arn     = module.aws[0].aws_s3_bucket.airflow[0].arn
  redshift_cluster_arn  = null
}

module "airflow_ec2" {
  count  = var.use_airflow && var.airflow_type == "ec2" ? 1 : 0
  source = "../modules/airflow_ec2"

  warehouse_type     = "snowflake"
  aws_prefix         = var.aws_prefix
  aws_region         = var.aws_region
  aws_vpc_id         = module.aws[0].vpc_id
  private_subnet_ids = module.aws[0].private_subnet_ids
  public_subnet_ids  = module.aws[0].public_subnet_ids

  domain_name                  = var.airflow_ec2_domain
  admin_email                  = var.airflow_ec2_admin_email
  aws_s3_bucket_name           = module.aws[0].aws_s3_bucket.airflow[0].bucket
  aws_s3_bucket_arn            = module.aws[0].aws_s3_bucket.airflow[0].arn
  ec2_instance_type            = var.ec2_instance_type
  ec2_inbound_cidr_restriction = var.ec2_inbound_cidr_restriction
  airflow_ec2_enable_https     = var.airflow_ec2_enable_https
  route53_zone_id              = var.airflow_ec2_route53_zone_id
  redshift_cluster_arn         = null
}
