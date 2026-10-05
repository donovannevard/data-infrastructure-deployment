variable "warehouse_type" {
  description = "Which warehouse to deploy: snowflake or redshift"
  type        = string

  validation {
    condition     = contains(["snowflake", "redshift"], var.warehouse_type)
    error_message = "warehouse_type must be one of: snowflake or redshift"
  }
}
variable "use_airflow" {
  description = "Whether to provision Airflow"
  type        = bool
}
variable "admin_user_name" {
  description = "The name to use for the admin database user that is created"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
variable "aws_vpc_cidr" {
  description = "VPC CIDR for AWS"
  type        = string
}
variable "aws_prefix" {
  description = "AWS prefix for differentiating resources"
  type        = string
}

variable "redshift_node_type" {
  description = "Redshift node type (unused when warehouse_type != \"redshift\")"
  type        = string
  default     = "ra3.large"
}
variable "redshift_node_count" {
  description = "Number of nodes in the cluster; 1 = single-node (unused when warehouse_type != \"redshift\")"
  type        = number
  default     = 1
}
variable "redshift_allowed_cidrs" {
  description = "CIDRs allowed to reach the Redshift cluster on port 5439 (unused when warehouse_type != \"redshift\")"
  type        = list(string)
  default     = []
}
variable "redshift_skip_final_snapshot" {
  description = "Skip the final snapshot when the Redshift cluster is destroyed (unused when warehouse_type != \"redshift\")"
  type        = bool
  default     = false
}
variable "redshift_publicly_accessible" {
  description = "Place the Redshift cluster in public subnets with a public endpoint (unused when warehouse_type != \"redshift\")"
  type        = bool
  default     = false
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the VPC's private subnets (one per AZ)"
  type        = list(string)
}
variable "public_subnet_cidrs" {
  description = "CIDR blocks for the VPC's public subnets (one per AZ)"
  type        = list(string)
}
