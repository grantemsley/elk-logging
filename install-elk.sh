#!/bin/bash
# Installs and configures full ELK Stack
set -e

# Functions to print text in color
status () {
	printf -- "\033[32m%s\033[0m\n" "$1"
}
info () {
	printf -- "\033[37m  %s\033[0m\n" "$1"
}

status "Cloning git repo to /root/elk-logging"
git clone https://github.com/grantemsley/elk-logging.git /tmp/elk-logging

status "Configuring elasticsearch package sources"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
apt-get install apt-transport-https
echo "deb https://artifacts.elastic.co/packages/6.x/apt stable main" > /etc/apt/sources.list.d/elastic-6.x.list
echo "deb [arch=amd64] https://packages.elastic.co/curator/5/debian stable main" > /etc/apt/sources.list.d/elastic-curator-5.list
apt-get update

# Use java 8 - newer versions not yet supported by logstash
status "Installing packages"
apt-get install -qq openjdk-8-jdk 
apt-get install -qq apache2
apt-get install -qq apache2 elasticsearch kibana logstash elasticsearch-curator

status "Configuring elasticsearch"
echo "network.host: localhost" >> /etc/elasticsearch/elasticsearch.yml
echo "xpack.monitoring.collection.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml

status "Starting elasticsearch"
systemctl start elasticsearch
while [ $(curl --write-out %{http_code} --silent --output /dev/null http://localhost:9200/_cat/health?h=st) != 200 ]; do
	info "Waiting for elasticsearch to start..."
	sleep 2
done

status "Loading all index templates"
for filename in /root/elk-logging/index-templates/*.json; do
	info "Loading $filename"
	basefile=$(basename $filename .json)
	curl -XPUT -H 'Content-Type: application/json' "http://localhost:9200/_template/$basefile" -d@$filename
done

status "Configuring apache to reverse proxy kibana"
a2enmod proxy
a2enmod proxy_http
a2dissiste 000-default.conf
cp /root/elk-logging/apache2/kibana.conf /etc/apache2/sites-available/
a2ensite kibana.conf

status "Configuing logstash"
echo "queue.type: persisted" >> /etc/logstash/logstash.yml
echo "xpack.monitoring.enabled: true" >> /etc/logstash/logstash.yml
echo "xpack.monitoring.elasticsearch.url: ['http://localhost:9200']" >> /etc/logstash/logstash.yml
cp -R /root/elk-logging/logstash/* /etc/logstash/

status "Downloading geoip database"
wget --quiet http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz -O /etc/logstash/GeoLite2-City.mmdb.gz
gunzip /etc/logstash/GeoLite2-City.mmdb.gz


status "Configure curator to indices older than 60 days at 2:30am every Sunday"
mkdir /etc/curator
cp /root/elk-logging/curator/* /etc/curator/
echo "30 2 * * 0 /usr/bin/curator --config /etc/curator/config.yml /etc/curator/delete_olderthan_60days.yml" > /etc/cron.d/curator





status "Enable and start services"
systemctl daemon-reload
systemctl enable logstash.service
systemctl enable kibana.service
systemctl enable elasticsearch.service
systemctl restart elasticsearch
systemctl restart kibana
systemctl restart logstash
systemctl restart apache2

status "Done!"
