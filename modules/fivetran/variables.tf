variable "warehouse_type" {
  description = "Which warehouse is being used (snowflake or redshift)"
  type        = string

  validation {
    condition     = contains(["snowflake", "redshift"], var.warehouse_type)
    error_message = "warehouse_type must be one of: snowflake or redshift"
  }
}

variable "fivetran_group_id" {
  description = "Existing Fivetran group to use. Null creates a new group named fivetran_group_name."
  type        = string
  default     = null
}
variable "fivetran_group_name" {
  description = "Name for the Fivetran group created when fivetran_group_id is null"
  type        = string
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
  description = "Warehouse hostname (e.g. <account>.snowflakecomputing.com, or the Redshift cluster endpoint)"
  type        = string
}
variable "port" {
  description = "Warehouse port"
  type        = number
}
variable "database" {
  description = "Database Fivetran should load into"
  type        = string
}
variable "user" {
  description = "Username for the database user that will perform the extract queries"
  type        = string
}
variable "password" {
  description = "Password for the database user that will perform the extract queries"
  type        = string
  sensitive   = true
}
variable "role" {
  description = "Snowflake role for the extract user (null for Redshift)"
  type        = string
  default     = null
}
