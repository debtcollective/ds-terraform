/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
}

variable "image_name" {
  description = "Docker image for ECS task"
  default     = "debtcollective/dispute-tools:latest"
}

variable "subnet_ids" {
  description = "VPC Subnet IDs to be used in the Launch Configuration for the instances running in this cluster"
  type        = "list"
}

variable "vpc_id" {
  description = "VPC Id to be used by the LB"
}

variable "ec2_security_groups" {
  description = "VPC Security Groups IDs to be used by the instance"
}

variable "elb_security_groups" {
  description = "VPC Security Groups IDs to be used by the load balancer"
}

variable "ecs_instance_role" {
  description = "iam role to be used for ecs"
}

variable "ecs_instance_profile" {
  description = "iam profile to be used for ecs"
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

variable "discourse_base_url" {
  description = "Discourse instance base url"
}

variable "discourse_api_key" {
  description = "Discourse API key"
}

variable "discourse_api_username" {
  description = "Discourse API username to go with key"
}

variable "doe_disclosure_representatives" {}
variable "doe_disclosure_phones" {}
variable "doe_disclosure_relationship" {}
variable "doe_disclosure_address" {}
variable "doe_disclosure_city" {}
variable "doe_disclosure_state" {}
variable "doe_disclosure_zip" {}

variable "site_url" {
  description = "URL where the application is hosted"
}

variable "sentry_endpoint" {
  description = "Sentry DNS for error reporting"
}

variable "static_assets_bucket_url" {
  description = "Debtcollective static assets bucket url"
  default     = "https://s3.amazonaws.com/tds-static"
}

variable "log_retention_in_days" {
  description = "Cloudwatch logs retention"
  default     = 3
}

variable "acm_certificate_domain" {
  description = "ACM certificate domain name to be used for SSL"
  default     = "*.debtsyndicate.org"
}

variable "key_name" {
  description = "SSH Key Pair to be assigned to the Launch Configuration for the instances running in this cluster"
}

variable "instance_type" {
  description = "Instace type Launch Configuration for the instances running in this cluster"
  default     = "t2.micro"
}

variable "asg_min_size" {
  description = "Auto Scaling Group minimium size for the cluster"
  default     = 1
}

variable "asg_max_size" {
  description = "Auto Scaling Group maximum size for the cluster"
  default     = 1
}

// S3 Bucket and permissions
resource "aws_s3_bucket" "disputes" {
  bucket        = "dispute-tools-uploads-${var.environment}"
  acl           = "private"
  force_destroy = true

  tags {
    Terraform   = true
    Name        = "Staging bucket"
    Environment = "${var.environment}"
  }
}

resource "aws_iam_user" "disputes_uploader" {
  name = "disputes-uploader-${var.environment}"
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
  name = "disputes-uploader-policy-${var.environment}"
  user = "${aws_iam_user.disputes_uploader.name}"

  policy = "${data.template_file.disputes_uploader_policy_document.rendered}"
}

// Load balancer
data "aws_acm_certificate" "domain" {
  domain   = "${var.acm_certificate_domain}"
  statuses = ["ISSUED"]
}

resource "aws_lb" "lb_dispute_tools" {
  name            = "tools-lb-${var.environment}"
  security_groups = ["${var.elb_security_groups}"]
  subnets         = ["${var.subnet_ids}"]
}

resource "aws_lb_target_group" "dispute_tools" {
  name_prefix = "tools-"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${var.vpc_id}"

  health_check {
    path = "/health-check"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "dispute_tools_http" {
  load_balancer_arn = "${aws_lb.lb_dispute_tools.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.dispute_tools.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "dispute_tools_https" {
  load_balancer_arn = "${aws_lb.lb_dispute_tools.id}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "${data.aws_acm_certificate.domain.arn}"
  ssl_policy        = "ELBSecurityPolicy-2015-05"

  default_action {
    target_group_arn = "${aws_lb_target_group.dispute_tools.arn}"
    type             = "forward"
  }
}

// ECS service and task
resource "aws_ecs_service" "dispute_tools" {
  name            = "dispute_tools"
  cluster         = "${aws_ecs_cluster.dispute_tools.id}"
  task_definition = "${aws_ecs_task_definition.dispute_tools.arn}"
  desired_count   = 1
  iam_role        = "${var.ecs_instance_role}"

  load_balancer {
    target_group_arn = "${aws_lb_target_group.dispute_tools.arn}"
    container_name   = "dispute_tools_${var.environment}"
    container_port   = "8080"
  }
}

resource "aws_ecs_cluster" "dispute_tools" {
  name = "dispute_tools_${var.environment}"
}

module "dispute_tools_lc" {
  source      = "../../../utils/launch_configuration"
  environment = "${var.environment}"

  cluster_name            = "${aws_ecs_cluster.dispute_tools.name}"
  key_name                = "${var.key_name}"
  iam_instance_profile_id = "${var.ecs_instance_profile}"
  security_groups         = ["${var.ec2_security_groups}"]
  instance_type           = "${var.instance_type}"
}

resource "aws_autoscaling_group" "dispute_tools_asg" {
  launch_configuration = "${module.dispute_tools_lc.id}"
  min_size             = "${var.asg_min_size}"
  max_size             = "${var.asg_max_size}"
  health_check_type    = "ELB"
  vpc_zone_identifier  = ["${var.subnet_ids}"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "dispute_tools_lg" {
  name              = "${aws_ecs_cluster.dispute_tools.name}_lg"
  retention_in_days = "${var.log_retention_in_days}"
}

data "template_file" "container_definitions" {
  template = "${file("${path.module}/container-definitions.json")}"

  vars {
    container_name = "dispute_tools_${var.environment}"
    environment    = "${var.environment}"
    image_name     = "${var.image_name}"
    sso_endpoint   = "${var.sso_endpoint}"
    sso_secret     = "${var.sso_secret}"
    jwt_secret     = "${var.jwt_secret}"
    cookie_name    = "${var.cookie_name}"
    site_url       = "${var.site_url}"

    doe_disclosure_representatives = "${var.doe_disclosure_representatives}"
    doe_disclosure_phones          = "${var.doe_disclosure_phones}"
    doe_disclosure_relationship    = "${var.doe_disclosure_relationship}"
    doe_disclosure_address         = "${var.doe_disclosure_address}"
    doe_disclosure_city            = "${var.doe_disclosure_city}"
    doe_disclosure_state           = "${var.doe_disclosure_state}"
    doe_disclosure_zip             = "${var.doe_disclosure_zip}"

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
    aws_bucket_name   = "dispute-tools-uploads-${var.environment}"

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

    discourse_api_key      = "${var.discourse_api_key}"
    discourse_api_username = "${var.discourse_api_username}"
    discourse_base_url     = "${var.discourse_base_url}"

    sentry_endpoint = "${var.sentry_endpoint}"

    static_assets_bucket_url = "${var.static_assets_bucket_url}"

    log_group = "${aws_ecs_cluster.dispute_tools.name}_lg"
  }
}

data "aws_iam_role" "exec_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "dispute_tools" {
  family                = "dispute_tools"
  execution_role_arn    = "${data.aws_iam_role.exec_role.arn}"
  container_definitions = "${data.template_file.container_definitions.rendered}"
}

/*
 * Outputs
 */
output "lb_dns_name" {
  value = "${aws_lb.lb_dispute_tools.dns_name}"
}

output "lb_zone_id" {
  value = "${aws_lb.lb_dispute_tools.zone_id}"
}
