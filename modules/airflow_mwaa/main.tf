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

data "aws_caller_identity" "current" {}

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
        # MWAA's queues are encrypted with an AWS-owned key, which lives in an
        # AWS service account: "any key except this account's own", as in the
        # AWS-documented policy (a wildcard account here would allow nothing)
        Effect      = "Allow"
        Action      = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:Encrypt"]
        NotResource = "arn:aws:kms:*:${data.aws_caller_identity.current.account_id}:key/*"
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

# CloudWatch log groups, created up front so they get a retention period and are
# removed on destroy. MWAA reuses existing groups with these names; left to
# itself it creates them with no expiry, and they outlive the environment.
resource "aws_cloudwatch_log_group" "mwaa" {
  for_each          = var.log_retention_days == null ? toset([]) : toset(["DAGProcessing", "Scheduler", "Task", "WebServer", "Worker"])
  name              = "airflow-${local.environment_name}-${each.key}"
  retention_in_days = var.log_retention_days
}

# MWAA Environment
resource "aws_mwaa_environment" "main" {
  name               = local.environment_name
  execution_role_arn = aws_iam_role.mwaa_execution.arn

  dag_s3_path       = "dags"
  source_bucket_arn = var.aws_s3_bucket_arn

  # Optional extra Python packages and plugins, from the same bucket (pinned to
  # an object version, so MWAA only restarts when their content changes)
  requirements_s3_path           = var.requirements_s3_path
  requirements_s3_object_version = var.requirements_s3_object_version
  plugins_s3_path                = var.plugins_s3_path
  plugins_s3_object_version      = var.plugins_s3_object_version

  airflow_configuration_options = {
    "core.max_active_tasks_per_dag" = var.mwaa_dag_concurrency
    "core.parallelism"              = var.mwaa_parallelism
    "core.max_active_runs_per_dag"  = var.mwaa_max_runs_per_dag
    "core.load_examples"            = "false"
  }

  # Warnings and errors from every component, plus full task logs, in
  # CloudWatch: without scheduler/worker logs, a task that fails to start
  # leaves no trace at all.
  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "WARNING"
    }
    scheduler_logs {
      enabled   = true
      log_level = "WARNING"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "WARNING"
    }
    worker_logs {
      enabled   = true
      log_level = "WARNING"
    }
  }

  environment_class     = var.mwaa_environment
  webserver_access_mode = var.webserver_access_mode
  max_workers           = var.mwaa_max_workers

  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = slice(var.private_subnet_ids, 0, 2) # MWAA requires exactly two
  }

  depends_on = [aws_iam_role_policy.mwaa_execution, aws_cloudwatch_log_group.mwaa]
}
