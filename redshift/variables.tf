# Core choices
variable "use_fivetran" {
  description = "Whether to provision a Fivetran destination + connector"
  type        = bool
  default     = true
}
variable "use_airflow" {
  description = "Whether to provision Airflow"
  type        = bool
  default     = false
}
variable "airflow_type" {
  description = "Which Airflow deployment to use when use_airflow = true"
  type        = string
  default     = "mwaa"

  validation {
    condition     = contains(["mwaa", "ec2"], var.airflow_type)
    error_message = "airflow_type must be mwaa or ec2"
  }
}

# Database
variable "db_admin_user_name" {
  description = "The name to use for the admin database user that is created"
  type        = string
  default     = "etladmin"
}
variable "db_extract_schema" {
  description = "The schema name to use for the extract layer"
  type        = string
  default     = "extract"
}
variable "db_transform_schema" {
  description = "The schema name to use for the transform layer"
  type        = string
  default     = "transform"
}
variable "db_analysis_schema" {
  description = "The schema name to use for the analysis layer"
  type        = string
  default     = "analysis"
}

# Fivetran (required when use_fivetran = true)
variable "fivetran_api_key" {
  description = "Fivetran API key"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.use_fivetran || var.fivetran_api_key != null
    error_message = "fivetran_api_key is required when use_fivetran = true."
  }
}
variable "fivetran_api_secret" {
  description = "Fivetran API secret"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.use_fivetran || var.fivetran_api_secret != null
    error_message = "fivetran_api_secret is required when use_fivetran = true."
  }
}
variable "fivetran_group_id" {
  description = "Existing Fivetran group to load into. Leave unset to have Terraform create one."
  type        = string
  default     = null
}
variable "fivetran_group_name" {
  description = "Name of the Fivetran group to create when fivetran_group_id is unset (letters, digits and underscores)"
  type        = string
  default     = "redshift_warehouse"
}
variable "fivetran_region" {
  description = "Fivetran processing region (e.g. AWS_EU_WEST_2, AWS_US_EAST_1)"
  type        = string
  default     = null

  validation {
    condition     = !var.use_fivetran || var.fivetran_region != null
    error_message = "fivetran_region is required when use_fivetran = true."
  }
}
variable "fivetran_time_zone_offset" {
  description = "Fivetran timezone offset"
  type        = string
  default     = "0"
}

# AWS (always required for Redshift)
variable "aws_prefix" {
  description = "Prefix for every AWS resource name: lowercase letters, digits and hyphens, max 20 characters (load balancer names are capped at 32)"
  type        = string
  default     = "etl"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.aws_prefix))
    error_message = "aws_prefix must be 2-20 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
variable "aws_vpc_cidr" {
  description = "VPC CIDR for AWS"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.aws_vpc_cidr, 0))
    error_message = "aws_vpc_cidr must be a valid CIDR block."
  }
}
variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (one per AZ, a/b/c)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ, a/b/c; used by the NAT gateway and ALB)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# Redshift-specific
variable "redshift_node_type" {
  description = "Redshift node type (RA3 or RG; DC2 is no longer available for new clusters)"
  type        = string
  default     = "ra3.large"
}
variable "redshift_node_count" {
  description = "Number of nodes. 1 = single-node (cheapest; fine for small workloads and testing), 2+ = multi-node"
  type        = number
  default     = 1

  validation {
    condition     = var.redshift_node_count >= 1
    error_message = "redshift_node_count must be at least 1."
  }
}
variable "redshift_allowed_cidrs" {
  description = "CIDRs allowed to reach the Redshift cluster on port 5439: your office/VPN range, plus Fivetran's IPs for your region if use_fivetran = true. No default — pick deliberate values, never 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.redshift_allowed_cidrs) > 0 && alltrue([for c in var.redshift_allowed_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "redshift_allowed_cidrs must be a non-empty list of valid CIDR blocks, and must not include 0.0.0.0/0."
  }
}
variable "redshift_skip_final_snapshot" {
  description = "Skip the final snapshot on terraform destroy. Keep false for client deployments; set true for throwaway test deployments."
  type        = bool
  default     = false
}
variable "redshift_publicly_accessible" {
  description = "Give the cluster a public endpoint (still firewalled to redshift_allowed_cidrs). Required when running Terraform from a laptop or using Fivetran without an SSH tunnel/PrivateLink; leave false if you run Terraform from inside the VPC."
  type        = bool
  default     = false
}

# Airflow/EC2-specific
variable "airflow_ec2_domain" {
  description = "Domain to assign to the Airflow webserver (required if airflow_ec2_enable_https = true)"
  type        = string
  default     = null
}
variable "airflow_ec2_admin_email" {
  description = "The email to use for the admin user for the EC2 Airflow instance"
  type        = string
  default     = null
}
variable "airflow_ec2_enable_https" {
  description = "Serve EC2 Airflow over HTTPS with an ACM certificate. Default false: plain HTTP behind the ALB, restricted to ec2_inbound_cidr_restriction — fastest path, no DNS wait."
  type        = bool
  default     = false
}
variable "airflow_ec2_route53_zone_id" {
  description = "Route53 hosted zone ID for airflow_ec2_domain. If set alongside airflow_ec2_enable_https, ACM DNS validation is fully automatic."
  type        = string
  default     = null
}
variable "ec2_inbound_cidr_restriction" {
  description = "CIDR allowed to reach the Airflow webserver (e.g. your office/VPN range). No default — pick a deliberate value, do not leave this open to 0.0.0.0/0."
  type        = string
  default     = null

  validation {
    condition     = !(var.use_airflow && var.airflow_type == "ec2") || (var.ec2_inbound_cidr_restriction != null && can(cidrhost(var.ec2_inbound_cidr_restriction, 0)))
    error_message = "ec2_inbound_cidr_restriction must be a valid CIDR block when use_airflow = true and airflow_type = \"ec2\"."
  }
}
variable "ec2_instance_type" {
  description = "Instance size for the EC2 instance running Airflow"
  type        = string
  default     = "t3.small"
}

# Airflow/MWAA-specific
variable "airflow_mwaa_webserver_access_mode" {
  description = "PUBLIC_ONLY: the Airflow UI is reachable from anywhere but still requires AWS IAM sign-in. PRIVATE_ONLY: reachable only from inside the VPC (VPN/bastion)."
  type        = string
  default     = "PUBLIC_ONLY"

  validation {
    condition     = contains(["PUBLIC_ONLY", "PRIVATE_ONLY"], var.airflow_mwaa_webserver_access_mode)
    error_message = "airflow_mwaa_webserver_access_mode must be PUBLIC_ONLY or PRIVATE_ONLY."
  }
}
variable "airflow_mwaa_environment" {
  description = "Instance size for the MWAA instance running Airflow"
  type        = string
  default     = "mw1.small"
}
