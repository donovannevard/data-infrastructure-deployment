terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.79"
    }
    redshift = {
      source  = "brainly/redshift"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  # Redshift database names allow only lowercase letters, digits, underscores and
  # dollar signs, so hyphens from the AWS naming prefix become underscores.
  database_name = "${replace(lower(var.aws_prefix), "-", "_")}_database"

  is_redshift = var.warehouse_type == "redshift"
  # Unique per deployment, so a snapshot left by a previous destroy never collides
  final_snapshot_identifier = local.is_redshift ? "${var.aws_prefix}-redshift-final-${random_id.snapshot[0].hex}" : null
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.9"

  name = "${var.aws_prefix}-vpc"
  cidr = var.aws_vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true
}

# Redshift cluster
resource "random_password" "admin" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()_+-=" # Redshift rejects @, quotes, slashes and spaces
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}
resource "aws_redshift_subnet_group" "main" {
  count       = var.warehouse_type == "redshift" ? 1 : 0
  name        = "${var.aws_prefix}-redshift-subnet-group"
  description = "Subnet group for Redshift cluster"
  # Private subnets by default. Opting into public access moves the cluster into
  # the public subnets so it is routable from your allowed CIDRs (still
  # firewalled by the security group below).
  subnet_ids = var.redshift_publicly_accessible ? module.vpc.public_subnets : module.vpc.private_subnets
}
resource "aws_redshift_cluster" "main" {
  count              = var.warehouse_type == "redshift" ? 1 : 0
  cluster_identifier = "${var.aws_prefix}-redshift"
  database_name      = local.database_name
  master_username    = var.admin_user_name
  master_password    = random_password.admin.result

  node_type       = var.redshift_node_type
  cluster_type    = var.redshift_node_count > 1 ? "multi-node" : "single-node"
  number_of_nodes = var.redshift_node_count

  publicly_accessible = var.redshift_publicly_accessible
  encrypted           = true

  # AWS enables this by default for RA3/RG clusters (it lets the cluster move AZs
  # during an outage, keeping the same endpoint); the provider default of false
  # would otherwise disable it on every apply.
  availability_zone_relocation_enabled = true
  skip_final_snapshot                  = var.redshift_skip_final_snapshot
  final_snapshot_identifier            = var.redshift_skip_final_snapshot ? null : local.final_snapshot_identifier

  vpc_security_group_ids    = [aws_security_group.redshift[0].id]
  cluster_subnet_group_name = aws_redshift_subnet_group.main[0].name

  automated_snapshot_retention_period = 7

  # The whole VPC (including its internet routes) is created before, and so
  # destroyed after, the cluster: Terraform must still be able to reach the
  # cluster on destroy to drop the users and grants in module.redshift.
  # The snapshot notice likewise outlives the cluster (see below).
  depends_on = [module.vpc, terraform_data.final_snapshot_notice]
}

resource "random_id" "snapshot" {
  count       = local.is_redshift ? 1 : 0
  byte_length = 4
}

# Terraform can't manage the final snapshot (AWS creates it while deleting the
# cluster), so print where it is and how to remove it once destroy has finished.
resource "terraform_data" "final_snapshot_notice" {
  count = local.is_redshift && !var.redshift_skip_final_snapshot ? 1 : 0
  input = {
    snapshot = local.final_snapshot_identifier
    region   = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo ""
      echo "NOTE: Redshift final snapshot '${self.input.snapshot}' was kept in ${self.input.region}."
      echo "Delete it once you no longer need it (snapshots incur storage costs):"
      echo "  aws redshift delete-cluster-snapshot --snapshot-identifier ${self.input.snapshot} --region ${self.input.region}"
      echo ""
    EOT
  }
}
resource "aws_security_group" "redshift" {
  count       = var.warehouse_type == "redshift" ? 1 : 0
  name        = "${var.aws_prefix}-redshift-sg"
  description = "Security group for Redshift cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow inbound from Fivetran / Airflow / dbt"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = var.redshift_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# S3 bucket for DAGs
resource "random_id" "bucket" {
  byte_length = 8
}
resource "aws_s3_bucket" "airflow" {
  count  = var.use_airflow == true ? 1 : 0
  bucket = "${var.aws_prefix}-airflow-dags-${random_id.bucket.hex}"
}
resource "aws_s3_bucket_versioning" "airflow" {
  count  = var.use_airflow == true ? 1 : 0
  bucket = aws_s3_bucket.airflow[0].id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_public_access_block" "airflow" {
  count  = var.use_airflow == true ? 1 : 0
  bucket = aws_s3_bucket.airflow[0].id

  # Required by MWAA, and good hygiene for the EC2 option too.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "airflow" {
  count  = var.use_airflow == true ? 1 : 0
  bucket = aws_s3_bucket.airflow[0].bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
