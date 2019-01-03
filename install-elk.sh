#!/bin/bash
# Installs and configures full ELK Stack
set -e
cd "${0%/*}"

main () {
    preflight_checks
    install_packages
    configure_elasticsearch_standalone
    start_elasticsearch
    load_index_templates
    start_kibana
    configure_kibana
    configure_apache
    configure_logstash
    configure_curator
    configure_firewall
    start_services
    status "Done!"
}

status () {
    printf -- "\033[32m%s\033[0m\n" "$1"
}
info () {
    printf -- "\033[37m  %s\033[0m\n" "$1"
}
error () {
    printf -- "\031[37mError: %s\033[0m\n" "$1"
}

preflight_checks () {
    # Make sure this is a git repo
    if ! git rev-parse --dit-dir > /dev/null 2>&1; then
        error "This is not a git repository. Make sure you have cloned the git repository, not just downloaded this script."
        exit 1
    fi
    
    # Make sure we're running as root.
    if ! [ $(id -u) == 0 ]; then
        error "This script must be run as root."
        exit 1
    fi
}

install_packages () {
    status "Configuring elasticsearch package sources"
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
    apt-get -qq install apt-transport-https > /dev/null
    echo "deb https://artifacts.elastic.co/packages/6.x/apt stable main" > /etc/apt/sources.list.d/elastic-6.x.list
    echo "deb [arch=amd64] https://packages.elastic.co/curator/5/debian stable main" > /etc/apt/sources.list.d/elastic-curator-5.list
    apt-get -qq update
    
    # Use java 8 - newer versions not yet supported by logstash
    status "Installing OpenJDK 8"
    apt-get install -qq openjdk-8-jdk > /dev/null
    status "Installing the rest of the packages"
    apt-get install -qq apache2 elasticsearch kibana logstash elasticsearch-curator > /dev/null
}

# Starts elasticsearch and waits for it to be listening on localhost
start_elasticsearch () {
    status "Starting elasticsearch"
    systemctl start elasticsearch
    while [ $(curl --write-out %{http_code} --silent --output /dev/null http://localhost:9200/_cat/health?h=st) != 200 ]; do
        info "Waiting for elasticsearch to start..."
        sleep 2
    done
}

load_index_templates () {
    status "Loading all index templates"
    for filename in ./index-templates/*.json; do
        [ -e "$filename" ] || continue
        info "Loading $filename"
        basefile=$(basename $filename .json)
        curl -XPUT -H 'Content-Type: application/json' "http://localhost:9200/_template/$basefile" -d@$filename
    done
    echo
}

# Start kibana and wait for it to finish loading
start_kibana () {
    status "Starting kibana"
    systemctl start kibana
    while [ $(curl --write-out %{http_code} --silent --output /dev/null http://localhost:5601) != 200 ]; do
        info "Waiting for kibana to start..."
        sleep 2
    done
}

configure_elasticsearch_standalone () {
    status "Configuring elasticsearch"
    echo "network.host: localhost" >> /etc/elasticsearch/elasticsearch.yml
    echo "xpack.monitoring.collection.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
    echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml
}

configure_apache () {
    status "Configuring apache to reverse proxy kibana"
    a2enmod proxy > /dev/null
    a2enmod proxy_http > /dev/null
    a2dissite 000-default.conf > /dev/null
    cp ./apache2/kibana.conf /etc/apache2/sites-available/
    a2ensite kibana.conf > /dev/null
}

configure_logstash () {
    status "Configuing logstash"
    echo "queue.type: persisted" >> /etc/logstash/logstash.yml
    echo "xpack.monitoring.enabled: true" >> /etc/logstash/logstash.yml
    echo "xpack.monitoring.elasticsearch.url: ['http://localhost:9200']" >> /etc/logstash/logstash.yml
    cp -R ./logstash/* /etc/logstash/
    status "Downloading geoip database"
    wget --quiet http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz -O /etc/logstash/GeoLite2-City.mmdb.gz
    gunzip /etc/logstash/GeoLite2-City.mmdb.gz
}

configure_kibana () {
    status "Importing kibana spaces and saved objects"
    /usr/bin/python3 ./kibana/import-spaces.py
}

configure_curator () {
    status "Configure curator to indices older than 60 days at 2:30am every Sunday"
    mkdir /etc/curator
    cp ./curator/* /etc/curator/
    echo "30 2 * * 0 /usr/bin/curator --config /etc/curator/config.yml /etc/curator/delete_olderthan_60days.yml" > /etc/cron.d/curator
}

configure_firewall () {
    status "Configuring firewall"
    cp ./ufw/applications.d/* /etc/ufw/applications.d/
    info "Allow SSH"
    ufw allow OpenSSH > /dev/null
    info "Allow Apache"
    ufw allow "Apache Full" > /dev/null
    info "Allow logstash"
    ufw allow Logstash > /dev/null
    #info "Allow elasticsearch from other cluster members"
    #ufw allow from 192.168.0.50 to any app elasticsearch
    ufw --force enable
}

start_services () {
    status "Enable and start services"
    systemctl daemon-reload
    systemctl enable logstash.service > /dev/null
    systemctl enable kibana.service > /dev/null
    systemctl enable elasticsearch.service > /dev/null
    systemctl restart elasticsearch
    systemctl restart kibana
    systemctl restart logstash
    systemctl restart apache2
}

main
