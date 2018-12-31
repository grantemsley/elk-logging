# Getting Event Logs from Windows to Elasticsearch

I'm using two methods of collecting the logs.  The first, installed on all domain controllers, is WinLogBeat. DCs have some of the most critical logs in them, and I want to make sure they get to ES quickly.

For all the other servers and workstations, I'm using Windows Event Forwarding. This has the advantage of not requiring any additional software, being configurable by group policy, and encrypting the data in transit.



## Configuring Windows Auditing

Before we can gather event logs, we need to make sure the important events are actually being logged.

### Group Policy
Create a group policy for auditing, and configure with the audit policies shown in the screenshots in the grouppolicy folder.

### SACL Entries

To actually audit some changes in active directory, you need to create SACL entries to tell AD to create the audit logs.

Open AD Users and Computers, turn on show advanced features, right click and select properties for the top of the domain (or for specific OUs, if that's all you are interested in).
Go to the Security tab, click Advanced. Go to Auditing tab. Click Add.

Select Everyone as the principal, type success, and applies to this object and all descendant objects. Then at the very bottom click clear all to remove the defaults, and check:

- Delete
- Delete subtree
- Modify owner
- Create Computer objects
- Delete Computer objects
- Create Contact objects
- Delete Contact objects
- Create Group objects
- Delete Group objects
- Create groupPolicyContainer objects
- Delete groupPolicyContainer objects
- Create Organizational Unit objects
- Delete Organizational Unit objects
- Create User objects
- Delete User objects

## Install WinLogBeats on Domain Controllers

There's a handy script in the winlogbeat folder.  In powershell, just run:

.\install-winlogbeat.ps1 -Computername <domaincontroller name> -LogStashServer <ip address of logstash server> -Config domaincontroller

## Configure Windows Event Forwarding

You need to setup a windows server that will collect all the events and forward them on to ElasticSearch.

The script setup-event-forwarding.ps1 can be run on the server to configure everything.