variable "warehouse_type" {
  description = "Warehouse type (for IAM policies)"
  type        = string
}
variable "aws_prefix" {
  description = "AWS prefix for differentiating resources"
  type        = string
}
variable "aws_vpc_id" {
  description = "VPC ID"
  type        = string
}
variable "aws_vpc_cidr" {
  description = "VPC CIDR for AWS"
  type        = string
}
variable "private_subnet_ids" {
  description = "Private subnet IDs (MWAA uses the first two; they must be in different AZs)"
  type        = list(string)
}

variable "mwaa_environment" {
  description = "MWAA environment size"
  type        = string
}
variable "aws_s3_bucket_name" {
  description = "The S3 bucket name to use for DAGs"
  type        = string
}
variable "aws_s3_bucket_arn" {
  description = "The S3 bucket ARN to use for DAGs"
  type        = string
}
variable "redshift_cluster_arn" {
  description = "Redshift cluster ARN (if using Redshift)"
  type        = string
  default     = null
}

variable "webserver_access_mode" {
  description = "PUBLIC_ONLY (UI reachable from the internet, still behind AWS IAM sign-in) or PRIVATE_ONLY (UI only reachable from inside the VPC)"
  type        = string
  default     = "PUBLIC_ONLY"
}
variable "mwaa_max_workers" {
  description = "MWAA max workers"
  type        = number
  default     = 5
}
variable "mwaa_dag_concurrency" {
  description = "MWAA max active tasks per DAG"
  type        = string
  default     = "16"
}
variable "mwaa_parallelism" {
  description = "MWAA parallelism setting"
  type        = string
  default     = "16"
}
variable "mwaa_max_runs_per_dag" {
  description = "MWAA max concurrent runs per DAG"
  type        = string
  default     = "10"
}
