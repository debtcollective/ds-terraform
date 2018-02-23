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

variable "discourse_db_username" {}
variable "discourse_db_password" {}

variable "smtp_address" {}
variable "smtp_username" {}
variable "smtp_password" {}

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
resource "aws_db_instance" "discourse" {
  identifier        = "postgres-${var.environment}"
  allocated_storage = "10"
  engine            = "postgres"
  engine_version    = "9.6.6"
  instance_class    = "db.t2.micro"
  name              = "discourse_${var.environment}"
  username          = "${var.discourse_db_username}"
  password          = "${var.discourse_db_password}"

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

  discourse_smtp_address   = "${var.smtp_address}"
  discourse_smtp_user_name = "${var.smtp_username}"
  discourse_smtp_password  = "${var.smtp_password}"

  discourse_db_host     = "${aws_db_instance.discourse.address}"
  discourse_db_name     = "discourse_${var.environment}"
  discourse_db_username = "${var.discourse_db_username}"
  discourse_db_password = "${var.discourse_db_password}"

  key_name        = "${aws_key_pair.development.key_name}"
  subnet_id       = "${element(module.vpc.public_subnet_ids, 0)}"
  security_groups = "${module.vpc.ec2_security_group_id}"
}
