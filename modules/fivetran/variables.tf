variable "warehouse_type" {
  description = "Which warehouse is being used (snowflake or redshift)"
  type        = string

  validation {
    condition     = contains(["snowflake", "redshift", "bigquery"], var.warehouse_type)
    error_message = "warehouse_type must be one of: snowflake, redshift or bigquery"
  }
}

variable "create_group" {
  description = "Create a new Fivetran group named fivetran_group_name, rather than using fivetran_group_id"
  type        = bool
}
variable "fivetran_group_id" {
  description = "Existing Fivetran group to use when create_group = false"
  type        = string
  default     = null
}
variable "fivetran_group_name" {
  description = "Name for the Fivetran group created when create_group = true"
  type        = string
  default     = null
}
variable "fivetran_region" {
  description = "Fivetran region"
  type        = string
}
variable "fivetran_time_zone_offset" {
  description = "Fivetran timezone offset"
  type        = string
}

variable "host" {
  description = "Warehouse hostname (e.g. <account>.snowflakecomputing.com, or the Redshift cluster endpoint); null for BigQuery"
  type        = string
  default     = null
}
variable "port" {
  description = "Warehouse port"
  type        = number
  default     = null
}
variable "database" {
  description = "Database Fivetran should load into"
  type        = string
  default     = null
}
variable "user" {
  description = "Username for the database user that will perform the extract queries"
  type        = string
  default     = null
}
variable "password" {
  description = "Password for the database user that will perform the extract queries"
  type        = string
  sensitive   = true
  default     = null
}
variable "role" {
  description = "Snowflake role for the extract user (null for Redshift)"
  type        = string
  default     = null
}

variable "bigquery_project_id" {
  description = "Google Cloud project for a BigQuery destination (null otherwise)"
  type        = string
  default     = null
}
variable "bigquery_location" {
  description = "BigQuery data location for a BigQuery destination (null otherwise)"
  type        = string
  default     = null
}
