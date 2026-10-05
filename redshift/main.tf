terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.79"
    }
    redshift = {
      source  = "brainly/redshift"
      version = "~> 1.0"
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

# Network + Redshift cluster + (optionally) Airflow DAG bucket
module "aws" {
  source = "../modules/aws"

  warehouse_type               = "redshift"
  use_airflow                  = var.use_airflow
  public_subnet_cidrs          = var.public_subnet_cidrs
  private_subnet_cidrs         = var.private_subnet_cidrs
  aws_prefix                   = var.aws_prefix
  admin_user_name              = var.db_admin_user_name
  aws_region                   = var.aws_region
  aws_vpc_cidr                 = var.aws_vpc_cidr
  redshift_node_type           = var.redshift_node_type
  redshift_node_count          = var.redshift_node_count
  redshift_allowed_cidrs       = var.redshift_allowed_cidrs
  redshift_publicly_accessible = var.redshift_publicly_accessible
  redshift_skip_final_snapshot = var.redshift_skip_final_snapshot
}

# Warehouse
module "redshift" {
  source = "../modules/redshift"

  admin_user_name  = var.db_admin_user_name
  extract_schema   = var.db_extract_schema
  transform_schema = var.db_transform_schema
  analysis_schema  = var.db_analysis_schema
}

# Fivetran
module "fivetran" {
  count  = var.use_fivetran ? 1 : 0
  source = "../modules/fivetran"

  warehouse_type            = "redshift"
  fivetran_group_id         = var.fivetran_group_id
  fivetran_group_name       = var.fivetran_group_name
  fivetran_region           = var.fivetran_region
  fivetran_time_zone_offset = var.fivetran_time_zone_offset

  # Connection details from the cluster, but auth as the least-privilege
  # EXTRACT service user (mirrors the Snowflake stack) rather than the master admin.
  host     = module.aws.redshift.host
  port     = module.aws.redshift.port
  database = module.aws.redshift.database
  user     = module.redshift.service_users.extract.name
  password = module.redshift.service_users.extract.password
}

# Airflow
module "airflow_mwaa" {
  count  = var.use_airflow && var.airflow_type == "mwaa" ? 1 : 0
  source = "../modules/airflow_mwaa"

  warehouse_type     = "redshift"
  aws_prefix         = var.aws_prefix
  aws_vpc_id         = module.aws.vpc_id
  aws_vpc_cidr       = var.aws_vpc_cidr
  private_subnet_ids = module.aws.private_subnet_ids

  mwaa_environment      = var.airflow_mwaa_environment
  webserver_access_mode = var.airflow_mwaa_webserver_access_mode
  aws_s3_bucket_name    = module.aws.aws_s3_bucket.airflow[0].bucket
  aws_s3_bucket_arn     = module.aws.aws_s3_bucket.airflow[0].arn
  redshift_cluster_arn  = module.aws.redshift.arn
}

module "airflow_ec2" {
  count  = var.use_airflow && var.airflow_type == "ec2" ? 1 : 0
  source = "../modules/airflow_ec2"

  warehouse_type     = "redshift"
  aws_prefix         = var.aws_prefix
  aws_region         = var.aws_region
  aws_vpc_id         = module.aws.vpc_id
  private_subnet_ids = module.aws.private_subnet_ids
  public_subnet_ids  = module.aws.public_subnet_ids

  domain_name                  = var.airflow_ec2_domain
  admin_email                  = var.airflow_ec2_admin_email
  aws_s3_bucket_name           = module.aws.aws_s3_bucket.airflow[0].bucket
  aws_s3_bucket_arn            = module.aws.aws_s3_bucket.airflow[0].arn
  ec2_instance_type            = var.ec2_instance_type
  ec2_inbound_cidr_restriction = var.ec2_inbound_cidr_restriction
  airflow_ec2_enable_https     = var.airflow_ec2_enable_https
  route53_zone_id              = var.airflow_ec2_route53_zone_id
  redshift_cluster_arn         = module.aws.redshift.arn
}
