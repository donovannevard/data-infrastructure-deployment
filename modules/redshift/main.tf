terraform {
  required_providers {
    redshift = {
      source  = "brainly/redshift"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# The database and the admin (master) user are created with the cluster itself
# in modules/aws, so this module only manages what lives inside it.

# Create schemas
resource "redshift_schema" "extract" {
  name  = var.extract_schema
  owner = var.admin_user_name
}
resource "redshift_schema" "transform" {
  name  = var.transform_schema
  owner = var.admin_user_name
}
resource "redshift_schema" "analysis" {
  name  = var.analysis_schema
  owner = var.admin_user_name
}

# Create service users (Redshift folds identifiers to lowercase, so names are
# lowercase here to avoid perpetual diffs)
resource "random_password" "extract" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()_+-="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}
resource "random_password" "transform" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()_+-="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}
resource "random_password" "load" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()_+-="
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}
resource "redshift_user" "extract" {
  name     = "extract"
  password = random_password.extract.result
}
resource "redshift_user" "transform" {
  name     = "transform"
  password = random_password.transform.result
}
resource "redshift_user" "load" {
  name     = "load"
  password = random_password.load.result
}

# Create groups and assign membership natively (no external psql step required)
resource "redshift_group" "admin" {
  name  = "admin_group"
  users = [var.admin_user_name]
}
resource "redshift_group" "extract" {
  name  = "extract_group"
  users = [redshift_user.extract.name]
}
resource "redshift_group" "transform" {
  name  = "transform_group"
  users = [redshift_user.transform.name]
}
resource "redshift_group" "load" {
  name  = "load_group"
  users = [redshift_user.load.name]
}
resource "redshift_group" "analyst" {
  name = "analyst_group"
}

# Assign permissions to groups
locals {
  # Which service user creates the tables in each schema. Default privileges
  # are keyed on the creating user, so readers get access to future tables.
  schema_writer = {
    (redshift_schema.extract.name)   = redshift_user.extract.name
    (redshift_schema.transform.name) = redshift_user.transform.name
    (redshift_schema.analysis.name)  = redshift_user.transform.name
  }

  # Write access: Fivetran lands raw data in extract; dbt builds staging models
  # in transform and marts in analysis.
  write_access = {
    extract_on_extract     = { group = redshift_group.extract.name, schema = redshift_schema.extract.name }
    transform_on_transform = { group = redshift_group.transform.name, schema = redshift_schema.transform.name }
    transform_on_analysis  = { group = redshift_group.transform.name, schema = redshift_schema.analysis.name }
  }

  # Read access: USAGE on the schema plus SELECT on its existing and future tables.
  #
  # `wave` orders the default-privilege grants: Redshift keeps one row per
  # (table owner, schema), and concurrent grants to different groups on the same
  # row fail with a unique-constraint error. Entries sharing an owner + schema
  # therefore need distinct waves (enforced by the precondition below).
  read_access = {
    transform_on_extract = { group = redshift_group.transform.name, schema = redshift_schema.extract.name, wave = 0 }
    admin_on_extract     = { group = redshift_group.admin.name, schema = redshift_schema.extract.name, wave = 1 }
    admin_on_transform   = { group = redshift_group.admin.name, schema = redshift_schema.transform.name, wave = 0 }
    admin_on_analysis    = { group = redshift_group.admin.name, schema = redshift_schema.analysis.name, wave = 0 }
    load_on_analysis     = { group = redshift_group.load.name, schema = redshift_schema.analysis.name, wave = 1 }
    analyst_on_analysis  = { group = redshift_group.analyst.name, schema = redshift_schema.analysis.name, wave = 2 }
  }

  # "owner/schema/wave" must be unique across read_access
  default_privilege_slots = [for k, v in local.read_access : "${local.schema_writer[v.schema]}/${v.schema}/${v.wave}"]
}

# Fivetran creates a schema per connector, and dbt may create custom schemas
resource "redshift_grant" "database" {
  for_each    = toset([redshift_group.extract.name, redshift_group.transform.name])
  group       = each.key
  object_type = "database"
  privileges  = ["CREATE", "TEMPORARY"]
}

resource "redshift_grant" "write_schema" {
  for_each    = local.write_access
  group       = each.value.group
  schema      = each.value.schema
  object_type = "schema"
  privileges  = ["CREATE", "USAGE"]
}

resource "redshift_grant" "read_schema" {
  for_each    = local.read_access
  group       = each.value.group
  schema      = each.value.schema
  object_type = "schema"
  privileges  = ["USAGE"]
}
resource "redshift_grant" "read_tables" {
  for_each    = local.read_access
  group       = each.value.group
  schema      = each.value.schema
  object_type = "table"
  objects     = [] # all existing tables in the schema
  privileges  = ["SELECT"]
}
resource "redshift_default_privileges" "read_tables" {
  for_each    = { for k, v in local.read_access : k => v if v.wave == 0 }
  group       = each.value.group
  schema      = each.value.schema
  owner       = local.schema_writer[each.value.schema]
  object_type = "table"
  privileges  = ["SELECT"]

  # The owner needs its schema privileges before default privileges can be
  # set for it in that schema ("permission denied for schema" otherwise).
  depends_on = [redshift_grant.write_schema]

  lifecycle {
    precondition {
      condition     = length(distinct(local.default_privilege_slots)) == length(local.default_privilege_slots)
      error_message = "Two read_access entries share a table owner, schema and wave; give them different waves."
    }
  }
}
resource "redshift_default_privileges" "read_tables_wave1" {
  for_each    = { for k, v in local.read_access : k => v if v.wave == 1 }
  group       = each.value.group
  schema      = each.value.schema
  owner       = local.schema_writer[each.value.schema]
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [redshift_default_privileges.read_tables]
}
resource "redshift_default_privileges" "read_tables_wave2" {
  for_each    = { for k, v in local.read_access : k => v if v.wave == 2 }
  group       = each.value.group
  schema      = each.value.schema
  owner       = local.schema_writer[each.value.schema]
  object_type = "table"
  privileges  = ["SELECT"]

  depends_on = [redshift_default_privileges.read_tables_wave1]
}
