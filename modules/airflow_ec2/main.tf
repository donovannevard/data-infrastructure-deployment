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

# AMI: latest Amazon Linux 2023 (standard, not minimal)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# EC2 Instance
resource "random_password" "admin" {
  length           = 20
  special          = true
  override_special = "!#%^*()_+-=" # no quotes, so it can be safely single-quoted in user data
}
resource "random_password" "postgres" {
  length  = 32
  special = false # embedded in a connection URL, so keep it URL-safe
}
resource "aws_instance" "airflow" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.airflow_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.airflow.name

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data_airflow.sh", {
    aws_region        = var.aws_region
    admin_email       = coalesce(var.admin_email, "admin@example.com")
    admin_password    = random_password.admin.result
    postgres_password = random_password.postgres.result
    dag_bucket        = var.aws_s3_bucket_name
  }))
}

# Security Groups
resource "aws_security_group" "airflow_ec2" {
  name   = "${var.aws_prefix}-airflow-ec2-sg"
  vpc_id = var.aws_vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.airflow_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "airflow_alb" {
  name   = "${var.aws_prefix}-airflow-alb-sg"
  vpc_id = var.aws_vpc_id

  ingress {
    description = var.airflow_ec2_enable_https ? "HTTPS, restricted to allowed CIDR" : "HTTP, restricted to allowed CIDR"
    from_port   = var.airflow_ec2_enable_https ? 443 : 80
    to_port     = var.airflow_ec2_enable_https ? 443 : 80
    protocol    = "tcp"
    cidr_blocks = [var.ec2_inbound_cidr_restriction]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB
resource "aws_lb" "airflow" {
  name               = "${var.aws_prefix}-airflow-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.airflow_alb.id]
  subnets            = var.public_subnet_ids
}
resource "aws_lb_target_group" "airflow" {
  name     = "${var.aws_prefix}-airflow-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.aws_vpc_id

  health_check {
    path = "/health"
  }
}
resource "aws_lb_target_group_attachment" "airflow" {
  target_group_arn = aws_lb_target_group.airflow.arn
  target_id        = aws_instance.airflow.id
  port             = 8080
}

# Plain HTTP listener — used when HTTPS is not enabled (default, fastest path: no
# DNS/ACM dependency, access is still restricted to ec2_inbound_cidr_restriction).
resource "aws_lb_listener" "airflow_http" {
  count             = var.airflow_ec2_enable_https ? 0 : 1
  load_balancer_arn = aws_lb.airflow.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow.arn
  }
}

# HTTPS listener — opt-in via airflow_ec2_enable_https. Requires domain_name.
# If airflow_ec2_route53_zone_id is also set, DNS validation is fully automatic.
# Otherwise the certificate is created but stays "pending validation" until the
# CNAME record surfaced in the acm_validation_record output is added manually.
resource "aws_acm_certificate" "airflow" {
  count             = var.airflow_ec2_enable_https ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_route53_record" "cert_validation" {
  count   = var.airflow_ec2_enable_https && var.route53_zone_id != null ? 1 : 0
  zone_id = var.route53_zone_id
  name    = tolist(aws_acm_certificate.airflow[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.airflow[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.airflow[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}
resource "aws_acm_certificate_validation" "airflow" {
  count                   = var.airflow_ec2_enable_https && var.route53_zone_id != null ? 1 : 0
  certificate_arn         = aws_acm_certificate.airflow[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]
}
resource "aws_lb_listener" "airflow_https" {
  count             = var.airflow_ec2_enable_https ? 1 : 0
  load_balancer_arn = aws_lb.airflow.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.airflow[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow.arn
  }
}

# IAM
resource "aws_iam_role" "airflow_ec2" {
  name = "${var.aws_prefix}-airflow-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}
resource "aws_iam_instance_profile" "airflow" {
  name = "${var.aws_prefix}-airflow-ec2-profile"
  role = aws_iam_role.airflow_ec2.name
}
resource "aws_iam_role_policy_attachment" "airflow_ssm" {
  role       = aws_iam_role.airflow_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "airflow_s3_access" {
  name = "${var.aws_prefix}-airflow-s3-policy"
  role = aws_iam_role.airflow_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = var.aws_s3_bucket_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${var.aws_s3_bucket_arn}/*"
      }
    ]
  })
}
resource "aws_iam_role_policy" "airflow_redshift" {
  count = var.warehouse_type == "redshift" ? 1 : 0
  name  = "${var.aws_prefix}-airflow-ec2-redshift"
  role  = aws_iam_role.airflow_ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["redshift-data:ExecuteStatement", "redshift-data:GetStatementResult"]
      Resource = var.redshift_cluster_arn
    }]
  })
}
