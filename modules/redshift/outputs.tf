output "schemas" {
  value = {
    extract   = redshift_schema.extract.name
    transform = redshift_schema.transform.name
    analysis  = redshift_schema.analysis.name
  }
}

output "user_groups" {
  value = {
    admin     = redshift_group.admin.name
    extract   = redshift_group.extract.name
    transform = redshift_group.transform.name
    load      = redshift_group.load.name
    analyst   = redshift_group.analyst.name
  }
}

output "service_users" {
  value = {
    extract = {
      name     = redshift_user.extract.name
      password = random_password.extract.result
    }
    transform = {
      name     = redshift_user.transform.name
      password = random_password.transform.result
    }
    load = {
      name     = redshift_user.load.name
      password = random_password.load.result
    }
  }
  sensitive = true
}
