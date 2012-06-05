<#
.Synopsis
Checks that WMI is available and IIS6 installed
#>
function Assert-II6Support
{
    try
    {
	   [wmiclass] 'root/MicrosoftIISv2:IIsWebServer' > $null
    }
    catch
	{
		Write-Error "The IIS WMI Provider for II6 does not appear to be installed"
	}
}

<#
.Synopsis
Starts the website
#>
function Start-IIS6WebSite
{
    param
    (
        [string] $Name = $(throw "Must provide a website name"),
        [string] $ComputerName
    )

    #Assert-II6Support

    $webServerSetting = Get-WmiObject -Namespace 'root\MicrosoftIISv2' -Class IISWebServerSetting -Filter "ServerComment = '$Name'" -ComputerName $ComputerName -Authentication PacketPrivacy
    
    if ($webServerSetting)
    {
		TeamCity-ReportBuildProgress "Starting IIS Website `"$Name`""
        $webServers = Get-WmiObject -Namespace 'root\MicrosoftIISv2' -Class IIsWebServer -ComputerName $ComputerName -Authentication PacketPrivacy
        $targetServer = $webServers | Where-Object { $_.Name -eq $webServerSetting.Name }
        $targetServer.Start()
        
		TeamCity-ReportBuildProgress "Website started"
    }
    else
    {
        throw "Could not find website '$Name' to start"
    }
}

<#
.Synopsis
Starts the website
#>
function Stop-IIS6WebSite
{
    param
    (
        [string] $Name = $(throw "Must provide a website name"),
        [string] $ComputerName
    )

    Assert-II6Support

    $webServerSetting = Get-WmiObject -Namespace 'root\MicrosoftIISv2' -Class IISWebServerSetting -Filter "ServerComment = '$Name'" -ComputerName $ComputerName -Authentication PacketPrivacy
    
    if ($webServerSetting)
    {
		TeamCity-ReportBuildProgress "Stopping IIS Website `"$Name`""
        $webServers = Get-WmiObject -Namespace 'root\MicrosoftIISv2' -Class IIsWebServer -ComputerName $ComputerName -Authentication PacketPrivacy
        $targetServer = $webServers | Where-Object { $_.Name -eq $webServerSetting.Name }
        $targetServer.Stop()
        
		TeamCity-ReportBuildProgress "Website stopped"
    }
    else
    {
        throw "Could not find website '$Name' to stop"
    }
}

<#
.Synopsis
Starts the app pool
#>
function Start-IIS6AppPool
{
    param
    (
        [string] $Name = $(throw "Must provide an app pool name"),
        [string] $ComputerName
    )
    
    Assert-II6Support
    
	$appPool = Get-WmiObject -Namespace "root\MicrosoftIISv2" -class IIsApplicationPool -Filter "Name ='W3SVC/APPPOOLS/$Name'" -ComputerName $ComputerName -Authentication PacketPrivacy

    if ($appPool)
    {
		TeamCity-ReportBuildProgress "Starting IIS AppPool `"$Name`""
        $appPool.Start()
		TeamCity-ReportBuildProgress "AppPool started"
    }
    else
    {
        throw "Could not find application pool '$Name' to start"
    }
}


<#
.Synopsis
Stops the app pool
#>
function Stop-IIS6AppPool
{
    param
    (
        [string] $Name = $(throw "Must provide an app pool name"),
        [string] $ComputerName
    )
    
    Assert-II6Support
    
	$appPool = Get-WmiObject -Namespace "root\MicrosoftIISv2" -class IIsApplicationPool -Filter "Name ='W3SVC/APPPOOLS/$Name'" -ComputerName $ComputerName -Authentication PacketPrivacy
    
	if ($appPool)
    {
		TeamCity-ReportBuildProgress "Stopping IIS AppPool `"$Name`""
        $appPool.Stop()
		TeamCity-ReportBuildProgress "AppPool stopped"
    }
    else
    {
        throw "Could not find application pool '$Name' to stop"
    }
}