# elk-logging
Various install scripts and configurations for logging with ELK stack

Resources used:
- http://pfelk.3ilson.com/
- https://www.syspanda.com/index.php/category/elasticsearch/
- https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/default.aspx

# Scripts

## install-elk.sh

This script installs and configures Elasticsearch, Logstash, and Kibana.

It also:
* Sets up apache2 as a reverse proxy for kibana
* Configures curator to delete indexes that are older than 60 days
* Configures firewall rules using ufw

Tested on Ubuntu 18.04

## kibana/import-spaces.py

This script creates spaces and imports data into them.  Kibana's API is...a work in progress.  As of 6.5.4, this script works, but it's using experimental APIs so it may break in the future.

Creating spaces is pretty easy.  In the spaces folder, create a subfolder (name doesn't matter).  In there, you need 2 files:

definition.json, which defines the space and looks like this:

{
    "id": "winauth",
    "name": "Windows Authentication",
    "description": "Authentication and security data",
    "color": "#e0f3a4",
    "initials": "WA"
}

And export.json, which is the file you download when you export all saved objects from a space using the web interface.

The export.json file automatically gets modified slightly to match what the API expects for importing objects.

## windows/winlogbeat/install-winlogbeat.ps1

Powershell script downloads and installs winlogbeat on remote servers using powershell remoting.  Different config files can be created in the config folder to be used for different machines.
The string logstashserver gets replaced with the address you specify in the script parameters for the logstash server.