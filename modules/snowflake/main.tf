terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.92.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure a warehouse for each stage for cost-optimization purposes
resource "snowflake_warehouse" "extract" {
  name                = "EXTRACT_WH"
  warehouse_size      = var.snowflake_extract_wh_size
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "Warehouse for Fivetran extract"
}
resource "snowflake_warehouse" "transform" {
  name                = "TRANSFORM_WH"
  warehouse_size      = var.snowflake_transform_wh_size
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "Warehouse for dbt transformations"
}
resource "snowflake_warehouse" "analysis" {
  name                = "ANALYSIS_WH"
  warehouse_size      = var.snowflake_analysis_wh_size
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "Warehouse for analysis, BI tools & analysts"
}

# Configure databases within warehouses
resource "snowflake_database" "extract" {
  name    = "EXTRACT"
  comment = "Fivetran extract database (raw data)"
}
resource "snowflake_database" "transform" {
  name    = "TRANSFORM"
  comment = "dbt transformation database"
}
resource "snowflake_database" "analysis" {
  name    = "ANALYSIS"
  comment = "Analysis / BI / analyst-facing database"
}

# Configure schemas
resource "snowflake_schema" "extract" {
  name     = var.extract_schema
  database = snowflake_database.extract.name
  comment  = "Fivetran landing schema"
}
resource "snowflake_schema" "transform" {
  name     = var.transform_schema
  database = snowflake_database.transform.name
  comment  = "dbt model schema"
}
resource "snowflake_schema" "analysis" {
  name     = var.analysis_schema
  database = snowflake_database.analysis.name
  comment  = "Final forms for BI tools"
}

# Create the roles for handling permissions
resource "snowflake_role" "admin" {
  name    = "ADMIN_ROLE"
  comment = "Admin group - read access across all 3 DBs (senior analysts)"
}
resource "snowflake_role" "extract" {
  name    = "EXTRACT_ROLE"
  comment = "Role for Fivetran extract into the DB"
}
resource "snowflake_role" "transform" {
  name    = "TRANSFORM_ROLE"
  comment = "Role for dbt transformations"
}
resource "snowflake_role" "load" {
  name    = "LOAD_ROLE"
  comment = "Role for BI tool connections to the DB"
}
resource "snowflake_role" "analyst" {
  name    = "ANALYST_ROLE"
  comment = "Analyst group - read access to analysis DB only"
}

# Create the service users
resource "random_password" "admin" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()_+-="
}
resource "random_password" "extract" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()_+-="
}
resource "random_password" "transform" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()_+-="
}
resource "random_password" "load" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()_+-="
}
resource "snowflake_user" "admin" {
  name                 = var.admin_user_name
  password             = random_password.admin.result
  default_role         = snowflake_role.admin.name
  default_warehouse    = snowflake_warehouse.analysis.name
  must_change_password = false
  comment              = "Admin user for full access"
}
resource "snowflake_user" "extract" {
  name                 = "EXTRACT"
  password             = random_password.extract.result
  default_role         = snowflake_role.extract.name
  default_warehouse    = snowflake_warehouse.extract.name
  must_change_password = false
  comment              = "Fivetran extract user"
}
resource "snowflake_user" "transform" {
  name                 = "TRANSFORM"
  password             = random_password.transform.result
  default_role         = snowflake_role.transform.name
  default_warehouse    = snowflake_warehouse.transform.name
  must_change_password = false
  comment              = "dbt transform user"
}
resource "snowflake_user" "load" {
  name                 = "LOAD"
  password             = random_password.load.result
  default_role         = snowflake_role.load.name
  default_warehouse    = snowflake_warehouse.analysis.name
  must_change_password = false
  comment              = "BI tool / load user for reading from the analysis database"
}

# Assign roles to users
resource "snowflake_grant_account_role" "admin_user" {
  role_name = snowflake_role.admin.name
  user_name = snowflake_user.admin.name
}
resource "snowflake_grant_account_role" "extract_user" {
  role_name = snowflake_role.extract.name
  user_name = snowflake_user.extract.name
}
resource "snowflake_grant_account_role" "transform_user" {
  role_name = snowflake_role.transform.name
  user_name = snowflake_user.transform.name
}
resource "snowflake_grant_account_role" "load_user" {
  role_name = snowflake_role.load.name
  user_name = snowflake_user.load.name
}

# Assign permissions to roles
locals {
  # Fully qualified, quoted schema identifiers as expected by on_schema grants
  schema_fqn = {
    extract   = "\"${snowflake_database.extract.name}\".\"${snowflake_schema.extract.name}\""
    transform = "\"${snowflake_database.transform.name}\".\"${snowflake_schema.transform.name}\""
    analysis  = "\"${snowflake_database.analysis.name}\".\"${snowflake_schema.analysis.name}\""
  }

  # Warehouse access per role
  warehouse_access = {
    extract_on_extract     = { role = snowflake_role.extract.name, warehouse = snowflake_warehouse.extract.name, privileges = ["USAGE", "OPERATE"] }
    transform_on_transform = { role = snowflake_role.transform.name, warehouse = snowflake_warehouse.transform.name, privileges = ["USAGE", "OPERATE"] }
    load_on_analysis       = { role = snowflake_role.load.name, warehouse = snowflake_warehouse.analysis.name, privileges = ["USAGE"] }
    analyst_on_analysis    = { role = snowflake_role.analyst.name, warehouse = snowflake_warehouse.analysis.name, privileges = ["USAGE"] }
    admin_on_extract       = { role = snowflake_role.admin.name, warehouse = snowflake_warehouse.extract.name, privileges = ["USAGE", "OPERATE"] }
    admin_on_transform     = { role = snowflake_role.admin.name, warehouse = snowflake_warehouse.transform.name, privileges = ["USAGE", "OPERATE"] }
    admin_on_analysis      = { role = snowflake_role.admin.name, warehouse = snowflake_warehouse.analysis.name, privileges = ["USAGE"] }
  }

  # Write access: Fivetran lands raw data in EXTRACT (and creates a schema per
  # connector); dbt builds staging models in TRANSFORM and marts in ANALYSIS.
  write_access = {
    extract_on_extract     = { role = snowflake_role.extract.name, database = snowflake_database.extract.name, schema = local.schema_fqn.extract }
    transform_on_transform = { role = snowflake_role.transform.name, database = snowflake_database.transform.name, schema = local.schema_fqn.transform }
    transform_on_analysis  = { role = snowflake_role.transform.name, database = snowflake_database.analysis.name, schema = local.schema_fqn.analysis }
  }

  # Read access: USAGE on the database and its schemas, SELECT on its tables and
  # views, including ones created later (future grants). All future grants are
  # database-level on purpose, since schema-level future grants would silently
  # override them.
  read_access = {
    transform_on_extract = { role = snowflake_role.transform.name, database = snowflake_database.extract.name }
    load_on_analysis     = { role = snowflake_role.load.name, database = snowflake_database.analysis.name }
    analyst_on_analysis  = { role = snowflake_role.analyst.name, database = snowflake_database.analysis.name }
    admin_on_extract     = { role = snowflake_role.admin.name, database = snowflake_database.extract.name }
    admin_on_transform   = { role = snowflake_role.admin.name, database = snowflake_database.transform.name }
    admin_on_analysis    = { role = snowflake_role.admin.name, database = snowflake_database.analysis.name }
  }
  read_objects = {
    for pair in setproduct(keys(local.read_access), ["TABLES", "VIEWS"]) :
    "${pair[0]}_${lower(pair[1])}" => merge(local.read_access[pair[0]], { object_type_plural = pair[1] })
  }
}

# Warehouses
resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  for_each          = local.warehouse_access
  privileges        = each.value.privileges
  account_role_name = each.value.role
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = each.value.warehouse
  }
}

# Write access
resource "snowflake_grant_privileges_to_account_role" "write_db" {
  for_each          = local.write_access
  privileges        = ["USAGE", "CREATE SCHEMA", "MONITOR"]
  account_role_name = each.value.role
  on_account_object {
    object_type = "DATABASE"
    object_name = each.value.database
  }
}
resource "snowflake_grant_privileges_to_account_role" "write_schema" {
  for_each          = local.write_access
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  account_role_name = each.value.role
  on_schema {
    schema_name = each.value.schema
  }
}

# Read access
resource "snowflake_grant_privileges_to_account_role" "read_db" {
  for_each          = local.read_access
  privileges        = ["USAGE"]
  account_role_name = each.value.role
  on_account_object {
    object_type = "DATABASE"
    object_name = each.value.database
  }
}
resource "snowflake_grant_privileges_to_account_role" "read_schemas_existing" {
  for_each          = local.read_access
  privileges        = ["USAGE"]
  account_role_name = each.value.role
  on_schema {
    all_schemas_in_database = each.value.database
  }
  depends_on = [snowflake_schema.extract, snowflake_schema.transform, snowflake_schema.analysis]
}
resource "snowflake_grant_privileges_to_account_role" "read_schemas_future" {
  for_each          = local.read_access
  privileges        = ["USAGE"]
  account_role_name = each.value.role
  on_schema {
    future_schemas_in_database = each.value.database
  }
}
resource "snowflake_grant_privileges_to_account_role" "read_objects_existing" {
  for_each          = local.read_objects
  privileges        = ["SELECT"]
  account_role_name = each.value.role
  on_schema_object {
    all {
      object_type_plural = each.value.object_type_plural
      in_database        = each.value.database
    }
  }
  depends_on = [snowflake_schema.extract, snowflake_schema.transform, snowflake_schema.analysis]
}
resource "snowflake_grant_privileges_to_account_role" "read_objects_future" {
  for_each          = local.read_objects
  privileges        = ["SELECT"]
  account_role_name = each.value.role
  on_schema_object {
    future {
      object_type_plural = each.value.object_type_plural
      in_database        = each.value.database
    }
  }
}
