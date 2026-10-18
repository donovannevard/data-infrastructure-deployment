terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  # Local state by default so a brand-new client engagement needs zero external
  # accounts to get started. See README "Design decisions" for switching to a
  # remote backend once you want locking/collaboration for a client.
  backend "local" {}
}

locals {
  # AWS is only needed here at all if you're also deploying Airflow.
  needs_aws = var.use_airflow

  airflow_role_name = (
    !var.use_airflow ? null :
    var.airflow_type == "mwaa" ? module.airflow_mwaa[0].iam_role_name : module.airflow_ec2[0].iam_role_name
  )
}

# Warehouse
module "bigquery" {
  source = "../modules/bigquery"

  project_id                 = var.gcp_project_id
  location                   = var.bigquery_location
  extract_dataset            = var.db_extract_schema
  transform_dataset          = var.db_transform_schema
  analysis_dataset           = var.db_analysis_schema
  delete_contents_on_destroy = var.bigquery_delete_contents_on_destroy

  service_account_prefix  = var.bigquery_service_account_prefix
  analyst_members         = var.bigquery_analyst_members
  admin_members           = var.bigquery_admin_members
  transform_impersonators = var.bigquery_transform_impersonators
}

# Fivetran. BigQuery destinations use the group's own Google-managed service
# account rather than credentials we create, so the group is created here and
# that account is granted access before the destination is registered (its
# setup tests run on creation).
resource "fivetran_group" "bigquery" {
  count = var.use_fivetran && var.fivetran_group_id == null ? 1 : 0
  name  = var.fivetran_group_name
}

locals {
  fivetran_group_id = !var.use_fivetran ? null : coalesce(var.fivetran_group_id, try(fivetran_group.bigquery[0].id, null))
}

data "fivetran_group_service_account" "this" {
  count = var.use_fivetran ? 1 : 0
  id    = local.fivetran_group_id
}

# BigQuery User: run load jobs and create a dataset per connector (Fivetran then
# owns the datasets it creates, and nothing else).
resource "google_project_iam_member" "fivetran" {
  count   = var.use_fivetran ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${data.fivetran_group_service_account.this[0].service_account}"

  depends_on = [module.bigquery.apis_enabled]
}

module "fivetran" {
  count  = var.use_fivetran ? 1 : 0
  source = "../modules/fivetran"

  warehouse_type            = "bigquery"
  create_group              = false # created above, so its service account can be granted access first
  fivetran_group_id         = local.fivetran_group_id
  fivetran_region           = var.fivetran_region
  fivetran_time_zone_offset = var.fivetran_time_zone_offset

  bigquery_project_id = module.bigquery.project_id
  bigquery_location   = module.bigquery.location

  depends_on = [google_project_iam_member.fivetran]
}

# Network + Airflow DAG bucket (only stood up if use_airflow = true)
module "aws" {
  count  = local.needs_aws ? 1 : 0
  source = "../modules/aws"

  warehouse_type       = "bigquery"
  use_airflow          = var.use_airflow
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  aws_prefix           = var.aws_prefix
  admin_user_name      = "unused" # Redshift-only
  aws_region           = var.aws_region
  aws_vpc_cidr         = var.aws_vpc_cidr
}

# Airflow
module "airflow_mwaa" {
  count  = var.use_airflow && var.airflow_type == "mwaa" ? 1 : 0
  source = "../modules/airflow_mwaa"

  warehouse_type        = "bigquery"
  aws_prefix            = var.aws_prefix
  aws_vpc_id            = module.aws[0].vpc_id
  aws_vpc_cidr          = var.aws_vpc_cidr
  private_subnet_ids    = module.aws[0].private_subnet_ids
  mwaa_environment      = var.airflow_mwaa_environment
  webserver_access_mode = var.airflow_mwaa_webserver_access_mode
  log_retention_days    = var.airflow_mwaa_log_retention_days
  aws_s3_bucket_name    = module.aws[0].aws_s3_bucket.airflow[0].bucket
  aws_s3_bucket_arn     = module.aws[0].aws_s3_bucket.airflow[0].arn
  redshift_cluster_arn  = null

  # Keyless BigQuery access (see modules/gcp_federation): the client library,
  # plus a plugin that authenticates every task before it runs
  requirements_s3_path           = module.gcp_federation[0].mwaa_requirements.path
  requirements_s3_object_version = module.gcp_federation[0].mwaa_requirements.version
  plugins_s3_path                = module.gcp_federation[0].mwaa_plugins.path
  plugins_s3_object_version      = module.gcp_federation[0].mwaa_plugins.version
}

module "airflow_ec2" {
  count  = var.use_airflow && var.airflow_type == "ec2" ? 1 : 0
  source = "../modules/airflow_ec2"

  warehouse_type     = "bigquery"
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

  # Keyless BigQuery access by default (see modules/gcp_federation)
  gcp_project_id       = var.gcp_project_id
  gcp_credentials_file = "/opt/airflow/dags/gcp/transform_credentials.json"
}

# Keyless BigQuery access for Airflow
module "gcp_federation" {
  count  = var.use_airflow ? 1 : 0
  source = "../modules/gcp_federation"

  project_id      = var.gcp_project_id
  apis_enabled    = module.bigquery.apis_enabled
  airflow_type    = var.airflow_type
  aws_role_name   = local.airflow_role_name
  dag_bucket_name = module.aws[0].aws_s3_bucket.airflow[0].bucket
  service_accounts = {
    for stage in ["extract", "transform"] : stage => {
      email = module.bigquery.service_accounts[stage]
      name  = module.bigquery.service_account_names[stage]
    }
  }
}
