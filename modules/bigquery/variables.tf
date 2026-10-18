variable "project_id" {
  description = "Google Cloud project that holds the warehouse"
  type        = string
}
variable "location" {
  description = "BigQuery location for the datasets (e.g. EU, US, europe-west2)"
  type        = string
}

variable "extract_dataset" {
  description = "Dataset name for the extract layer"
  type        = string
}
variable "transform_dataset" {
  description = "Dataset name for the transform layer"
  type        = string
}
variable "analysis_dataset" {
  description = "Dataset name for the analysis layer"
  type        = string
}
variable "delete_contents_on_destroy" {
  description = "Allow destroy to delete datasets that still contain tables"
  type        = bool
  default     = false
}

variable "service_account_prefix" {
  description = "Prefix for the service account IDs (<prefix>-extract, -transform, -load)"
  type        = string
}
variable "analyst_members" {
  description = "IAM principals with read access to the analysis dataset (e.g. group:analysts@example.com)"
  type        = list(string)
  default     = []
}
variable "admin_members" {
  description = "IAM principals with read access to every dataset (e.g. group:data-admins@example.com)"
  type        = list(string)
  default     = []
}
variable "transform_impersonators" {
  description = "IAM principals allowed to impersonate the TRANSFORM service account, for keyless dbt runs (e.g. user:you@example.com)"
  type        = list(string)
  default     = []
}
