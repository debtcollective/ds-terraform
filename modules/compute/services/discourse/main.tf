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
  default     = "orlando@hashlabs.com,alex@marcondesian.net,sberleant@gmail.com"
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
    discourse_letsencrypt_account_email = "${var.discourse_letsencrypt_account_email}"
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
    volume_size           = 12
    volume_type           = "gp2"
    delete_on_termination = false
  }

  timeouts {
    create = "30m"
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

  provisioner "remote-exec" {
    inline = [
      // Update OS
      <<-BASH
        sudo apt-get update && sudo apt-get dist-upgrade \
          -o Dpkg::Options::="--force-confdef" \
          -o Dpkg::Options::="--force-confold" \
          --assume-yes
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
      BASH
      ,

      // Bootstrap Discourse
      <<-BASH
        cd /opt/discourse
        sudo ./launcher bootstrap web
        sudo ./launcher start web
      BASH
      ,

      // Add ubuntu to the docker user group
      <<-BASH
        sudo usermod -aG docker $${USER}
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

// Route 53
data "aws_route53_zone" "primary" {
  name = "debtcollective.org."
}

resource "aws_route53_record" "discourse" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "community-staging"
  type    = "A"
  ttl     = 300
  records = ["${aws_eip.discourse.public_ip}"]
}

/*
 * Outputs
 */
output "public_ip" {
  value = "${aws_eip.discourse.public_ip}"
}
