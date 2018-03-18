/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
}

variable "subnets" {
  type        = "list"
  description = "VPC Subnet ids"
}

variable "subnet_id" {
  description = "VPC Subnet ID to be used in by the instance"
}

variable "vpc_id" {
  description = "VPC Id to be used by the ALB"
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

data "template_file" "disputes_uploader_policy_document" {
  template = "${file("${path.module}/bucket-policy.json")}"

  vars {
    resource_arn = "${aws_s3_bucket.disputes.arn}"
  }
}

resource "aws_iam_user_policy" "disputes_uploader_policy" {
  name = "tds-disputes_uploader__policy-${var.environment}"
  user = "${aws_iam_user.disputes_uploader.name}"

  policy = "${data.template_file.disputes_uploader_policy_document.rendered}"
}

data "aws_acm_certificate" "debtcollective" {
  domain   = "*.debtcollective.org"
  statuses = ["ISSUED"]
}

resource "aws_alb_target_group" "dispute_tools" {
  name        = "${var.environment}-alb-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${var.vpc_id}"
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web_inbound_sg" {
  name        = "${var.environment}-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.environment}-web-inbound-sg"
  }
}

resource "aws_alb" "alb_dispute_tools" {
  name    = "${var.environment}-alb-dispute-tools"
  subnets = ["${var.subnets}"]
}

resource "aws_alb_listener" "dispute_tools" {
  load_balancer_arn = "${aws_alb.alb_dispute_tools.arn}"
  port              = "443"
  protocol          = "HTTPS"
  depends_on        = ["aws_alb_target_group.dispute_tools"]

  certificate_arn = "${data.aws_acm_certificate.debtcollective.arn}"
  ssl_policy      = "ELBSecurityPolicy-2015-05"

  default_action {
    target_group_arn = "${aws_alb_target_group.dispute_tools.arn}"
    type             = "forward"
  }
}

resource "aws_ecr_repository" "dispute_tools" {
  name = "ds-dispute-tools-${var.environment}"
}

resource "aws_ecs_service" "dispute_tools" {
  name            = "dispute_tools"
  cluster         = "${aws_ecs_cluster.dispute_tools.id}"
  task_definition = "${aws_ecs_task_definition.dispute_tools.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = ["${var.subnets}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.dispute_tools.arn}"
    container_name   = "tds-dispute-tools"
    container_port   = "80"
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

    smtp_host   = "${var.smtp_host}"
    smtp_port   = "${var.smtp_port}"
    smtp_user   = "${var.smtp_user}"
    smtp_pass   = "${var.smtp_pass}"
    smtp_secure = "${var.smtp_secure}"

    aws_access_id     = "${aws_iam_access_key.disputes_uploader.id}"
    aws_access_secret = "${aws_iam_access_key.disputes_uploader.secret}"
    aws_region        = "${aws_s3_bucket.disputes.region}"

    loggly_api_key = "${var.loggly_api_key}"

    stripe_private     = "${var.stripe_private}"
    stripe_publishable = "${var.stripe_publishable}"

    google_maps_api_key = "${var.google_maps_api_key}"

    db_connection_string = "${var.db_connection_string}"
    db_pool_min          = "${var.db_pool_min}"
    db_pool_max          = "${var.db_pool_max}"

    access_key_id     = "${aws_iam_access_key.disputes_uploader.id}"
    secret_access_key = "${aws_iam_access_key.disputes_uploader.secret}"
    bucket_region     = "${aws_s3_bucket.disputes.region}"

    repository_url = "${aws_ecr_repository.dispute_tools.repository_url}"
  }
}

data "aws_iam_role" "exec_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "dispute_tools" {
  family                = "dispute_tools"
  execution_role_arn    = "${data.aws_iam_role.exec_role.arn}"
  container_definitions = "${data.template_file.container_definitions.rendered}"

  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  requires_compatibilities = ["FARGATE"]
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
    name                   = "${aws_alb.alb_dispute_tools.dns_name}"
    zone_id                = "${aws_alb.alb_dispute_tools.zone_id}"
    evaluate_target_health = true
  }
}
