output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "aws_s3_bucket" {
  value = {
    airflow = aws_s3_bucket.airflow
  }
}

output "redshift" {
  value = length(aws_redshift_cluster.main) > 0 ? {
    host     = aws_redshift_cluster.main[0].dns_name # `endpoint` would include ":5439"
    arn      = aws_redshift_cluster.main[0].arn
    port     = 5439
    database = aws_redshift_cluster.main[0].database_name
    username = var.admin_user_name
    password = random_password.admin.result
  } : null
  sensitive = true
}

output "final_snapshot_notice" {
  description = "Present when a final snapshot will be kept on destroy (used by tests)"
  value       = terraform_data.final_snapshot_notice[*].id
}
