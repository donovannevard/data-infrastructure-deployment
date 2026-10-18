terraform {
  required_providers {
    fivetran = {
      source  = "fivetran/fivetran"
      version = "~> 1.9.17"
    }
  }
}

# Registers the new warehouse as a Fivetran destination, in a new group unless
# an existing group ID is supplied.
# On Snowflake and Redshift, Fivetran authenticates as the least-privilege
# EXTRACT service user, never the warehouse admin. On BigQuery it uses the
# group's own Google-managed service account, granted access by the stack. Source connectors (Postgres, Salesforce, etc.) are then added
# to this group in the Fivetran UI or with additional fivetran_connector resources.
locals {
  # Fivetran's service name for each warehouse
  service = lookup({ bigquery = "big_query" }, var.warehouse_type, var.warehouse_type)
}

resource "fivetran_group" "main" {
  count = var.create_group ? 1 : 0
  name  = var.fivetran_group_name
}

resource "fivetran_destination" "main" {
  group_id         = var.create_group ? fivetran_group.main[0].id : var.fivetran_group_id
  service          = local.service
  region           = var.fivetran_region
  time_zone_offset = var.fivetran_time_zone_offset

  config {
    # Snowflake and Redshift
    host     = var.host
    port     = var.port
    database = var.database
    auth     = var.warehouse_type == "snowflake" ? "PASSWORD" : null # Snowflake-only setting; Fivetran drops it otherwise
    user     = var.user
    password = var.password
    role     = var.role # Snowflake only

    # BigQuery
    project_id        = var.bigquery_project_id
    data_set_location = var.bigquery_location
  }
}
