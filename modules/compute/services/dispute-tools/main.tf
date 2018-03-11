/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
}

variable "subnet_id" {
  description = "VPC Subnet ID to be used in by the instance"
}

variable "security_groups" {
  description = "VPC Security Groups IDs to be used by the instance"
}

variable "sso_endpoint" {
  description = "SSO authentication endpoint"
}

variable "sso_secret" {
  description = "Shared secret for SSO"
}

variable "jwt_secret" {
  description = "Unshared secret for JWT encoding"
}

variable "cookie_name" {
  description = "Name of session cookie"
}

variable "contact_email" {
  description = "Administrator contact email"
}

variable "sender_email" {
  description = "The FROM address for sending emails"
}

variable "disputes_bcc_address" {
  description = "Address to bcc for all dispute emails"
}

variable "smtp_host" {
  description = "SMTP host"
}

variable "smtp_port" {
  description = "SMTP port"
}

variable "smtp_secure" {
  description = "Whether SMTP should use SSL"
  default     = true
}

variable "smtp_user" {
  description = "SMTP user"
}

variable "smtp_pass" {
  description = "SMTP password"
}

variable "loggly_api_key" {
  description = "Loggly API key"
}

variable "stripe_private" {
  description = "Stripe private key"
}

variable "stripe_publishable" {
  description = "Stripe shared key"
}

variable "google_maps_api_key" {
  description = "Google maps API key"
}

variable "db_connection_string" {
  description = "Connection string to DB instance"
}

variable "db_pool_min" {
  description = "Databse pool minimum"
  default     = 5
}

variable "db_pool_max" {
  description = "Database pool maximum"
  default     = 30
}

resource "aws_s3_bucket" "disputes" {
  bucket = "tds-tools-${var.environment}"
  acl    = "private"

  tags {
    Terraform   = true
    Name        = "Staging bucket"
    Environment = "${var.environment}"
  }
}

resource "aws_iam_user" "disputes_uploader" {
  name = "tds-disputes_uploader-${var.environment}"
}

resource "aws_iam_access_key" "disputes_uploader" {
  user = "${aws_iam_user.disputes_uploader.name}"
}

resource "aws_iam_user_policy" "disputes_uploader_policy" {
  name = "tds-disputes_uploader__policy-${var.environment}"
  user = "${aws_iam_user.disputes_uploader.name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:PutObjectAcl"
          ],
          "Resource": "${aws_s3_bucket.disputes.arn}"
        }
      ]
    }
  ]
}
POLICY
}

data "aws_acm_certificate" "debtcollective" {
  domain   = "*.debtcollective.org"
  statuses = ["ISSUED"]
}

resource "aws_elb" "dispute_tools" {
  name               = "disputetools${var.environment}elb"
  availability_zones = ["us-west-2a", "us-east-2b"]

  listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${data.aws_acm_certificate.debtcollective.arn}"
  }

  tags {
    Terraform = true
    Name      = "dispute_tools_${var.environment}_elb"
  }
}

resource "aws_ecs_service" "dispute_tools" {
  name            = "dispute_tools"
  cluster         = "${aws_ecs_cluster.dispute_tools.id}"
  task_definition = "${aws_ecs_task_definition.dispute_tools.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    elb_name       = "${aws_elb.dispute_tools.name}"
    container_name = "tds-dispute-tools"
    container_port = 8080
  }
}

resource "aws_ecs_cluster" "dispute_tools" {
  name = "dispute_tools"
}

data "template_file" "container_definitions" {
  template = "${file("${path.module}/container-definitions.json")}"

  vars {
    environment  = "${var.environment}"
    sso_endpoint = "${var.sso_endpoint}"
    sso_secret   = "${var.sso_secret}"
    jwt_secret   = "${var.jwt_secret}"
    cookie_name  = "${var.cookie_name}"

    contact_email        = "${var.contact_email}"
    sender_email         = "${var.sender_email}"
    disputes_bcc_address = "${var.disputes_bcc_address}"

    smtp_host = "${var.smtp_host}"
    smtp_port = "${var.smtp_port}"
    smtp_user = "${var.smtp_user}"
    smtp_pass = "${var.smtp_pass}"

    loggly_api_key = "${var.loggly_api_key}"

    stripe_private     = "${var.stripe_private}"
    stripe_publishable = "${var.stripe_publishable}"

    google_maps_api_key = "${var.google_maps_api_key}"

    db_connection_string = "${var.db_connection_string}"
    db_pool_min          = "${var.db_pool_min}"
    db_pool_max          = "${var.db_pool_max}"
  }
}

resource "aws_ecs_task_definition" "dispute_tools" {
  family = "dispute_tools"

  container_definitions = "${data.template_file.container_definitions.rendered}"
}

resource "aws_eip" "disputes" {
  vpc = true
}

data "aws_route53_zone" "primary" {
  name = "debtcollective.org."
}

resource "aws_route53_record" "dispute-tools" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "tools-staging.debtcollective.org"
  type    = "A"

  alias {
    name                   = "${aws_elb.dispute_tools.dns_name}"
    zone_id                = "${aws_elb.dispute_tools.zone_id}"
    evaluate_target_health = true
  }
}
