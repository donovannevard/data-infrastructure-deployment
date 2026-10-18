output "warehouses" {
  value = {
    extract   = snowflake_warehouse.extract.name
    transform = snowflake_warehouse.transform.name
    analysis  = snowflake_warehouse.analysis.name
  }
}

output "databases" {
  value = {
    extract   = snowflake_database.extract.name
    transform = snowflake_database.transform.name
    analysis  = snowflake_database.analysis.name
  }
}

output "roles" {
  value = {
    extract   = snowflake_role.extract.name
    transform = snowflake_role.transform.name
    load      = snowflake_role.load.name
    analyst   = snowflake_role.analyst.name
    admin     = snowflake_role.admin.name
  }
}

output "service_users" {
  value = {
    admin = {
      name     = snowflake_user.admin.name
      password = random_password.admin.result
    }
    extract = {
      name     = snowflake_user.extract.name
      password = random_password.extract.result
    }
    transform = {
      name     = snowflake_user.transform.name
      password = random_password.transform.result
    }
    load = {
      name     = snowflake_user.load.name
      password = random_password.load.result
    }
  }
  sensitive = true
}
