/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
}

variable "discourse_hostname" {
  description = "Discourse hostname"
}

variable "discourse_developer_emails" {
  description = "Discourse developer emails for notifications"
  default     = "orlando@hashlabs.com"
}

// SMTP configuration
variable "discourse_smtp_address" {
  description = "Discourse SMTP address"
}

variable "discourse_smtp_port" {
  description = "Discourse SMTP port"
  default     = 587
}

variable "discourse_smtp_user_name" {
  description = "Discourse SMTP user name"
}

variable "discourse_smtp_password" {
  description = "Discourse SMTP password"
}

variable "discourse_smtp_enable_start_tls" {
  description = "Discourse SMTP enable start TLS"
  default     = true
}

variable "discourse_smtp_authentication" {
  description = "Discourse SMTP authentication"
  default     = "plain"
}

// Database Configuration
variable "discourse_db_host" {
  description = "Discourse database host URL"
}

variable "discourse_db_name" {
  description = "Discourse database name"
}

variable "discourse_db_username" {
  description = "Discourse database username"
}

variable "discourse_db_password" {
  description = "Discourse database password"
}

variable "discourse_letsencrypt_account_email" {
  description = "email to setup Let's Encrypt"
  default     = "orlando@hashlabs.com"
}

variable "discourse_sso_secret" {
  description = "SSO secret for Discourse"
}

variable "discourse_reply_by_email_address" {
  description = "Reply by email address, needs %{reply_key} variable to be in the value"
}

variable "discourse_pop3_polling_username" {
  description = "pop3 username for the address used in reply by email"
}

variable "discourse_pop3_polling_password" {
  description = "pop3 password for the address used in reply by email"
}

variable "discourse_pop3_polling_host" {
  description = "pop3 host for the address used in reply by email"
}

variable "discourse_pop3_polling_port" {
  description = "pop3 port for the address used in reply by email"
}

variable "discourse_ga_universal_tracking_code" {
  description = "Google analytics universal tracking code"
}

variable "discourse_maxmind_license_key" {
  description = "Maxmind geo2ip database license key"
}

variable "key_name" {
  description = "SSH Key Pair to be assigned to the instance"
}

variable "subnet_id" {
  description = "VPC Subnet ID to be used in by the instance"
}

variable "security_groups" {
  description = "VPC Security Groups IDs to be used by the instance"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.small"
}

variable "volume_size" {
  description = "EBS block size"
  default     = 25
}

variable "acm_certificate_domain" {
  description = "ACM certificate domain name to be used for CDN SSL"
  default     = "*.debtcollective.org"
}

variable "domain" {}

/*
 * Resources
 */
// ec2 instance
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-20180228.1"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

// ec2 instance user_data
data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.sh")}"
}

// Generate sso_jwt_secret
resource "random_string" "discourse_sso_jwt_secret" {
  length = 64
}

resource "aws_ssm_parameter" "discourse_sso_jwt_secret" {
  name  = "/${var.environment}/services/discourse/sso_jwt_secret"
  type  = "SecureString"
  value = "${random_string.discourse_sso_jwt_secret.result}"
}

// Discourse configuration
data "template_file" "discourse" {
  template = "${file("${path.module}/web.yml")}"

  vars {
    discourse_smtp_port             = "${var.discourse_smtp_port}"
    discourse_smtp_username         = "${var.discourse_smtp_user_name}"
    discourse_smtp_password         = "${var.discourse_smtp_password}"
    discourse_smtp_address          = "${var.discourse_smtp_address}"
    discourse_smtp_enable_start_tls = "${var.discourse_smtp_enable_start_tls}"
    discourse_smtp_authentication   = "${var.discourse_smtp_authentication}"

    discourse_db_host     = "${var.discourse_db_host}"
    discourse_db_port     = "5432"
    discourse_db_name     = "${var.discourse_db_name}"
    discourse_db_username = "${var.discourse_db_username}"
    discourse_db_password = "${var.discourse_db_password}"

    discourse_developer_emails          = "${var.discourse_developer_emails}"
    discourse_hostname                  = "${var.discourse_hostname}"
    discourse_maxmind_license_key       = "${var.discourse_maxmind_license_key}"
    discourse_letsencrypt_account_email = "${var.discourse_letsencrypt_account_email}"
    discourse_sso_jwt_secret            = "${aws_ssm_parameter.discourse_sso_jwt_secret.value}"
    discourse_sso_cookie_name           = "tdc_auth_${var.environment}"
    discourse_sso_cookie_domain         = ".${var.domain}"

    discourse_s3_region            = "${aws_s3_bucket.uploads.region}"
    discourse_s3_access_key_id     = "${aws_iam_access_key.discourse.id}"
    discourse_s3_secret_access_key = "${aws_iam_access_key.discourse.secret}"
    discourse_s3_bucket            = "${aws_s3_bucket.uploads.id}"
    discourse_s3_cdn_url           = "https://${aws_route53_record.cdn.fqdn}"
  }
}

// S3 buckets and permissions
resource "aws_s3_bucket" "uploads" {
  bucket = "community-uploads-${var.environment}"
  acl    = "public-read"

  cors_rule {
    allowed_headers = ["Authorization"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  lifecycle_rule {
    id      = "purge_tombstone"
    enabled = true

    prefix = "tombstone/"

    expiration {
      days                         = 90
      expired_object_delete_marker = false
    }
  }

  tags {
    Terraform   = true
    Name        = "community-uploads-${var.environment}"
    Environment = "${var.environment}"
  }
}

// Uploads bucket Cloudfront CDN
locals {
  s3_origin_id = "community${title(var.environment)}"
  cdn_alias    = "community-cdn-${substr(var.environment, 0, 4)}"
}

data "aws_acm_certificate" "domain" {
  domain   = "${var.acm_certificate_domain}"
  statuses = ["ISSUED"]
}

data "aws_route53_zone" "primary" {
  name = "${var.domain}."
}

resource "aws_route53_record" "cdn" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "${local.cdn_alias}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.cdn.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.cdn.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_origin_access_identity" "uploads" {
  comment = "Community uploads bucket origin"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = "${aws_s3_bucket.uploads.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.uploads.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["${local.cdn_alias}.${var.domain}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Terraform   = true
    Name        = "${local.s3_origin_id}"
    Environment = "${var.environment}"
  }

  // We are using a custom alias
  // We need to provide a SSL certificate for that alias
  viewer_certificate {
    ssl_support_method  = "sni-only"
    acm_certificate_arn = "${data.aws_acm_certificate.domain.arn}"
  }
}

resource "aws_s3_bucket" "backups" {
  bucket = "community-backups-${var.environment}"

  tags {
    Terraform   = true
    Name        = "community-backups-${var.environment}"
    Environment = "${var.environment}"
  }
}

// User for Discourse s3 uploads
resource "aws_iam_user" "discourse" {
  name = "community-${var.environment}"
}

data "aws_iam_policy_document" "discourse" {
  statement {
    sid = "1"

    actions = [
      "s3:List*",
      "s3:Get*",
      "s3:Put*",
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:CreateBucket",
    ]

    resources = [
      "${aws_s3_bucket.uploads.arn}",
      "${aws_s3_bucket.uploads.arn}/*",
      "${aws_s3_bucket.backups.arn}",
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }

  statement {
    actions = [
      "s3:ListAllMyBuckets",
      "s3:HeadBucket",
    ]

    resources = [
      "*",
    ]
  }
}

resource "aws_iam_user_policy" "user_policy" {
  name_prefix = "CommunityPolicy${title(var.environment)}"
  user        = "${aws_iam_user.discourse.name}"

  policy = "${data.aws_iam_policy_document.discourse.json}"
}

resource "aws_iam_access_key" "discourse" {
  user = "${aws_iam_user.discourse.name}"
}

data "template_file" "discourse_settings" {
  template = "${file("${path.module}/settings.yml")}"

  vars {
    sso_secret = "${var.discourse_sso_secret}"

    reply_by_email_address = "${var.discourse_reply_by_email_address}"
    pop3_polling_host      = "${var.discourse_pop3_polling_host}"
    pop3_polling_port      = "${var.discourse_pop3_polling_port}"
    pop3_polling_username  = "${var.discourse_pop3_polling_username}"
    pop3_polling_password  = "${var.discourse_pop3_polling_password}"

    ga_universal_tracking_code = "${var.discourse_ga_universal_tracking_code}"

    s3_access_key_id     = "${aws_iam_access_key.discourse.id}"
    s3_secret_access_key = "${aws_iam_access_key.discourse.secret}"
    s3_upload_bucket     = "${aws_s3_bucket.uploads.id}"
    s3_cdn_url           = "https://${aws_route53_record.cdn.fqdn}"

    backup_frequency = "3"
    s3_backup_bucket = "${aws_s3_bucket.backups.id}"
  }
}

resource "aws_instance" "discourse" {
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${var.security_groups}"]
  ami                    = "${data.aws_ami.ubuntu.id}"
  subnet_id              = "${var.subnet_id}"
  user_data              = "${data.template_file.user_data.rendered}"

  tags {
    Name        = "discourse_${var.environment}"
    Environment = "${var.environment}"
    Terraform   = true
  }

  root_block_device {
    volume_size           = "${var.volume_size}"
    volume_type           = "gp2"
    delete_on_termination = false
  }

  timeouts {
    create = "30m"
  }

  lifecycle {
    ignore_changes = ["user_data"]
  }

  // Install steps
  provisioner "file" {
    content     = "${data.template_file.discourse.rendered}"
    destination = "~/web.yml"

    connection {
      user        = "ubuntu"
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    content     = "${data.template_file.discourse_settings.rendered}"
    destination = "~/settings.yml"

    connection {
      user        = "ubuntu"
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      // Update
      <<-BASH
        sudo apt-get update
      BASH
      ,

      // Enable swap
      <<-BASH
        sudo fallocate -l 2G /swapfile
        ls -lh /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
        echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
      BASH
      ,

      // Install Docker
      <<-BASH
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo apt-key fingerprint 0EBFCD88

        repo=https://download.docker.com/linux/ubuntu
        sudo add-apt-repository "deb [arch=amd64] $repo $(lsb_release -cs) stable"
        sudo apt-get update && sudo apt-get install docker-ce -y \
          --no-install-recommends
      BASH
      ,

      // Download Discourse
      <<-BASH
        sudo mkdir -p /opt/discourse
        sudo chown ubuntu.ubuntu /opt/discourse
        git clone https://github.com/discourse/discourse_docker.git /opt/discourse
        mv ~/web.yml /opt/discourse/containers/web.yml
        mv ~/settings.yml /opt/discourse/settings.yml
      BASH
      ,

      // Add ubuntu to the docker user group
      <<-BASH
        sudo usermod -aG docker ubuntu
      BASH
      ,

      // Bootstrap Discourse
      // Allow some time to services come up
      <<-BASH
        cd /opt/discourse
        sudo ./launcher bootstrap web
        sudo ./launcher start web
        sleep 60
      BASH
      ,
    ]

    connection {
      user        = "ubuntu"
      port        = "12345"
      timeout     = "30m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      // Copy settings
      <<-BASH
        docker cp /opt/discourse/settings.yml web:/var/www/discourse
        docker exec -w /var/www/discourse web bash -c 'rake site_settings:import < settings.yml'
      BASH
      ,
    ]

    connection {
      user        = "ubuntu"
      port        = "12345"
      timeout     = "30m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }
}

resource "aws_eip" "discourse" {
  instance = "${aws_instance.discourse.id}"
  vpc      = true
}

/*
 * Outputs
 */
output "public_ip" {
  value = "${aws_eip.discourse.public_ip}"
}
