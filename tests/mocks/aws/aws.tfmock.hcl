# Shared AWS mock data for `terraform test` in snowflake/ and redshift/.
# The AWS provider validates ARN formats even when mocked, so give the
# resources whose ARNs are passed to other resources realistic values.

mock_resource "aws_iam_role" {
  defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
}
mock_resource "aws_s3_bucket" {
  defaults = { arn = "arn:aws:s3:::mock-bucket" }
}
mock_resource "aws_redshift_cluster" {
  defaults = { arn = "arn:aws:redshift:eu-west-2:123456789012:cluster:mock" }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/mock/0123456789abcdef" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/mock/0123456789abcdef" }
}
mock_resource "aws_acm_certificate" {
  defaults = { arn = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000" }
}
