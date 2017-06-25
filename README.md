# debtcollective terraform

This is the terraform recipes we use to generate our production
environment.

## Installation

First you will need to install [Terraform](https://www.terraform.io/intro/getting-started/install.html). If you are on OSX use [Homebrew](https://brew.sh/) to do this. If you don't have homebrew installed, [install it first](https://brew.sh/)

```bash
brew install terraform
```

Then follow these steps to init your environment

1. `cp env.sample .env` and replace variables
2. `source .env`
3. `make init`

You need to have valid and with the permissions we need, AWS credentials before running step 3.

## Usage

When you are making a change, follow this loop

1. `make plan` to see your changes in memory
2. `make apply` to apply changes

`make apply` will also upload the `terraform.tfvars` file (that is
ignored from the git repository since it has sensible data). When you
run `make init` this file will be pulled from the remote.

If more than one person is modifying these files, you can make sure you
have the latest `terraform.tfvars` file by running `make tfvars-pull`.
This command will override your local `terraform.tfvars` file, and since
is not commited to git, you will lose your changes (if any)

## How-to

### Connect to the postgres database from your local instance
RDS databases are only reachable from an instance in the
ec2_security_group. You can connect to the database using an SSH tunnel

```bash
ssh -N -L 9998:<rds_address>:5432 ubuntu@<instance-ip> -p 12345
```

Then connect to the database using the tunnel

```bash
psql -h localhost -p 9998 -d debtcollective_prod -U debtcollective < backup.sql
```
