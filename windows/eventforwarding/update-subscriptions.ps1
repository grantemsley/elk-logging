[CmdletBinding()]
Param()
# This script installs/updates subscriptions from the subscriptions folder, removing existing ones with the same name if needed
# Sometimes this makes Windows Event Collector service crash...
# Bulk disabling or deleting from the event viewer interface does the same thing.
# In fact, sometimes it breaks it so badly restarting the services doesn't fix it.  Somehow screws up the SDDL for wsman

# If you see a bunch of event id 10128 and/or 10129 in the System log on the collector, running these commands fixes that:
#
# netsh http delete urlacl url=http://+:5985/wsman/
# netsh http add urlacl url=http://+:5985/wsman/ sddl=D:(A;;GX;;;S-1-5-80-569256582-2953403351-2909559716-1301513147-412116970)(A;;GX;;;S-1-5-80-4059739203-877974739-1245631912-527174227-2996563517)
# 
# Then restart the event collector service

# Since the service is so unstable when deleting and recreating all the subscriptions, this script goes to great lengths to identify which subscriptions have changed, and only replacing those ones.

[Reflection.Assembly]::LoadWithPartialName("System.Xml.Linq") | Out-Null

Get-ChildItem .\subscriptions -Filter *.xml | Foreach-Object {

    [xml]$new = Get-Content $_.FullName
    $SubscriptionId = $new.subscription.SubscriptionId
    
    # Check if the subscription already exists
    $e = wecutil gs $SubscriptionId /f:xml 2>&1
    
    # wecutil will set an error code if the subscription didn't exist
    if ($LASTEXITCODE -eq 0) {
        [xml]$existing = $e
        
        $different = @()
        # Compare the nodes that we actually care about
        if ($new.subscription.SubscriptionId -ne $existing.subscription.SubscriptionId) { $different += "SubscriptionID" }
        if ($new.subscription.SubscriptionType -ne $existing.subscription.SubscriptionType) { $different += "SubscriptionType" }
        if ($new.subscription.Description -ne $existing.subscription.Description) { $different += "Description" }
        if ($new.subscription.Enabled -ne $existing.subscription.Enabled) { $different += "Enabled" }
        if ($new.subscription.ConfigurationMode -ne $existing.subscription.ConfigurationMode) { $different += "ConfigurationMode" }
        if ($new.subscription.Delivery.Mode -ne $existing.subscription.Delivery.Mode) { $different += "DeliveryMode" }
        if ($new.subscription.Delivery.Batching.MaxItems -ne $existing.subscription.Delivery.Batching.MaxItems) { $different += "MaxItems" }
        if ($new.subscription.Delivery.Batching.MaxLatencyTime -ne $existing.subscription.Delivery.Batching.MaxLatencyTime) { $different += "MaxLatencyTime" }
        if ($new.subscription.Delivery.PushSettings.Heartbeat.Interval -ne $existing.subscription.Delivery.PushSettings.Heartbeat.Interval) { $different += "Heartbeat" }
        if ($new.subscription.ReadExistingEvents -ne $existing.subscription.ReadExistingEvents) { $different += "ReadExistingEvents" }
        if ($new.subscription.TransportName -ne $existing.subscription.TransportName) { $different += "TransportName" }
        if ($new.subscription.ContentFormat -ne $existing.subscription.ContentFormat) { $different += "ContentFormat" }
        if ($new.subscription.Locale.Language -ne $existing.subscription.Locale.Language) { $different += "Language" }
        if ($new.subscription.LogFile -ne $existing.subscription.LogFile) { $different += "LogFile" }
        if ($new.subscription.AllowedSourceNonDomainComputers -ne $existing.subscription.AllowedSourceNonDomainComputers) { $different += "AllowedSourceNonDomainComputers" }
        if ($new.subscription.AllowedSourceDomainComputers -ne $existing.subscription.AllowedSourceDomainComputers) { $different += "AllowedSourceDomainComputers" }

        # Query has to be handled specially - even if the XML is the same, there's usually spacing differences between the xml file and the exported subscription
        # [System.Xml.Linq.XDocument] can parse and compare XML easily. There's no native powershell way to do it that I've found, but powershell has the full power of .NET under the hood.

        $newquery = [System.Xml.Linq.XDocument]::Parse($new.subscription.Query.InnerText)
        $existingquery = [System.Xml.Linq.XDocument]::Parse($existing.subscription.Query.InnerText)
        if ([System.Xml.Linq.XDocument]::DeepEquals($newquery, $existingquery) -ne $True) { $different += "Query" }
    
        if ($different) {
            Write-Host -NoNewLine "Settings for $SubscriptionId have changed: "
            $different -join ', '
            
            Write-Host "Disabling and deleting existing subscription $SubscriptionId"
            wecutil ss /e:false $SubscriptionId
            # Giving it a couple seconds can't hurt stability
            Start-Sleep 2
            wecutil ds $SubscriptionId
            Start-Sleep 2
            Write-Host "Creating updated subscription from $($_.BaseName)"
            wecutil cs $_.FullName
        } else {
            Write-Verbose "$SubscriptionId is unchanged, skipping"
        }
    } else {
        Write-Host "Subscription $SubscriptionId does not exist, creating from $($_.BaseName)"
        wecutil cs $_.FullName
    }
}