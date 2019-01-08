#!/bin/bash

# Takes advantage of the fact that my systems are already domain joined using sssd for authentication against AD, and already limited to appropriate user groups
# We'll create a certificate signing request to be signed by a remote CA, and configure Apache to use PAM authentication.

if [ -e "/etc/ssl/private/webserver.crt" ]; then
    echo "/etc/ssl/private/webserver.crt already exists. Don't want to overwrite existing certificate. Exiting"
    exit 1
fi


echo "Installing Apache PAM authentication module" 
apt-get -qq install libapache2-mod-authnz-pam > /dev/null
a2enmod ssl > /dev/null
a2enmod rewrite > /dev/null
a2enmod authnz_pam > /dev/null

# Setup the PAM service to require pam_sss.so authentication
echo "auth	required	pam_sss.so" > /etc/pam.d/kibana
echo "account	required	pam_sss.so" >> /etc/pam.d/kibana

# Replace apache config with the secure version
cp ./apache2/kibana_secure.conf /etc/apache2/sites-available/kibana.conf

openssl genrsa -out /etc/ssl/private/webserver.key 2048
cat << _EOF_ > /etc/ssl/private/config.txt
[req]
prompt = no
distinguished_name = req_distinguished_name
[req_distinguished_name]
CN=$(hostname -f)
[x509v3_DNS]
subjectAltName=critical,DNS:$(hostname -f)
_EOF_
openssl req -new -key /etc/ssl/private/webserver.key -out /etc/ssl/private/webserver.csr -config /etc/ssl/private/config.txt -reqexts x509v3_DNS

echo "Your certificate request:"
echo
echo
cat /etc/ssl/private/webserver.csr
echo
echo
echo "Submit the certificate at https://<windows CA server>/certsrv"
echo "Then download the BASE64 encoded certificate and paste it's contents into /etc/ssl/private/webserver.crt"
echo "and run 'service apache2 restart'"
