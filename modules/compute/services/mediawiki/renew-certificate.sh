#!/bin/bash

sudo /opt/bitnami/ctlscript.sh stop apache
sudo /usr/local/bin/lego --email="orlando@hashlabs.com" --domains="${domain}" --path="/etc/lego" renew
sudo /opt/bitnami/ctlscript.sh start apache
