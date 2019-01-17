/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
}

variable "image_name" {
  description = "Docker image for ECS task"
  default     = "debtcollective/wordpress:latest"
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

variable "acm_certificate_domain" {
  description = "ACM certificate domain name to be used for SSL"
  default     = "*.debtcollective.org"
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

variable "db_host" {
  description = "Wordpress Datbase host"
}

variable "db_user" {
  description = "Wordpress Database user"
}

variable "db_password" {
  description = "Wordpress Database password"
}

variable "db_name" {
  description = "Wordpress Database name"
}

variable "auth_key" {
  description = "Wordpress Auth key"
}

variable "secure_auth_key" {
  description = "Wordpress Secure Auth key"
}

variable "logged_in_key" {
  description = "Wordpress Logged in key"
}

variable "nonce_key" {
  description = "Wordpress Nonce key"
}

variable "auth_salt" {
  description = "Wordpress Auth Salt"
}

variable "secure_auth_salt" {
  description = "Wordpress Secure Auth Salt"
}

variable "logged_in_salt" {
  description = "Wordpress Logged in Salt"
}

variable "nonce_salt" {
  description = "Wordpress Nonce salt"
}

variable "smtp_host" {
  description = "Wordpress SMTP host"
}

variable "smtp_port" {
  description = "Wordpress SMTP port"
}

variable "smtp_username" {
  description = "Wordpress SMTP username"
}

variable "smtp_password" {
  description = "Wordpress SMTP password"
}

variable "smtp_from" {
  description = "Wordpress SMTP from"
}

variable "smtp_from_name" {
  description = "Wordpress SMTP from name"
}

// Load balancer
data "aws_acm_certificate" "debtcollective" {
  domain   = "${var.acm_certificate_domain}"
  statuses = ["ISSUED"]
}

resource "aws_lb" "wordpress" {
  name            = "wordpress-lb-${var.environment}"
  security_groups = ["${var.elb_security_groups}"]
  subnets         = ["${var.subnet_ids}"]
}

resource "aws_lb_target_group" "wordpress" {
  name_prefix = "wp-"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${var.vpc_id}"

  health_check {
    matcher = "200-399"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "wordpress_http" {
  load_balancer_arn = "${aws_lb.wordpress.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.wordpress.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "wordpress_https" {
  load_balancer_arn = "${aws_lb.wordpress.id}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "${data.aws_acm_certificate.debtcollective.arn}"
  ssl_policy        = "ELBSecurityPolicy-2015-05"

  default_action {
    target_group_arn = "${aws_lb_target_group.wordpress.arn}"
    type             = "forward"
  }
}

// ECS service and task
data "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role-${var.environment}"
}

resource "aws_ecs_service" "wordpress" {
  name            = "wordpress"
  cluster         = "${aws_ecs_cluster.wordpress.id}"
  task_definition = "${aws_ecs_task_definition.wordpress.arn}"
  desired_count   = 1
  iam_role        = "${data.aws_iam_role.ecs_instance_role.arn}"

  load_balancer {
    target_group_arn = "${aws_lb_target_group.wordpress.arn}"
    container_name   = "wordpress_${var.environment}"
    container_port   = "80"
  }
}

resource "aws_ecs_cluster" "wordpress" {
  name = "wordpress_${var.environment}"
}

resource "aws_iam_instance_profile" "ecs_profile" {
  name = "ecs-instance-profile-wp-${var.environment}"
  role = "${data.aws_iam_role.ecs_instance_role.id}"
}

module "wordpress_lc" {
  source      = "../../../utils/launch_configuration"
  environment = "${var.environment}"

  cluster_name            = "${aws_ecs_cluster.wordpress.name}"
  key_name                = "${var.key_name}"
  iam_instance_profile_id = "${aws_iam_instance_profile.ecs_profile.id}"
  security_groups         = ["${var.ec2_security_groups}"]
  instance_type           = "${var.instance_type}"
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = "${module.wordpress_lc.id}"
  min_size             = "${var.asg_min_size}"
  max_size             = "${var.asg_max_size}"
  health_check_type    = "ELB"
  vpc_zone_identifier  = ["${var.subnet_ids}"]

  lifecycle {
    create_before_destroy = true
  }
}

data "template_file" "container_definitions" {
  template = "${file("${path.module}/container-definitions.json")}"

  vars {
    container_name = "wordpress_${var.environment}"
    environment    = "${var.environment}"
    image_name     = "${var.image_name}"

    wordpress_db_host          = "${var.db_host}"
    wordpress_db_user          = "${var.db_user}"
    wordpress_db_password      = "${var.db_password}"
    wordpress_db_name          = "${var.db_name}"
    wordpress_auth_key         = "${var.auth_key}"
    wordpress_secure_auth_key  = "${var.secure_auth_key}"
    wordpress_logged_in_key    = "${var.logged_in_key}"
    wordpress_nonce_key        = "${var.nonce_key}"
    wordpress_auth_salt        = "${var.auth_salt}"
    wordpress_secure_auth_salt = "${var.secure_auth_salt}"
    wordpress_logged_in_salt   = "${var.logged_in_salt}"
    wordpress_nonce_salt       = "${var.nonce_salt}"
    wordpress_smtp_host        = "${var.smtp_host}"
    wordpress_smtp_port        = "${var.smtp_port}"
    wordpress_smtp_username    = "${var.smtp_username}"
    wordpress_smtp_password    = "${var.smtp_password}"
    wordpress_smtp_from        = "${var.smtp_from}"
    wordpress_smtp_from_name   = "${var.smtp_from_name}"
  }
}

data "aws_iam_role" "exec_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "wordpress" {
  family                = "wordpress"
  execution_role_arn    = "${data.aws_iam_role.exec_role.arn}"
  container_definitions = "${data.template_file.container_definitions.rendered}"
}

/*
 * Outputs
 */
output "lb_dns_name" {
  value = "${aws_lb.wordpress.dns_name}"
}

output "lb_zone_id" {
  value = "${aws_lb.wordpress.zone_id}"
}
