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
  default = "development"
}

# Shared

variable "db_username" {}
variable "db_password" {}
variable "tools_port" {}
variable "smtp_host" {}
variable "smtp_port" {}
variable "sso_endpoint" {}
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

variable "tools_sender_email" {
  default = "admin@debtcollective.org"
}

variable "tools_disputes_bcc_address" {
  default = "admin@debtcollective.org"
}

variable "tools_contact_email" {
  default = "admin@debtcollective.org"
}

# Discourse

variable "discourse_smtp_user" {}
variable "discourse_smtp_pass" {}

/*
 * Remote State
 */
terraform {
  backend "s3" {
    bucket = "debtcollective-terraform"
    region = "us-west-2"

    // This is the state key, make sure you are using the right environment in line 13, otherwise you may overwrite other state
    // We cannot use variables at this point
    key = "development/terraform.tfstate"
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

// Discourse Database
resource "aws_db_instance" "postgres" {
  identifier        = "postgres-${var.environment}"
  allocated_storage = "10"
  engine            = "postgres"
  engine_version    = "9.6.6"
  instance_class    = "db.t2.micro"
  name              = "debtsyndicate${var.environment}"
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
  source = "./modules/utils/ecs_role"

  environment = "${var.environment}"
}

// key_pair for Discourse cluster
resource "aws_key_pair" "development" {
  key_name   = "development-tdc"
  public_key = ""

  lifecycle {
    prevent_destroy = true
  }
}

// Discourse EC2 Instance
module "discourse" {
  source      = "./modules/compute/services/discourse"
  environment = "${var.environment}"

  discourse_hostname = "community-staging.debtcollective.org"

  discourse_smtp_address   = "${var.smtp_host}"
  discourse_smtp_user_name = "${var.discourse_smtp_user}"
  discourse_smtp_password  = "${var.discourse_smtp_pass}"

  discourse_db_host     = "${aws_db_instance.postgres.address}"
  discourse_db_name     = "discourse_${var.environment}"
  discourse_db_username = "${var.db_username}"
  discourse_db_password = "${var.db_password}"

  key_name        = "${aws_key_pair.development.key_name}"
  subnet_id       = "${element(module.vpc.public_subnet_ids, 0)}"
  security_groups = "${module.vpc.ec2_security_group_id}"
}

module "dispute_tools" {
  source          = "./modules/compute/services/dispute-tools"
  environment     = "${var.environment}"
  vpc_id          = "${module.vpc.id}"
  subnets         = "${module.vpc.public_subnet_ids}"
  subnet_id       = "${element(module.vpc.public_subnet_ids, 0)}"
  security_groups = "${module.vpc.ec2_security_group_id}"

  sso_endpoint = "${var.sso_endpoint}"
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

  db_connection_string = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/dispute_tools_${var.environment}"
  db_pool_min          = "${var.tools_db_pool_min}"
  db_pool_max          = "${var.tools_db_pool_max}"
}
