/*
 * Config
 */
provider "aws" {}

/*
 * Variables
 */
variable "environment" {
  default = "production"
}

variable "db_username" {
  default = "debtcollective"
}

variable "db_password" {}

variable "aws_bucket" {
  default = "debtcollective-deployed"
}

variable "aws_bucket_region" {
  default = "us-east-2"
}

variable "aws_access_key_id" {}

variable "aws_secret_access_key" {}

variable "web_instance_type" {
  default = "t2.micro"
}

/*
 * Remote State
 */
terraform {
  backend "s3" {
    bucket = "debtcollective-terraform"
    region = "us-west-2"

    // This is the state key, please make sure this namespace we are using matches the environment file in line 10
    key = "production/terraform.tfstate"
  }
}

/*
 * Resources
 */
// VPC
module "vpc" {
  source = "./modules/network/vpc"

  environment = "${var.environment}"
}

// Create Main Database
resource "aws_db_subnet_group" "postgres_sg" {
  name        = "postgres-${var.environment}-sg"
  description = "postgres-${var.environment} RDS subnet group"
  subnet_ids  = ["${module.vpc.private_subnet_ids}"]
}

resource "aws_db_instance" "postgres" {
  identifier        = "postgres-${var.environment}"
  allocated_storage = "10"
  engine            = "postgres"
  engine_version    = "9.6.2"
  instance_class    = "db.t2.micro"
  name              = "debtcollective_prod"
  username          = "${var.db_username}"
  password          = "${var.db_password}"

  backup_window           = "22:00-23:59"
  maintenance_window      = "sat:20:00-sat:21:00"
  backup_retention_period = "7"

  vpc_security_group_ids = ["${module.vpc.rds_security_group_id}"]

  db_subnet_group_name = "${aws_db_subnet_group.postgres_sg.name}"
  parameter_group_name = "default.postgres9.6"

  multi_az            = true
  storage_type        = "gp2"
  skip_final_snapshot = false

  tags {
    Name        = "discourse-database-${var.environment}"
    Environment = "${var.environment}"
    Terraform   = true
  }
}

// Create an Elastic Load Balancer
// Get an SSL certificate for debtcollective.org
data "aws_acm_certificate" "web" {
  domain   = "debtcollective.org"
  statuses = ["ISSUED"]
}

resource "aws_elb" "web" {
  name = "debtcollective-elb-${var.environment}"

  // The same availability zone as our instance
  subnets = ["${module.vpc.public_subnet_ids}"]

  security_groups = ["${module.vpc.elb_security_group_id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "${data.aws_acm_certificate.web.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 4
    timeout             = 3
    target              = "TCP:80"
    interval            = 15
  }
}

// Create Instance
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-20170619.1"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.sh")}"
}

data "template_file" "env_vars" {
  template = "${file("${path.module}/env_vars.sh")}"

  vars {
    environment           = "${var.environment}"
    database_url          = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/debtcollective_prod"
    aws_bucket            = "${var.aws_bucket}"
    aws_region            = "${var.aws_region}"
    aws_secret_access_key = "${var.aws_secret_access_key}"
    aws_access_key_id     = "${var.aws_access_key_id}"
  }
}

data "template_file" "knexfile" {
  template = "${file("${path.module}/files/knexfile.js")}"

  vars {
    database_url = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/debtcollective_prod"
  }
}

resource "aws_eip" "web" {
  instance = "${aws_instance.web.id}"
  vpc      = true
}

resource "aws_instance" "web" {
  ami           = "${data.aws_ami.ubuntu.id}"
  instance_type = "${var.web_instance_type}"
  user_data     = "${data.template_file.user_data.rendered}"

  subnet_id              = "${element(module.vpc.public_subnet_ids, 0)}"
  vpc_security_group_ids = ["${module.vpc.ec2_security_group_id}"]

  lifecycle {
    ignore_changes = ["user_data"]
  }

  root_block_device {
    volume_size           = 10
    volume_type           = "gp2"
    delete_on_termination = false
  }

  tags {
    Name        = "web-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }

  provisioner "file" {
    content     = "${data.template_file.env_vars.rendered}"
    destination = "/etc/profile.d/env_vars.sh"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    source      = "./files/id_rsa"
    destination = "/home/ubuntu/.ssh/id_rsa"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    source      = "./files/id_rsa.pub"
    destination = "/home/ubuntu/.ssh/id_rsa.pub"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  # Installing dependencies
  provisioner "remote-exec" {
    inline = [
      "curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -",
      "curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -",
      "echo \"deb https://dl.yarnpkg.com/debian/ stable main\" | sudo tee /etc/apt/sources.list.d/yarn.list",
      "sudo apt-get -y update",
      "sudo apt-get -y install git-core build-essential tcl redis-server libssl-dev nodejs yarn nginx",
      "sudo apt-get -y install graphicsmagick imagemagick python-minimal",
      "sudo npm install pm2@latest -g",
    ]

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  # Security Monitoring Software and Dependencies
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get install nagios-nrpe-server libnagios-plugin-perl nagios-plugins libsys-statistics-linux-perl -y",
      "sudo sed -i -e 's/allowed_hosts=127.0.0.1/allowed_hosts=127.0.0.1,192.99.99.97/' /etc/nagios/nrpe.cfg",
      "sudo echo 'command[check_users]=/usr/lib64/nagios/plugins/check_users -w 1 -c 2' >> /etc/nagios/nrpe.cfg",
      "sudo echo 'command[check_load]=/usr/lib64/nagios/plugins/check_load -w 5,5,5 -c 10,10,10' >> /etc/nagios/nrpe.cfg",
      "sudo echo 'command[check_hdhome]=/usr/lib64/nagios/plugins/check_disk -w 40% -c 30%' >> /etc/nagios/nrpe.cfg",
      "sudo echo 'command[check_procs]=/usr/lib64/nagios/plugins/check_procs -w 150 -c 200' >> /etc/nagios/nrpe.cfg",
      "sudo echo 'command[check_uptime]=/usr/lib64/nagios/plugins/check_uptime' >> /etc/nagios/nrpe.cfg",
      "sudo /etc/init.d/nagios-nrpe-server start",
      "sudo update-rc.d nagios-nrpe-server defaults",
      "sudo apt install snmpd -y",
      "sudo sed -i -e 's/agentAddress  udp:127.0.0.1:161/agentAddress  udp:161/' /etc/snmp/snmpd.conf",
      "sudo sed -i -e 's/#rocommunity public  localhost/rocommunity public 149.56.84.50/' /etc/snmp/snmpd.conf",
      "sudo sed -i -e 's/sysLocation    Sitting on the Dock of the Bay/sysLocation    Guadalajara, Jal, Mex./' /etc/snmp/snmpd.conf",
      "sudo sed -i -e 's/sysContact     Me <me@example.org>/sysContact     operations@sinergia.io/' /etc/snmp/snmpd.conf",
      "sudo iptables -I INPUT -p tcp -s 149.56.84.50 -j ACCEPT",
      "sudo iptables -I OUTPUT -p tcp -d  149.56.84.50 -j ACCEPT",
      "sudo iptables -I INPUT -p udp -m udp --dport 161 -j ACCEPT",
      "sudo iptables -I INPUT -p udp -m udp --dport 162 -j ACCEPT",
      "sudo iptables-save ",
      "sudo service snmpd restart",
    ]

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /home/ubuntu/apps/tdc/source",
      "mkdir -p /home/ubuntu/apps/tdc/shared",
      "mkdir -p /home/ubuntu/apps/tdc/shared/uploads/${var.environment}",
      "ssh-keyscan -H 'gitlab.com' >> $HOME/.ssh/known_hosts",
      "ssh-keyscan -H 'github.com' >> $HOME/.ssh/known_hosts",
    ]

    connection {
      user        = "ubuntu"
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    source      = "./files/config.js"
    destination = "/home/ubuntu/apps/tdc/shared/config.js"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    content     = "${data.template_file.knexfile.rendered}"
    destination = "/home/ubuntu/apps/tdc/shared/knexfile.js"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    source      = "./files/sites-available.conf"
    destination = "/etc/nginx/sites-available/default"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    source      = "./files/nginx.conf"
    destination = "/etc/nginx/nginx.conf"

    connection {
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo service nginx restart",
    ]

    connection {
      user        = "ubuntu"
      port        = "12345"
      timeout     = "1m"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }
}

resource "aws_elb_attachment" "web-elb-attachment" {
  elb      = "${aws_elb.web.id}"
  instance = "${aws_instance.web.id}"
}

// Route 53
data "aws_route53_zone" "primary" {
  name = "debtcollective.org."
}

resource "aws_route53_record" "www" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name    = "debtcollective.org"
  type    = "A"

  alias {
    name                   = "${aws_elb.web.dns_name}"
    zone_id                = "${aws_elb.web.zone_id}"
    evaluate_target_health = false
  }
}

// ECS instance_profile and iam_role
module "ecs_role" {
  source = "./modules/utils/ecs_role"
}

// key_pair for Metabase cluster
resource "aws_key_pair" "metabase" {
  key_name   = "metabase-tdc"
  public_key = ""
}

// Creates Metabase ECS
module "metabase" {
  source      = "github.com/hashlabs/angostura//modules/aws/compute/services/metabase"
  environment = "${var.environment}"

  db_username = "${var.db_username}"
  db_password = "${var.db_password}"
  db_host     = "${aws_db_instance.postgres.address}"
  db_port     = "${aws_db_instance.postgres.port}"
  db_name     = "metabase"

  key_name                = "${aws_key_pair.metabase.key_name}"
  iam_instance_profile_id = "${module.ecs_role.instance_profile_id}"
  subnet_ids              = ["${module.vpc.public_subnet_ids}"]
  security_groups         = ["${module.vpc.ec2_security_group_id}"]
  asg_min_size            = 1
  asg_max_size            = 1
}

/*
 * Outputs
 */
output "ec2_ip" {
  value = "${aws_eip.web.public_ip}"
}

output "elb_url" {
  value = "${aws_elb.web.dns_name}"
}

output "database_url" {
  value = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/debtcollective_prod"
}

output "postgres_address" {
  value = "${aws_db_instance.postgres.address}"
}
