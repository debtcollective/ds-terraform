# Description

Mediawiki module creates a EC2 instance with [Bitnami Mediawiki image](https://docs.bitnami.com/aws/apps/mediawiki)

## Usage

```hcl
module "mediawiki" {
  source      = "./modules/compute/services/mediawiki"
  environment = "${var.environment}"

  key_name        = "${aws_key_pair.development.key_name}"
  subnet_id       = "${element(module.vpc.public_subnet_ids, 0)}"
  security_groups = "${module.vpc.ec2_security_group_id}"
}
```

## Setup steps

### Bootstrap

After the server is running, execute the `~/bootstrap.sh` file to finish the setup process.

### EBS snahpshots

Refer to this guide https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/TakeScheduledSnapshot.html

### Restore data from another installation

We need to restore database and uploads.

**uploads**: You can `rsync` the `images` folder like this

```bash
rsync -r -a -v -e ssh bitnami@<remote-ip>:~/apps/mediawiki/htdocs/images/ ~/apps/mediawiki/htdocs/images/
```

**database**: You can use `mysqldump` to make a database backup, and
then restore the backup in the new database

```bash
# Backup
mysqldump -u bitnami -p -B bitnami_mediawiki > backup.sql

# Restore
mysql -u bn_mediawiki -p < backup.sql
```
