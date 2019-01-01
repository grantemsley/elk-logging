# This script sets up a server to act as a windows event collector


# Make sure WinRM is setup and running
Set-Service -Name winrm -StartupType Automatic
winrm quickconfig -quiet

# Increase the log size for forwarded events from the default 20MB to 500MB, so fewer events are lost if they can't be forwarded to elasticsearch right away
wevtutil sl forwardedevents /ms:512000000

# Run quick config for subscription service
wecutil qc -quiet