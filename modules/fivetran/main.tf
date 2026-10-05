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
# Fivetran authenticates as the least-privilege EXTRACT service user, never the
# warehouse admin. Source connectors (Postgres, Salesforce, etc.) are then added
# to this group in the Fivetran UI or with additional fivetran_connector resources.
resource "fivetran_group" "main" {
  count = var.fivetran_group_id == null ? 1 : 0
  name  = var.fivetran_group_name
}

resource "fivetran_destination" "main" {
  group_id         = var.fivetran_group_id != null ? var.fivetran_group_id : fivetran_group.main[0].id
  service          = var.warehouse_type
  region           = var.fivetran_region
  time_zone_offset = var.fivetran_time_zone_offset

  config {
    host     = var.host
    port     = var.port
    database = var.database
    auth     = var.warehouse_type == "snowflake" ? "PASSWORD" : null # Snowflake-only setting; Fivetran drops it for Redshift
    user     = var.user
    password = var.password
    role     = var.role # Snowflake only; null for Redshift
  }
}
