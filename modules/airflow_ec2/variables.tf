variable "warehouse_type" {
  description = "Warehouse type"
  type        = string
}
variable "aws_prefix" {
  description = "AWS prefix for differentiating resources"
  type        = string
}
variable "aws_region" {
  description = "AWS region"
  type        = string
}
variable "aws_vpc_id" {
  description = "VPC ID for AWS resources"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the Airflow webserver to be accessible at (required when airflow_ec2_enable_https = true)"
  type        = string
  default     = null
}
variable "admin_email" {
  description = "Airflow admin email (defaults to admin@example.com)"
  type        = string
  default     = null
}
variable "aws_s3_bucket_name" {
  description = "The S3 bucket name to use for DAGs"
  type        = string
}
variable "aws_s3_bucket_arn" {
  description = "The S3 bucket ARN to use for DAGs"
  type        = string
}
variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
}
variable "ec2_inbound_cidr_restriction" {
  description = "CIDR block allowed to reach the Airflow webserver via the ALB"
  type        = string
}
variable "redshift_cluster_arn" {
  description = "Redshift cluster ARN (if using Redshift)"
  type        = string
  default     = null
}
variable "airflow_ec2_enable_https" {
  description = "Serve the Airflow webserver over HTTPS with an ACM certificate for domain_name. When false (default), the ALB serves plain HTTP restricted to ec2_inbound_cidr_restriction, which needs no DNS/ACM setup and is the fastest path."
  type        = bool
  default     = false
}
variable "route53_zone_id" {
  description = "Route53 hosted zone ID for domain_name. When set alongside airflow_ec2_enable_https, ACM DNS validation is fully automatic. When omitted, the certificate is created but requires a manual DNS record (see the acm_validation_record output) before it validates."
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}
variable "public_subnet_ids" {
  description = "Public subnet IDs (for ALB)"
  type        = list(string)
}
