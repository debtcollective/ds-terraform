/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
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
  default     = "t2.micro"
}

variable "smtp_host" {
  description = "SMTP host"
}

variable "smtp_port" {
  description = "SMTP port"
  default     = "587"
}

variable "smtp_user" {
  description = "SMTP user"
}

variable "smtp_pass" {
  description = "SMTP password"
}

variable "admin_email" {
  description = "Support and contact email"
  default     = "admin@debtsyndicate.org"
}

variable "sitename" {
  description = "Sitename to be displayed in the website"
  default     = "The Debt Syndicate"
}

variable "domain" {
  description = "Domain to be used by the instance"
}

/*
 * Resources
 */
// ec2 instance
data "aws_ami" "mediawiki" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-mediawiki-1.30.0-0-r02-linux-ubuntu-16.04-x86_64-hvm-ebs-mp-b3ebc2b0-8c88-4edd-9551-8b8b5ec57943-ami-b6d8e8cc.4"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"] # Bitnami
}

// ec2 instance user_data
data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.sh")}"
}

data "template_file" "httpdconf" {
  template = "${file("${path.module}/httpd-prefix.conf")}"
}

data "template_file" "autorenew" {
  template = "${file("${path.module}/renew-certificate.sh")}"

  vars {
    domain = "${var.domain}"
  }
}

data "template_file" "bootstrap" {
  template = "${file("${path.module}/bootstrap.sh")}"

  vars {
    domain      = "${var.domain}"
    sitename    = "${var.sitename}"
    admin_email = "${var.admin_email}"
    smtp_host   = "${var.smtp_host}"
    smtp_port   = "${var.smtp_port}"
    smtp_user   = "${var.smtp_user}"
    smtp_pass   = "${var.smtp_pass}"
  }
}

resource "aws_instance" "mediawiki" {
  instance_type          = "${var.instance_type}"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${var.security_groups}"]
  ami                    = "${data.aws_ami.mediawiki.id}"
  subnet_id              = "${var.subnet_id}"
  user_data              = "${data.template_file.user_data.rendered}"

  tags {
    Name        = "mediawiki_${var.environment}"
    Environment = "${var.environment}"
    Terraform   = true
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = false
  }

  timeouts {
    create = "30m"
  }

  // httpd.conf
  provisioner "file" {
    content     = "${data.template_file.httpdconf.rendered}"
    destination = "~/httpd-prefix.conf"

    connection {
      user        = "bitnami"
      port        = "12345"
      timeout     = "2m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  // autorenew letsencrypt certificate
  provisioner "file" {
    content     = "${data.template_file.autorenew.rendered}"
    destination = "~/renew-certificate.sh"

    connection {
      user        = "bitnami"
      port        = "12345"
      timeout     = "2m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  // bootstrap.sh file
  // we need to exec this in the server once it's running
  provisioner "file" {
    content     = "${data.template_file.bootstrap.rendered}"
    destination = "~/bootstrap.sh"

    connection {
      user        = "bitnami"
      port        = "12345"
      timeout     = "2m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  // upload logo
  provisioner "file" {
    content     = "${file("${path.module}/dc.png")}"
    destination = "/home/bitnami/apps/mediawiki/htdocs/resources/assets/dc.png"

    connection {
      user        = "bitnami"
      port        = "12345"
      timeout     = "2m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }
}

resource "aws_eip" "mediawiki" {
  instance = "${aws_instance.mediawiki.id}"
  vpc      = true
}

/*
 * Outputs
 */
output "public_ip" {
  value = "${aws_eip.mediawiki.public_ip}"
}
