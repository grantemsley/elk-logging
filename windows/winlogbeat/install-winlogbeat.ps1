param(
    [Parameter(Mandatory=$true)][string]$ComputerName,
    [Parameter(Mandatory=$true)][string]$Config,
    [Parameter(Mandatory=$true)][string]$LogStashServer
)

$winlogbeatversion = "6.5.4"
$ErrorActionPreference = "Stop"

function Download-WinLogBeat {
    mkdir .\download | Out-Null
    wget "https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-${winlogbeatversion}-windows-x86_64.zip" -OutFile .\download\winlogbeat.zip
    Expand-Archive .\download\winlogbeat.zip -DestinationPath .\download\
    # Remove some of the files we don't need
    rmdir -Recurse ".\download\winlogbeat-${winlogbeatversion}-windows-x86_64\kibana"
    rm ".\download\winlogbeat-${winlogbeatversion}-windows-x86_64\winlogbeat.yml"
}

# Check that the config file specified exists
$configfile = ".\config\${Config}.yml"
If (!(Test-Path $configfile)) {
    Write-Host "Invalid config file specified. Valid options are:"
    dir .\config -Filter *.yml| Select-Object -ExpandProperty basename
    exit 1
}

# Test that the C$ share on the remote computer is accessible
If(!(Test-Path "\\${ComputerName}\C$\Program Files")) {
    Write-Host "Unable to access C$ share on ${ComputerName}"
    exit 2
}

# Test that powershell remoting is setup on the remote computer
if(!(Test-WSMan -ComputerName $ComputerName -ErrorAction Ignore))
    Write-Host "Test-WSMan failed, unable to do powershell remoting to $ComputerName"
    exit 3
}

# Check if WinLogBeat exists, if not download it
If (!(Test-Path ".\download\winlogbeat-${winlogbeatversion}-windows-x86_64\winlogbeat.exe")) {
    Write-Host "Downloading WinLogBeat"
    Download-WinLogBeat
}

# Copy files to the remote computer
Write-Host "Copying files to remote computer"
#Copy-Item -Recurse ".\download\winlogbeat-${winlogbeatversion}-windows-x86_64\*" "\\${ComputerName}\c$\Program Files\winlogbeat"

# Edit config file and copy to the remote computer. Also make sure it has windows line endings
Write-Host "Generating config file"
$configfile = ".\config\${Config}.yml"
$config = Get-Content -Raw -Path $configfile
# Ensure the line endings are windows format, by converting them all to unix format, then back to windows.  Otherwise if it were already windows format you'd end up with `r`r`n
$config = $config -Replace "`r`n","`n"
$config = $config -Replace "`n", "`r`n"
$config -Replace "logstashserver", $LogStashServer | Out-File -FilePath "\\${ComputerName}\c$\Program Files\winlogbeat\winlogbeat.yml" -Encoding ascii

# Register it as a service
Write-Host "Registering service"
Invoke-Command -ComputerName $ComputerName -ScriptBlock { 
    New-Service -name winlogbeat `
     -displayName Winlogbeat `
     -binaryPathName '"C:\Program Files\winlogbeat\winlogbeat.exe" -c "C:\Program Files\winlogbeat\winlogbeat.yml" -path.home "C:\Program Files\winlogbeat" -path.data "C:\ProgramData\winlogbeat" -path.logs "C:\ProgramData\winlogbeat\logs"'
}

Write-Host "Starting service"
Invoke-Command -ComputerName $ComputerName -ScriptBlock {Start-Service -Name winlogbeat}
