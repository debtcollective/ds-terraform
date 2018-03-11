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
  statuses = ["AMAZON_ISSUED"]
}

resource "aws_elb" "dispute_tools" {
  name               = "dispute_tools_${var.environment}_elb"
  availability_zones = ["us-west-2a", "us-east-2a"]

  listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${aws_acm_certificate.debtcollective.arn}"
  }

  tags {
    Terraform = true
    Name      = "dispute_tools_${var.environment}_elb"
  }
}

data "aws_ecs_task_definition" "dispute_tools" {
  task_definition = "${aws_ecs_task_definition.dispute_tools.family}"
}

resource "aws_ecs_service" "dispute_tools" {
  name            = "dispute_tools"
  cluster         = "${aws_ecs_cluster.dispute_tools.id}"
  task_definition = "${aws_ecs_task_definition.dispute_tools.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
  }

  load_balancer {
    elb_name       = "${aws_elb.dispute_tools.name}"
    container_name = "tds-dispute-tools"
    container_port = 8080
  }
}

resource "aws_ecs_cluster" "dispute_tools" {
  name = "dispute_tools"
}

resource "aws_ecs_task_definition" "dispute_tools" {
  family = "dispute_tools"

  container_definitions = <<DEFINITION
[
  {
      "dnsSearchDomains": null,
      "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
              "awslogs-group": "/ecs/dispute-tools-staging",
              "awslogs-region": "us-east-1",
              "awslogs-stream-prefix": "ecs"
          }
      },
      "entryPoint": [],
      "portMappings": [
          {
              "hostPort": 8080,
              "protocol": "tcp",
              "containerPort": 8080
          }
      ],
      "command": [],
      "linuxParameters": null,
      "cpu": 0,
      "environment": [
          {
              "name": "SSO_ENDPOINT",
              "value": "${var.sso_endpoint}"
          },
          {
              "name": "SSO_SECRET",
              "value": "${var.sso_secret}"
          },
          {
              "name": "JWT_SECRET",
              "value": "${var.jwt_secret}"
          },
          {
              "name": "SSO_COOKIE_NAME",
              "value": "${var.cookie_name}"
          },
          {
              "name": "SITE_URL",
              "value": "${var.site_url}"
          },
          {
              "name": "PORT",
              "value": "${var.port}"
          },
          {
              "name": "NODE_ENV",
              "value": "${var.environment}"
          },
          {
              "name": "EMAIL_CONTACT",
              "value": "${var.contact_email}"
          },
          {
              "name": "EMAIL_NO_REPLY",
              "value": "${var.sender_email}"
          },
          {
              "name": "EMAIL_DISPUTES_BCC",
              "value": "${var.disputes_bcc_address}"
          },
          {
              "name": "EMAIL_HOST",
              "value": "${var.smtp_host}"
          },
          {
              "name": "EMAIL_PORT",
              "value": "${var.smtp_port}"
          },
          {
              "name": "EMAIL_SECURE",
              "value": "${var.smtp_secure}"
          },
          {
              "name": "EMAIL_AUTH",
              "value": "${var.smtp_user}"
          },
          {
              "name": "EMAIL_PASS",
              "value": "${var.smtp_pas}"
          },
          {
              "name": "LOGGLY_KEY",
              "value": "${var.loggly_api_key}"
          },
          {
              "name": "STRIPE_PRIVATE",
              "value": "${var.stripe_private}"
          },
          {
              "name": "STRIPE_PUBLISHABLE",
              "value": "${var.stripe_publishable}"
          },
          {
              "name": "GMAPS_KEY",
              "value": "${var.google_maps_api_key}"
          },
          {
              "name": "AWS_UPLOAD_BUCKET",
              "value": "${aws_s3_bucket.disputes.name}"
          },
          {
              "name": "AWS_ACCESS_KEY_ID",
              "value": "${aws_iam_access_key.disputes_uploader.id}"
          },
          {
              "name": "AWS_SECRET_ACCESS_KEY",
              "value": "${aws_iam_access_key.disputes_uploader.secret}"
          },
          {
              "name": "AWS_DEFAULT_REGION",
              "value": "${aws_s3_bucket.disputes.region}""
          },
          {
              "name": "DB_CONNECTION_STRING",
              "value": "${var.db_connection_string}"
          },
          {
              "name": "DB_POOL_MIN",
              "value": "${var.db_pool_min}"
          },
          {
              "name": "DB_POOL_MAX",
              "value": "${var.db_pool_max}"
          }
      ],
      "ulimits": null,
      "dnsServers": null,
      "mountPoints": null,
      "workingDirectory": null,
      "dockerSecurityOptions": null,
      "memoryReservation": "",
      "volumesFrom": null,
      "image": "183550513269.dkr.ecr.us-west-2.amazonaws.com/ds-dispute-tools:latest",
      "disableNetworking": null,
      "healthCheck": null,
      "essential": true,
      "links": [],
      "hostname": null,
      "extraHosts": null,
      "user": null,
      "readonlyRootFilesystem": null,
      "dockerLabels": null,
      "privileged": null,
      "name": "dispute-tools"
  }
]
DEFINITION
}

resource "aws_eip" "disputes" {
  vpc = true
}

data "aws_route53_zone" "primary" {
  name = "debtcollective.org."
}

resource "aws_route53_record" "dispute-tools" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "tools-staging"
  type    = "A"
  ttl     = 300
  records = ["${}"]
}
