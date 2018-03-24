#!/bin/bash

# Stop server
echo "Stopping server"
sudo /opt/bitnami/ctlscript.sh stop

# Install LEGO
cd /tmp
curl -s https://api.github.com/repos/xenolf/lego/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4 | wget -i -
tar xf lego_linux_amd64.tar.xz
sudo mv lego_linux_amd64 /usr/local/bin/lego

# Run LEGO
echo "Running LEGO"
sudo lego --email="orlando@hashlabs.com" --domains="${domain}" --path="/etc/lego" run

# Move SSL certificates
sudo mv /opt/bitnami/apache2/conf/server.crt /opt/bitnami/apache2/conf/server.crt.old
sudo mv /opt/bitnami/apache2/conf/server.key /opt/bitnami/apache2/conf/server.key.old
sudo mv /opt/bitnami/apache2/conf/server.csr /opt/bitnami/apache2/conf/server.csr.old
sudo ln -s /etc/lego/certificates/${domain}.key /opt/bitnami/apache2/conf/server.key
sudo ln -s /etc/lego/certificates/${domain}.crt /opt/bitnami/apache2/conf/server.crt
sudo chown root:root /opt/bitnami/apache2/conf/server*
sudo chmod 600 /opt/bitnami/apache2/conf/server*

# Automate SSL renewal
sudo cp ~/renew-certificate.sh /etc/lego/renew-certificate.sh
sudo chmod +x /etc/lego/renew-certificate.sh
(crontab -u bitnami -l ; echo "0 0 1 * * /etc/lego/renew-certificate.sh 2> /dev/null") | crontab -u bitnami -

# Remove values in LocalSettings.php
# We are removing whole lines to replace the values at the bottom of the file
sed -e '/^\$wgEmergencyContact/ d; /^\$wgPasswordSender/ d; /^\$wgSitename/ d; /^\$wgMetaNamespace/ d; /^\$wgLogo/ d' /opt/bitnami/apps/mediawiki/htdocs/LocalSettings.php

# Enable SES for emails
sudo cat <<EOT >> /opt/bitnami/apps/mediawiki/htdocs/LocalSettings.php
# Our configuration
\$wgSMTP = array(
  'host' => '${smtp_host}',
  'IDHost' => '${domain}',
  'port' => ${smtp_port},
  'username' => '${smtp_user}',
  'password' => '${smtp_pass}',
  'auth' => true
);
\$wgEmergencyContact = "${admin_email}";
\$wgPasswordSender   = "${admin_email}"
\$wgSitename      = "${sitename}";
\$wgMetaNamespace = "${sitename}";
\$wgLogo = "$wgScriptPath/resources/assets/dc.png";
EOT

# HTTPS redirect
sudo cp ~/httpd-prefix.conf /opt/bitnami/apps/mediawiki/conf/httpd-prefix.conf

# Start Server
echo "Starting server"
sudo /opt/bitnami/ctlscript.sh start
echo "Completed"
