# Getting Event Logs from Windows to Elasticsearch

I'm using two methods of collecting the logs.  The first, installed on all domain controllers, is WinLogBeat. DCs have some of the most critical logs in them, and I want to make sure they get to ES quickly.

For all the other servers and workstations, I'm using Windows Event Forwarding. This has the advantage of not requiring any additional software, being configurable by group policy, and encrypting the data in transit.


## Configuring Windows Auditing

Before we can gather event logs, we need to make sure the important events are actually being logged.

### Group Policy
Create a group policy for auditing, and configure with the audit policies shown in the screenshots in the grouppolicy folder.

If you don't want to monitor process creation, turn that one off - it's really noisy.  But you should monitor it.

In addition, a few other settings have to be set for event forwarding to work properly. This doesn't need to be applied to domain controllers, but it won't hurt them if it is.

- Computer -> Policies -> Windows Settings -> Security Settings -> Restricted Groups: Group BUILTIN\Event Log Readers, Members: NETWORK SERVICE
    This is needed to allow WinRM to access the security logs on the computers and forward them to the server. Without this, it won't have access to anything in the security log.
- Computer -> Policies -> Windows Settings -> Security Settings -> System Services: Windows Remote Magement, Startup Mode: Automatic
    The WinRM service has to be enabled for event forwarding to happen.  Even though we are using a push configuration where the server doesn't have to remotely access the workstations, WinRM service must be running.
- Computer -> Administrative Templates -> Windows Components -> Event Forwarding -> Configure target Subscription Manager:  Set the value to "Server=http://name-of-WEF-server.domain.name:5985/wsman/SubscriptionManager/WEC,Refresh=300"
    Enables event forwarding. The computers will check every 5 minutes for a list of subscriptions, which tells them which events they are supposed to be forwarding.

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

All the subscriptions are set to allow members of Domain Computers - which excludes all domain controllers, so we don't have to worry about not having the domain controllers apply the group policy, 
and won't end up with duplicate events from their own winlogbeat + event forwarding.