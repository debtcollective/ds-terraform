/**
 *Metabase module creates a ECS Cluster with ECS Service and Task for the metabase image.
 *The cluster is created inside a VPC.
 *
 *This module creates all the necessary pieces that are needed to run a cluster, including:
 *
 ** Auto Scaling Groups
 ** EC2 Launch Configurations
 ** Application load balancer (ELB)
 *
 *## Usage:
 *
 *```hcl
 *module "metabase" {
 *  source      = "../services/metabase"
 *  environment = "${var.environment}"
 *  image       = "${var.image}"
 *
 *  db_username = "${var.db_username}"
 *  db_password = "${var.db_password}"
 *  db_host     = "${var.db_host}"
 *  db_port     = "${var.db_port}"
 *  db_name     = "${var.metabase_db_name}"
 *
 *  key_name                = "${var.key_name}"
 *  iam_instance_profile_id = "${var.iam_instance_profile_id}"
 *  subnet_ids              = ["${var.subnet_ids}"]
 *  security_groups         = ["${var.security_groups}"]
 *  asg_min_size            = "${var.asg_min_size}"
 *  asg_max_size            = "${var.asg_max_size}"
 *}
 *```
/*
 * Variables
 */

variable "environment" {
  description = "Environment name"
}

variable "image" {
  description = "Docker image name"
  default     = "metabase/metabase:latest"
}

variable "db_host" {
  description = "Database Host URL"
}

variable "db_username" {
  description = "Database Username"
}

variable "db_password" {
  description = "Database Password"
}

variable "db_port" {
  description = "Database Port"
  default     = "5432"
}

variable "db_name" {
  description = "Database name"
  default     = "metabase"
}

variable "key_name" {
  description = "SSH Key Pair to be assigned to the Launch Configuration for the instances running in this cluster"
}

variable "iam_instance_profile_id" {
  description = "IAM Profile ID to be used in the Launch Configuration for the instances running in this cluster"
}

variable "subnet_ids" {
  description = "VPC Subnet IDs to be used in the Launch Configuration for the instances running in this cluster"
  type        = "list"
}

variable "security_groups" {
  description = "VPC Security Groups IDs to be used in the Launch Configuration for the instances running in this cluster"
  type        = "list"
}

variable "asg_min_size" {
  description = "Auto Scaling Group minimium size for the cluster"
  default     = 1
}

variable "asg_max_size" {
  description = "Auto Scaling Group maximum size for the cluster"
  default     = 1
}

variable "desired_count" {
  description = "Number of instances to be run"
  default     = 1
}

variable "acm_certificate_domain" {
  description = "ACM certificate domain name to be used for SSL"
  default     = "*.debtcollective.org"
}

variable "vpc_id" {
  description = "VPC Id to be used by the LB"
}

variable "elb_security_groups" {
  description = "VPC Security Groups IDs to be used by the load balancer"
}

/*
 * Resources
 */
locals {
  container_name = "metabase"
  name_prefix    = "mb-${substr(var.environment, 0, 2)}-"
}

// Load balancer
data "aws_acm_certificate" "domain" {
  domain   = "${var.acm_certificate_domain}"
  statuses = ["ISSUED"]
}

resource "aws_lb" "metabase" {
  name_prefix     = "${local.name_prefix}"
  security_groups = ["${var.elb_security_groups}"]
  subnets         = ["${var.subnet_ids}"]
}

resource "aws_lb_target_group" "metabase" {
  name_prefix = "${local.name_prefix}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${var.vpc_id}"

  health_check {
    path = "/api/health"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "metabase_http" {
  load_balancer_arn = "${aws_lb.metabase.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.metabase.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "metabase_https" {
  load_balancer_arn = "${aws_lb.metabase.id}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "${data.aws_acm_certificate.domain.arn}"
  ssl_policy        = "ELBSecurityPolicy-2015-05"

  default_action {
    target_group_arn = "${aws_lb_target_group.metabase.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "redirect_http_to_https" {
  listener_arn = "${aws_lb_listener.metabase_http.arn}"

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    field  = "host-header"
    values = ["${var.acm_certificate_domain}"]
  }
}

data "template_file" "metabase" {
  template = "${file("${path.module}/container-definitions.json")}"

  vars {
    container_name = "${local.container_name}"
    image          = "${var.image}"

    db_username = "${var.db_username}"
    db_password = "${var.db_password}"
    db_host     = "${var.db_host}"
    db_port     = "${var.db_port}"
    db_name     = "${var.db_name}"
  }
}

module "metabase_lc" {
  source      = "../../../utils/launch_configuration"
  environment = "${var.environment}"

  cluster_name            = "${aws_ecs_cluster.metabase.name}"
  key_name                = "${var.key_name}"
  iam_instance_profile_id = "${var.iam_instance_profile_id}"
  security_groups         = ["${var.security_groups}"]
}

resource "aws_autoscaling_group" "metabase_asg" {
  launch_configuration = "${module.metabase_lc.id}"
  min_size             = "${var.asg_min_size}"
  max_size             = "${var.asg_max_size}"
  health_check_type    = "ELB"
  vpc_zone_identifier  = ["${var.subnet_ids}"]
}

// Create a cluster for Metabase
resource "aws_ecs_cluster" "metabase" {
  name = "metabase-c-${var.environment}"
}

// Create a task definition for Metabase
resource "aws_ecs_task_definition" "metabase" {
  family                = "metabase-${var.environment}"
  container_definitions = "${data.template_file.metabase.rendered}"
}

// ECS service and task
resource "aws_ecs_service" "metabase" {
  name            = "metabase-${var.environment}"
  cluster         = "${aws_ecs_cluster.metabase.id}"
  task_definition = "${aws_ecs_task_definition.metabase.arn}"
  desired_count   = "${var.desired_count}"

  load_balancer {
    target_group_arn = "${aws_lb_target_group.metabase.arn}"
    container_name   = "${local.container_name}"
    container_port   = "3000"
  }
}

/*
 * Outputs
 */

// ECS Service name
output "service_name" {
  value = "${aws_ecs_service.metabase.name}"
}

// ELB dns_name
output "dns_name" {
  value = "${aws_lb.metabase.dns_name}"
}

// ELB zone_id
output "zone_id" {
  value = "${aws_lb.metabase.zone_id}"
}
