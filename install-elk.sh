#!/bin/bash
# Installs and configures full ELK Stack

# Make sure we stop on any error - also makes it easier to stop the entire script by exiting with an error code from a function
set -euo pipefail

cd "${0%/*}"

main () {
    preflight_checks
    configure
    if [ "$NODETYPE" == "ImportOnly" ]; then
        load_index_templates
        load_kibana_data
    else
	    status "Creating $NODETYPE ELK node"
        install_packages
        configure_elasticsearch
        configure_apache
        configure_curator
        configure_logstash
        configure_firewall
    
        # On standalone nodes, or the last node in a cluster, load the index templates, kibana spaces, and configure curator
        # Only has to be done on one node - index templates and kibana data are stored in elasticsearch for the entire cluster
        if [ "$NODETYPE" == "Standalone" -o "$NODETYPE" == "LastNode" ]; then
            start_elasticsearch
            load_index_templates
            start_kibana
            load_kibana_data
        fi
        start_services
    fi
    status "Done!"
}

status () {
    printf -- "\033[32m%s\033[0m\n" "$1"
}
info () {
    printf -- "\033[37m  %s\033[0m\n" "$1"
}
error () {
    printf -- "\033[31mError: %s\033[0m\n" "$1"
    exit 1
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
    fi
    status "Preflight checks passed"
}

configure () {
    WIDTH=$(($(tput cols) - 20))
    HEIGHT=$(($(tput lines) / 2))

    get_nodetype
    if [ "$NODETYPE" == "ClusterNode" -o "$NODETYPE" == "LastNode" ]; then
        get_clustername
        get_hosts
    fi

    echo "#################################################################"
    echo "Ready to build elasticsearch node with these settings:"
    echo " "
    echo "           Node type: $NODETYPE"
    if [ "$NODETYPE" != "Standalone" -a "$NODETYPE" != "ImportOnly" ]; then
        echo "        Cluster name: $CLUSTERNAME"
        echo "          Node count: $NODECOUNT"
        echo "Minimum master nodes: $MINIMUMMASTERS"
        echo "               Hosts: ${HOSTS[@]}"
    fi
    echo " "
    echo "#################################################################"

    read -p "Proceed with these settings? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Installation canceled"
        exit 1
    fi
}

get_nodetype () {
    NODETYPE=$(whiptail --title "ELK Setup" --menu "What type of server do you want to build?" 0 0 10 \
        "Standalone" "     A single ELK server" \
        "ClusterNode" "     A node in a cluster - skips importing data to ElasticSearch" \
        "LastNode" "     The last node in a cluster - waits for the cluster to form and imports data" \
	    "ImportOnly" "     Just import templates and spaces to existing cluster (if you forgot to use LastNode for the final node)" \
        3>&1 1>&2 2>&3) || error "Installation canceled"
}

get_clustername () {
    CLUSTERNAME=$(whiptail --title "ELK Setup" --inputbox "Enter the cluster name:" 0 0 "elk-logging" 3>&1 1>&2 2>&3) || error "Installation canceled"

    if [ -z "$CLUSTERNAME" ]; then
        error "Cluster name can not be empty"
    fi
}

get_hosts () {
    HOSTIP=$(hostname -I)
    HOSTSSTRING=$(whiptail --title "ELK Setup" --inputbox "List the IP addresses of all the hosts in the cluster, including this one, separated by spaces:" 0 0 "$HOSTIP" 3>&1 1>&2 2>&3) || error "Installation canceled"
    if [ -z "$HOSTSSTRING" ]; then
        error "You must specify the IP addresses of the hosts in the cluster"
    fi

    IFS=', ' read -r -a HOSTS <<< "$HOSTSSTRING"
    NODECOUNT=${#HOSTS[@]}
    if [ $NODECOUNT -lt 3 ]; then
        error "You must have at least 3 nodes to prevent split-brain problems. If you want a single node, choose Standalone."
    fi
    # Calculate how many nodes needed to make a quorum - has to be >50% of nodes or split brain can occur, where two isolated groups of nodes have different masters and diverge from each other.
    # Only needed in elasticsearch 6.x - 7.0 replaces it with cluster.initial_master_nodes
    MINIMUMMASTERS=$(($NODECOUNT / 2 + 1 ))

}

install_packages () {
    status "Configuring elasticsearch package sources"
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - > /dev/null 2>&1
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
    while [ $(curl --write-out %{http_code} --silent --output /dev/null http://localhost:9200/cluster/health) != 200 ]; do
        info "Waiting for elasticsearch to start... check for errors in /var/log/elasticsearch/ if stuck here"
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
    while [ $(curl -L --write-out %{http_code} --silent --output /dev/null http://localhost:5601) != 200 ]; do
        info "Waiting for kibana to start..."
        sleep 2
    done
}

configure_elasticsearch () {
    status "Configuring elasticsearch as $NODETYPE node"

    echo "node.name: \${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml
    echo "xpack.monitoring.collection.enabled: true" >> /etc/elasticsearch/elasticsearch.yml

    if [ "$NODETYPE" == "Standalone" ]; then
        echo "network.host: localhost" >> /etc/elasticsearch/elasticsearch.yml
    else
        echo "network.host: [ _local_, _site_ ]" >> /etc/elasticsearch/elasticsearch.yml
        echo "cluster.name: $CLUSTERNAME" >> /etc/elasticsearch/elasticsearch.yml
        echo "discovery.zen.ping.unicast.hosts:" >> /etc/elasticsearch/elasticsearch.yml
        for i in "${HOSTS[@]}"; do
            echo "  - $i" >> /etc/elasticsearch/elasticsearch.yml
        done
	fi

    # Find the elasticsearch version. 6.x needs discovery.zen.minimum_master_nodes, 7.x needs cluster.initial_master_nodes
    ESVERSION=$(dpkg-query --showformat='${Version}' --show elasticsearch | cut -d "." -f1)
    if [ "$ESVERSION" -eq 7 ]; then
        echo "cluster.initial_master_nodes: " >> /etc/elasticsearch/elasticsearch.yml
        for i in "${HOSTS[@]}"; do
            echo "  - $i" >> /etc/elasticsearch/elasticsearch.yml
        done
    else
        echo "discovery.zen.minimum_master_nodes: $MINIMUMMASTERS" >> /etc/elasticsearch/elasticsearch.yml
    fi
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

load_kibana_data () {
    status "Importing kibana spaces and saved objects"
    /usr/bin/python3 ./kibana/import-spaces.py
}

configure_curator () {
    status "Configure curator to indices older than 60 days at 2:30am every Sunday"
    if [ ! -d /etc/curator ]; then
        mkdir /etc/curator
    fi
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
    if [ "$NODETYPE" != "Standalone" ]; then
        info "Allow elasticsearch from other cluster members"
        for i in "${HOSTS[@]}"; do
            ufw allow from $i to any app elasticsearch
        done
    fi
    ufw --force enable
}

start_services () {
    status "Enable and start services"
    systemctl daemon-reload
    systemctl enable logstash.service > /dev/null
    systemctl enable kibana.service > /dev/null
    systemctl enable elasticsearch.service > /dev/null
    systemctl start elasticsearch
    systemctl start kibana
    systemctl start logstash
    systemctl start apache2
}

main

