variable "admin_user_name" {
  description = "The name to use for the admin database user that is created"
  type        = string
}

variable "extract_schema" {
  description = "Schema name to use for the extract layer"
  type        = string
}
variable "transform_schema" {
  description = "Schema name to use for the transform layer"
  type        = string
}
variable "analysis_schema" {
  description = "Schema name to use for the analysis layer"
  type        = string
}

variable "snowflake_extract_wh_size" {
  description = "Snowflake extract warehouse instance size"
  type        = string
}
variable "snowflake_transform_wh_size" {
  description = "Snowflake transform warehouse instance size"
  type        = string
}
variable "snowflake_analysis_wh_size" {
  description = "Snowflake analysis warehouse instance size"
  type        = string
}
