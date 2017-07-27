/**
 *## Description:
 *
 *VPC module creates a VPC in the region used in the AWS provider with:
 *
 ** 1 Internet gateway
 ** 2 Public subnets (one in each availability zone)
 ** 2 Private subnets (one in each availability zone)
 ** 3 Security groups (elb, rds, ec2)
 ** VPC Subnet Group
 *
 *## Usage:
 *
 *```hcl
 *module "vpc" {
 *  source      = "../../modules/network/vpc"
 *  environment = "${var.environment}"
 *
 *  nat_gateway = false
 *}
 *```
 */

/*
 * Variables
 */
variable "environment" {
  description = "Environment name"
}

/*
 * Resources
 */
data "aws_region" "current" {
  current = true
}

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Name        = "vpc-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }
}

# Create Internet Gateway to by used by Public subnet
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name        = "ig-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }
}

# Create public subnet in AZ 1
resource "aws_subnet" "public_a" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_region.current.name}a"

  tags {
    Name        = "Public-a-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }
}

# Create public subnet in AZ 2
resource "aws_subnet" "public_b" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_region.current.name}b"

  tags {
    Name        = "Public-b-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }
}

# Create private subnet in AZ 1
resource "aws_subnet" "private_a" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_region.current.name}a"

  tags {
    Name        = "Private-a-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }
}

# Create private subnet in AZ 2
resource "aws_subnet" "private_b" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_region.current.name}b"

  tags {
    Name        = "Private-b-${var.environment}"
    Class       = "terraform"
    Environment = "${var.environment}"
  }
}

# Create a routing table for public subnets
# and hook the internet gateway to the outbound zone
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }
}

# Bind the public routing table to the public subnet AZ 1
resource "aws_route_table_association" "public_a" {
  subnet_id      = "${aws_subnet.public_a.id}"
  route_table_id = "${aws_route_table.public.id}"
}

# Bind the public routing table to the public subnet AZ 2
resource "aws_route_table_association" "public_b" {
  subnet_id      = "${aws_subnet.public_b.id}"
  route_table_id = "${aws_route_table.public.id}"
}

# Create a routing table for private subnets
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.default.id}"
}

# Bind the private routing table to the private subnet AZ 1
resource "aws_route_table_association" "private_a" {
  subnet_id      = "${aws_subnet.private_a.id}"
  route_table_id = "${aws_route_table.private.id}"
}

# Bind the private routing table to the private subnet AZ 2
resource "aws_route_table_association" "private_b" {
  subnet_id      = "${aws_subnet.private_b.id}"
  route_table_id = "${aws_route_table.private.id}"
}

# Create a security group for the elb servers
resource "aws_security_group" "elb" {
  name        = "elb_sg_${var.environment}"
  description = "security group for elb servers"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a security group for the app servers
resource "aws_security_group" "ec2" {
  name        = "ec2_security_group_${var.environment}"
  description = "security group for app servers"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 12345
    to_port     = 12345
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  ingress {
    from_port       = 32768
    to_port         = 61000
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  ingress {
    from_port       = 32768
    to_port         = 61000
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  # NRPE & SNMP for Security Monitoring
  ingress {
    from_port   = 5666
    to_port     = 5666
    protocol    = "tcp"
    cidr_blocks = ["192.99.99.97/32"]
  }

  ingress {
    from_port   = 161
    to_port     = 161
    protocol    = "tcp"
    cidr_blocks = ["149.56.84.50/32"]
  }

  ingress {
    from_port   = 5666
    to_port     = 5666
    protocol    = "udp"
    cidr_blocks = ["192.99.99.97/32"]
  }

  ingress {
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    cidr_blocks = ["149.56.84.50/32"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a security group for the rds servers
resource "aws_security_group" "rds" {
  name        = "rds_security_group_${var.environment}"
  description = "security group for databases"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ec2.id}"]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ec2.id}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/*
* Outputs
*/

// VPC ID
output "id" {
  value = "${aws_vpc.default.id}"
}

// EC2 Security group ID
output "ec2_security_group_id" {
  value = "${aws_security_group.ec2.id}"
}

// ELB Security group ID
output "elb_security_group_id" {
  value = "${aws_security_group.elb.id}"
}

// RDS Security group ID
output "rds_security_group_id" {
  value = "${aws_security_group.rds.id}"
}

// VPC Public subnet IDs
output "public_subnet_ids" {
  value = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]
}

// VPC Private subnet IDs
output "private_subnet_ids" {
  value = ["${aws_subnet.private_a.id}", "${aws_subnet.private_b.id}"]
}
