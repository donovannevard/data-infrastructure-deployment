terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.79"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  environment_name = "${var.aws_prefix}-airflow"
}

# IAM Role + minimal policies
resource "aws_iam_role" "mwaa_execution" {
  name = "${var.aws_prefix}-mwaa-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = ["airflow.amazonaws.com", "airflow-env.amazonaws.com"]
      }
    }]
  })
}
# Execution role permissions, per the AWS-documented MWAA execution policy
resource "aws_iam_role_policy" "mwaa_execution" {
  name = "${var.aws_prefix}-mwaa-execution"
  role = aws_iam_role.mwaa_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "airflow:PublishMetrics"
        Resource = "arn:aws:airflow:*:*:environment/${local.environment_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject*", "s3:GetBucket*", "s3:List*"]
        Resource = [var.aws_s3_bucket_arn, "${var.aws_s3_bucket_arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream", "logs:CreateLogGroup", "logs:PutLogEvents",
          "logs:GetLogEvents", "logs:GetLogRecord", "logs:GetLogGroupFields",
          "logs:GetQueryResults",
        ]
        Resource = "arn:aws:logs:*:*:log-group:airflow-${local.environment_name}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups", "cloudwatch:PutMetricData", "s3:GetAccountPublicAccessBlock"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl", "sqs:ReceiveMessage", "sqs:SendMessage",
        ]
        Resource = "arn:aws:sqs:*:*:airflow-celery-*"
      },
      {
        Effect      = "Allow"
        Action      = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:Encrypt"]
        NotResource = "arn:aws:kms:*:*:key/*"
        Condition = {
          StringLike = { "kms:ViaService" = ["sqs.*.amazonaws.com"] }
        }
      },
    ]
  })
}
resource "aws_iam_role_policy" "mwaa_redshift" {
  count = var.warehouse_type == "redshift" ? 1 : 0
  name  = "${var.aws_prefix}-mwaa-redshift"
  role  = aws_iam_role.mwaa_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["redshift-data:ExecuteStatement", "redshift-data:GetStatementResult"]
      Resource = var.redshift_cluster_arn
    }]
  })
}
resource "aws_iam_policy" "mwaa_ui_access" {
  name = "${var.aws_prefix}-mwaa-ui-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "airflow:CreateWebLoginToken",
          "airflow:GetEnvironment"
        ]
        Resource = aws_mwaa_environment.main.arn
      }
    ]
  })
}

# Security Group
resource "aws_security_group" "mwaa" {
  name   = "${var.aws_prefix}-mwaa-sg"
  vpc_id = var.aws_vpc_id

  # Required by MWAA: its scheduler, workers, web server and metadata database
  # all share this group and must be able to reach each other.
  ingress {
    description = "MWAA components (self-referencing)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Airflow UI (VPC only)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.aws_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# MWAA Environment
resource "aws_mwaa_environment" "main" {
  name               = local.environment_name
  execution_role_arn = aws_iam_role.mwaa_execution.arn

  dag_s3_path       = "dags"
  source_bucket_arn = var.aws_s3_bucket_arn

  airflow_configuration_options = {
    "core.max_active_tasks_per_dag" = var.mwaa_dag_concurrency
    "core.parallelism"              = var.mwaa_parallelism
    "core.max_active_runs_per_dag"  = var.mwaa_max_runs_per_dag
    "core.load_examples"            = "false"
  }

  environment_class     = var.mwaa_environment
  webserver_access_mode = var.webserver_access_mode
  max_workers           = var.mwaa_max_workers

  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = slice(var.private_subnet_ids, 0, 2) # MWAA requires exactly two
  }

  depends_on = [aws_iam_role_policy.mwaa_execution]
}
