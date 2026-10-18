variable "project_id" {
  description = "Google Cloud project holding the warehouse and the identity pool"
  type        = string
}
variable "aws_role_name" {
  description = "Name of the IAM role Airflow runs as"
  type        = string
}
variable "service_accounts" {
  description = "Service accounts Airflow may act as, keyed by stage, with their email and fully qualified name"
  type = map(object({
    email = string
    name  = string
  }))
}
variable "apis_enabled" {
  description = "APIs enabled by the bigquery module (IAM and STS must be on before the pool is created)"
  type        = list(string)
}
variable "airflow_type" {
  description = "mwaa or ec2: MWAA additionally gets a requirements.txt and a credentials plugin"
  type        = string
}
variable "dag_bucket_name" {
  description = "S3 bucket Airflow syncs DAGs from; credential configs go under dags/gcp/"
  type        = string
}
