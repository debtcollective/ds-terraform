/*
 * Config
 */
provider "aws" {
  region = "us-east-1"
}

/*
 * Variables
 */
variable "environment" {
  default = "staging"
}

# Shared

variable "db_username" {}
variable "db_password" {}
variable "tools_port" {}
variable "smtp_host" {}
variable "smtp_port" {}
variable "sso_secret" {}

# Dispute tools

variable "tools_smtp_pass" {}
variable "tools_smtp_user" {}
variable "tools_gmaps_api_key" {}

variable "tools_cookie_name" {
  description = "Will have the environment appended to it to maintain environmental atomicity"
  default     = "_dispute_tools__"
}

variable "tools_jwt_secret" {}
variable "tools_loggly_api_key" {}
variable "tools_stripe_private" {}
variable "tools_stripe_publishable" {}
variable "tools_db_pool_min" {}
variable "tools_db_pool_max" {}

variable "tools_sentry_endpoint" {}

variable "tools_sender_email" {
  default = "admin@debtsyndicate.org"
}

variable "tools_disputes_bcc_address" {
  default = "admin@debtsyndicate.org"
}

variable "tools_contact_email" {
  default = "admin@debtsyndicate.org"
}

variable "tools_image_name" {
  description = "Full repository URI reference to image name to deploy"
  default     = "debtcollective/dispute-tools:latest"
}

variable "tools_discourse_api_username" {
  default = "system"
}

variable "tools_discourse_base_url" {}
variable "tools_discourse_api_key" {}
variable "tools_doe_disclosure_representatives" {}
variable "tools_doe_disclosure_phones" {}
variable "tools_doe_disclosure_relationship" {}
variable "tools_doe_disclosure_address" {}
variable "tools_doe_disclosure_city" {}
variable "tools_doe_disclosure_state" {}
variable "tools_doe_disclosure_zip" {}

# Discourse

variable "discourse_smtp_user" {}
variable "discourse_smtp_pass" {}
variable "discourse_reply_by_email_address" {}
variable "discourse_pop3_polling_username" {}
variable "discourse_pop3_polling_password" {}
variable "discourse_pop3_polling_host" {}
variable "discourse_pop3_polling_port" {}

# Mediawiki

variable "mediawiki" {
  default = {}
}

/*
 * Remote State
 */
terraform {
  backend "s3" {
    bucket = "tdc-terraform"
    region = "us-east-1"

    // This is the state key, make sure you are using the right environment on line 12, otherwise you may overwrite other state
    // We cannot use variables at this point
    key = "staging/terraform.tfstate"
  }
}

/*
 * Resources
 */
module "vpc" {
  source = "./modules/network/vpc"

  environment = "${var.environment}"
}

// Database
// Create Subnet Group
resource "aws_db_subnet_group" "postgres_sg" {
  name        = "postgres-${var.environment}-sg"
  description = "postgres-${var.environment} RDS subnet group"
  subnet_ids  = ["${module.vpc.private_subnet_ids}"]
}

// Postgres Database
resource "aws_db_instance" "postgres" {
  identifier        = "postgres-${var.environment}"
  allocated_storage = "20"
  engine            = "postgres"
  engine_version    = "9.6.6"
  instance_class    = "db.t2.micro"
  name              = "discourse_${var.environment}"
  username          = "${var.db_username}"
  password          = "${var.db_password}"

  backup_window           = "22:00-23:59"
  maintenance_window      = "sat:20:00-sat:21:00"
  backup_retention_period = "7"

  vpc_security_group_ids = ["${module.vpc.rds_security_group_id}"]

  db_subnet_group_name = "${aws_db_subnet_group.postgres_sg.name}"
  parameter_group_name = "default.postgres9.6"

  multi_az                  = true
  storage_type              = "gp2"
  skip_final_snapshot       = true
  final_snapshot_identifier = "postgres-${var.environment}"

  tags {
    Terraform   = true
    Name        = "postgres-${var.environment}"
    Environment = "${var.environment}"
  }
}

// ECS instance_profile and iam_role
module "ecs_role" {
  source      = "./modules/utils/ecs_role"
  environment = "${var.environment}"
}

// key_pair for Discourse cluster
resource "aws_key_pair" "ssh" {
  key_name   = "key_pair_${var.environment}"
  public_key = "${file("key_pair_${var.environment}.pub")}"
}

module "discourse" {
  source      = "./modules/compute/services/discourse"
  environment = "${var.environment}"

  discourse_hostname = "community.${var.environment}.debtsyndicate.org"

  discourse_smtp_address   = "${var.smtp_host}"
  discourse_smtp_user_name = "${var.discourse_smtp_user}"
  discourse_smtp_password  = "${var.discourse_smtp_pass}"

  discourse_db_host     = "${aws_db_instance.postgres.address}"
  discourse_db_name     = "discourse_${var.environment}"
  discourse_db_username = "${var.db_username}"
  discourse_db_password = "${var.db_password}"
  discourse_sso_secret  = "${var.sso_secret}"

  discourse_reply_by_email_address = "${var.discourse_reply_by_email_address}"
  discourse_pop3_polling_username  = "${var.discourse_pop3_polling_username}"
  discourse_pop3_polling_password  = "${var.discourse_pop3_polling_password}"
  discourse_pop3_polling_host      = "${var.discourse_pop3_polling_host}"
  discourse_pop3_polling_port      = "${var.discourse_pop3_polling_port}"

  key_name        = "${aws_key_pair.ssh.key_name}"
  subnet_id       = "${element(module.vpc.public_subnet_ids, 0)}"
  security_groups = "${module.vpc.ec2_security_group_id}"
}

module "dispute_tools" {
  source              = "./modules/compute/services/dispute-tools"
  environment         = "${var.environment}"
  vpc_id              = "${module.vpc.id}"
  subnet_ids          = "${module.vpc.public_subnet_ids}"
  ec2_security_groups = "${module.vpc.ec2_security_group_id}"
  elb_security_groups = "${module.vpc.elb_security_group_id}"
  key_name            = "${aws_key_pair.ssh.key_name}"

  sso_endpoint = "https://${aws_route53_record.discourse.fqdn}/session/sso_provider"
  site_url     = "https://${aws_route53_record.dispute_tools.fqdn}"
  sso_secret   = "${var.sso_secret}"
  jwt_secret   = "${var.tools_jwt_secret}"
  cookie_name  = "${var.tools_cookie_name}${var.environment}__"

  contact_email        = "${var.tools_contact_email}"
  sender_email         = "${var.tools_sender_email}"
  disputes_bcc_address = "${var.tools_disputes_bcc_address}"

  smtp_host = "${var.smtp_host}"
  smtp_port = "${var.smtp_port}"
  smtp_user = "${var.tools_smtp_user}"
  smtp_pass = "${var.tools_smtp_pass}"

  loggly_api_key = "${var.tools_loggly_api_key}"

  stripe_private     = "${var.tools_stripe_private}"
  stripe_publishable = "${var.tools_stripe_publishable}"

  google_maps_api_key = "${var.tools_gmaps_api_key}"

  sentry_endpoint = "${var.tools_sentry_endpoint}"

  db_connection_string = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/dispute_tools_${var.environment}"
  db_pool_min          = "${var.tools_db_pool_min}"
  db_pool_max          = "${var.tools_db_pool_max}"

  image_name = "${var.tools_image_name}"

  discourse_base_url     = "${var.tools_discourse_base_url}"
  discourse_api_key      = "${var.tools_discourse_api_key}"
  discourse_api_username = "${var.tools_discourse_api_username}"

  doe_disclosure_representatives = "${var.tools_doe_disclosure_representatives}"
  doe_disclosure_phones          = "${var.tools_doe_disclosure_phones}"
  doe_disclosure_relationship    = "${var.tools_doe_disclosure_relationship}"
  doe_disclosure_address         = "${var.tools_doe_disclosure_address}"
  doe_disclosure_city            = "${var.tools_doe_disclosure_city}"
  doe_disclosure_state           = "${var.tools_doe_disclosure_state}"
  doe_disclosure_zip             = "${var.tools_doe_disclosure_zip}"
}

// Route 53
data "aws_route53_zone" "primary" {
  name = "debtsyndicate.org."
}

resource "aws_route53_record" "discourse" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "staging.community"
  type    = "A"
  ttl     = 300
  records = ["${module.discourse.public_ip}"]
}

resource "aws_route53_record" "dispute_tools" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "staging"
  type    = "A"

  alias {
    name                   = "${module.dispute_tools.lb_dns_name}"
    zone_id                = "${module.dispute_tools.lb_zone_id}"
    evaluate_target_health = true
  }
}
