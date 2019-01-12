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
  default = "production"
}

# Shared

variable "db_username" {}
variable "db_password" {}
variable "domain" {}

// Cloudfront zone id is fixed
// https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-route53-aliastarget.html
variable "cloudfront_zone_id" {
  default = "Z2FDTNDATAQYW2"
}

# Dispute tools
variable "dispute_tools" {
  default = {}
}

# Discourse
variable "discourse" {
  default = {}
}

# Mediawiki
variable "mediawiki" {
  default = {}
}

# Power Report
variable "power_report" {
  default = {}
}

# Landing
variable "landing" {
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
    key = "production/terraform.tfstate"
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
  allocated_storage = "30"
  engine            = "postgres"
  engine_version    = "10.5"
  instance_class    = "db.t2.micro"
  name              = "discourse_${var.environment}"
  username          = "${var.db_username}"
  password          = "${var.db_password}"

  backup_window           = "22:00-23:59"
  maintenance_window      = "sat:20:00-sat:21:00"
  backup_retention_period = "7"

  vpc_security_group_ids = ["${module.vpc.rds_security_group_id}"]

  db_subnet_group_name = "${aws_db_subnet_group.postgres_sg.name}"
  parameter_group_name = "default.postgres10"

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

  discourse_hostname = "community.${var.domain}"

  discourse_smtp_address   = "${var.discourse["smtp_host"]}"
  discourse_smtp_user_name = "${var.discourse["smtp_user"]}"
  discourse_smtp_password  = "${var.discourse["smtp_pass"]}"

  discourse_db_host     = "${aws_db_instance.postgres.address}"
  discourse_db_name     = "discourse_${var.environment}"
  discourse_db_username = "${var.db_username}"
  discourse_db_password = "${var.db_password}"
  discourse_sso_secret  = "${var.discourse["sso_secret"]}"

  discourse_reply_by_email_address = "${var.discourse["reply_by_email_address"]}"
  discourse_pop3_polling_username  = "${var.discourse["pop3_polling_username"]}"
  discourse_pop3_polling_password  = "${var.discourse["pop3_polling_password"]}"
  discourse_pop3_polling_host      = "${var.discourse["pop3_polling_host"]}"
  discourse_pop3_polling_port      = "${var.discourse["pop3_polling_port"]}"

  discourse_ga_universal_tracking_code = "${var.discourse["ga_universal_tracking_code"]}"

  key_name        = "${aws_key_pair.ssh.key_name}"
  subnet_id       = "${element(module.vpc.public_subnet_ids, 0)}"
  security_groups = "${module.vpc.ec2_security_group_id}"
}

module "dispute_tools" {
  source              = "./modules/compute/services/dispute-tools"
  environment         = "${var.environment}"
  subnet_ids          = "${module.vpc.public_subnet_ids}"
  ec2_security_groups = "${module.vpc.ec2_security_group_id}"
  key_name            = "${aws_key_pair.ssh.key_name}"

  sso_endpoint     = "https://${aws_route53_record.discourse.fqdn}/session/sso_provider"
  site_url         = "https://${aws_route53_record.dispute_tools.fqdn}"
  sso_secret       = "${var.discourse["sso_secret"]}"
  jwt_secret       = "${var.dispute_tools["jwt_secret"]}"
  cookie_name      = "${var.dispute_tools["cookie_name"]}${var.environment}__"
  landing_page_url = "https://${aws_route53_record.landing.fqdn}"

  contact_email        = "${var.dispute_tools["contact_email"]}"
  sender_email         = "${var.dispute_tools["sender_email"]}"
  disputes_bcc_address = "${var.dispute_tools["disputes_bcc_address"]}"

  ecs_instance_profile = "${module.ecs_role.instance_profile_id}"
  ecs_instance_role    = "${module.ecs_role.instance_role_arn}"

  acm_certificate_domain = "*.${var.domain}"
  elb_security_groups    = "${module.vpc.elb_security_group_id}"
  vpc_id                 = "${module.vpc.id}"

  smtp_host = "${var.dispute_tools["smtp_host"]}"
  smtp_port = "${var.dispute_tools["smtp_port"]}"
  smtp_user = "${var.dispute_tools["smtp_user"]}"
  smtp_pass = "${var.dispute_tools["smtp_pass"]}"

  loggly_api_key = "${var.dispute_tools["loggly_api_key"]}"

  stripe_private     = "${var.dispute_tools["stripe_private"]}"
  stripe_publishable = "${var.dispute_tools["stripe_publishable"]}"

  google_maps_api_key = "${var.dispute_tools["gmaps_api_key"]}"

  sentry_endpoint = "${var.dispute_tools["sentry_endpoint"]}"

  db_connection_string = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/dispute_tools_${var.environment}"
  db_pool_min          = "${var.dispute_tools["db_pool_min"]}"
  db_pool_max          = "${var.dispute_tools["db_pool_max"]}"

  image_name = "${var.dispute_tools["image_name"]}"

  discourse_base_url     = "https://${aws_route53_record.discourse.fqdn}"
  discourse_api_key      = "${var.dispute_tools["discourse_api_key"]}"
  discourse_api_username = "${var.dispute_tools["discourse_api_username"]}"

  doe_disclosure_representatives = "${var.dispute_tools["doe_disclosure_representatives"]}"
  doe_disclosure_phones          = "${var.dispute_tools["doe_disclosure_phones"]}"
  doe_disclosure_relationship    = "${var.dispute_tools["doe_disclosure_relationship"]}"
  doe_disclosure_address         = "${var.dispute_tools["doe_disclosure_address"]}"
  doe_disclosure_city            = "${var.dispute_tools["doe_disclosure_city"]}"
  doe_disclosure_state           = "${var.dispute_tools["doe_disclosure_state"]}"
  doe_disclosure_zip             = "${var.dispute_tools["doe_disclosure_zip"]}"

  recaptcha_site_key   = "${var.dispute_tools["recaptcha_site_key"]}"
  recaptcha_secret_key = "${var.dispute_tools["recaptcha_secret_key"]}"

  google_analytics_ua = "${var.dispute_tools["google_analytics_ua"]}"
}

module "metabase" {
  source      = "./modules/compute/services/metabase"
  environment = "${var.environment}"

  db_username = "${var.db_username}"
  db_password = "${var.db_password}"
  db_host     = "${aws_db_instance.postgres.address}"
  db_port     = "${aws_db_instance.postgres.port}"
  db_name     = "metabase_${var.environment}"

  acm_certificate_domain = "*.${var.domain}"
  elb_security_groups    = "${module.vpc.elb_security_group_id}"
  vpc_id                 = "${module.vpc.id}"

  key_name                = "${aws_key_pair.ssh.key_name}"
  iam_instance_profile_id = "${module.ecs_role.instance_profile_id}"
  subnet_ids              = ["${module.vpc.public_subnet_ids}"]
  security_groups         = ["${module.vpc.ec2_security_group_id}"]
}

// Route 53
data "aws_route53_zone" "primary" {
  name = "${var.domain}."
}

resource "aws_route53_record" "discourse" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "community"
  type    = "A"
  ttl     = 300
  records = ["${module.discourse.public_ip}"]
}

resource "aws_route53_record" "dispute_tools" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "tools"
  type    = "A"

  alias {
    name                   = "${module.dispute_tools.lb_dns_name}"
    zone_id                = "${module.dispute_tools.lb_zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "landing" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = ""
  type    = "A"

  alias {
    name                   = "${var.landing["cloudfront_domain_name"]}"
    zone_id                = "${var.cloudfront_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "power_report" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "powerreport"
  type    = "A"

  alias {
    name                   = "${var.power_report["cloudfront_domain_name"]}"
    zone_id                = "${var.cloudfront_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "metabase" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "metabase"
  type    = "A"

  alias {
    name                   = "${module.metabase.dns_name}"
    zone_id                = "${module.metabase.zone_id}"
    evaluate_target_health = true
  }
}
