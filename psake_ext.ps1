$script_path = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
. "$script_path\teamcity.ps1"

# add 7-zip to the path
$env:path += ";$script_path\7zip"

# add included windows sdk tools to the build path
$env:path += ";$script_path\windows_sdk" # mage.exe is required for ClickOnce deployments

# print the environment variables used in this build
Write-Host "Environment Variables:"
Get-ChildItem Env: | Format-Table -AutoSize

# SUPPORTED BUILD PARAMETERS
#parameters {
#    [string]$deployment_target = $null                           # name of the deployment target to select by default
#}

# SUPPORTED BUILD PROPERTIES
properties {
    [string]$company_name = "WHO"                                  # used to generate the AssemblyInfo file and in ClickOnce deployments
    [string]$product_name = $null                                  # used to generate the AssemblyInfo file and name ZIP files and ClickOnce deployments
	[string]$product_desc = $null                                  # used to generate the AssemblyInfo file
    [string]$assembly_info_path = $null                            # path to save the AssemblyInfo file to
    $solution_path = $null                                         # path (or array of paths) to the solution or project to build

    [string]$checkout_path = (Get-CheckoutPath)
	[string]$build_path_rel = "@build"                             # path relative to the checkout_path
    [string]$build_path = "$checkout_path\$build_path_rel"         # build output will go here
    [string]$artifact_path_rel = "@artifacts"                      # path relative to the checkout_path
    [string]$artifact_path = "$checkout_path\$artifact_path_rel"   # artifacts will go here
    [string]$version = (Generate-VersionNumber)                    # application's version number
    [string]$info_version = (Generate-InfoVersion)                 # application's informational version number

    [string]$clickonce_cert_path = "$script_path\certs\WHO_AIM_Key.pfx" # path to the ClickOnce PFX cert file
	[string]$clickonce_cert_password = "happyGoLucky"              # password for the PFX cert file
	[bool]$clickonce_install = $false                              # specifies whether the ClickOnce app should install to the local machine or run from the deployment folder
	[string]$clickonce_trust_level = "FullTrust"                   # specifies the level of trust to grant the application on client computers. Values include "Internet", "LocalIntranet" and "FullTrust"

	[string]$primary_assembly_path = $null                         # path to the primary assembly that the version number, company & product name, etc should be pulled from
	[bool]$preserve_App_Data = $false                              # true/false whether to skip deleting the App_Data folder during deployments
	[string]$deploy_file_pattern = "deploy.*"				       # pattern that matches deployment scripts in the checkout path
    
    [array]$deploy_targets = @()                                   # an array of hashes that specify the deployment targets available
																   # example: $deploy_targets = @(
																   #                               @{
																   #                                  # REQUIRED, name of the target
																   #                                  "Name" = "Test";
																   #
																   #                                  # REQUIRED, UNC path where the file should be deployed
																   #                                  "Path" = "\\usws501\web\someapp\site\services";
																   #
																   #                                  # OPTIONAL, name of the server hosting the IIS website
																   #                                  # defaults to the server in the UNC path if left $null
																   #                                  "Server" = "usws501"
																   #
																   #                                  # OPTIONAL, name of the IIS website to start/stop during deployment
																   #                                  "Website" = "SomeApp";
																   #
																   #                                  # OPTIONAL, name of the IIS app pool to start/stop during deployment
																   #                                  "AppPool" = "SomeAppPool";
																   #
																   #                                  # OPTIONAL, name of the task(s) to run for target specific configuration
																   #                                  # This can also be an array of tasks to run. ex. "ConfigTask" = @("Task1", "Task2");
																   #                                  "ConfigTask" = "ConfigureForTest";
																   #
																   #                                  # OPTIONAL, name to use for the generated ClickOnce application
																   #                                  "ClickOnceName" = "SomeApp Services - Test";
																   #
																   #                                  # OPTIONAL, URL (or UNC path) where the ClickOnce application will be run from
																   #                                  # defaults to the "Path" value if left $null
																   #                                  "ClickOnceUrl" = $null;
																   #
																   #                                  # OPTIONAL, true/false whether to skip the backup when deploying the app
																   #                                  # defaults to false (by default a backup WILL be performed)
																   #                                  "SkipBackup" = $false;
																   #
																   #                                  # OPTIONAL, name of task(s) to run after the deployment is complete
																   #                                  # you might use this to set write permissions on some web directories
																   #                                  "PostDeployTask" = "SetTestPermissions"
																   #                                }
																   #                              )
}

formatTaskName {
	param($taskName)
	TeamCity-ReportBuildProgress "Executing $taskName"
}

#################################
##    BUILD RECIPES
#################################

task SimpleBuild -depends CompileSolution, AutoTest, BasePublishBuildOutput

task SimpleDeploy -depends BaseDeploy

#################################
##    COMMON BASE TASKS
#################################

task CompileSolution -depends BaseInit {    
	Assert ($solution_path -is [System.String] -or $solution_path -is [System.Array]) "solution_path property does not exist. this should point to the solution or project file you want to build."

    $solution_path | foreach { Invoke-MSBuild $_ }
	
	# if a website was built, we need to reorganize the build output
	Move-PublishedWebsiteBuildOutput
}

task BaseInit -depends BaseClean {
    Assert (-not([string]::IsNullOrEmpty($product_name))) "product_name property is required"
    Assert (-not([string]::IsNullOrEmpty($version))) "version property is required"
    Assert (-not([string]::IsNullOrEmpty($assembly_info_path))) "assembly_info_path property is required"

	Generate-AssemblyInfo `
        -file $assembly_info_path `
        -title $product_name `
        -description $product_desc `
        -product $product_name
    
    TeamCity-SetBuildNumber $version
    Write-Host "Info Version: $info_version"

	New-Item $build_path -ItemType directory | out-null
}

task BaseClean {
    if (Test-Path $build_path) { Remove-Item -Force -Recurse $build_path }
    if (Test-Path $artifact_path) { Remove-Item -Force -Recurse $artifact_path }
}

task AutoTest {
    Invoke-NUnitRunner $build_path
}

task BasePublishBuildOutput {
    Publish-BuildOutput
}


# Runs the ConfigTask specified in the deployment options
# Always performs a backup of the destination path before deploying new files
# Supports xcopy style deployments
# Supports starting/stopping the IIS Website and AppPool during the deployment.
# Supports basic ClickOnce deployments
task BaseDeploy {
    Assert (Test-Path $build_path) "build_path does not exist. nothing to publish."
    Assert ($deploy_targets -is [array] -and $deploy_targets[0] -is [hashtable]) "deploy_targets does not exist or is invalid. you must specify deployment targets."

	Write-Host "Primary Assembly Path: $primary_assembly_path"
	Assert (Test-Path $primary_assembly_path) "`$primary_assembly_path property does not exist or path not found. This is required for deployments."

	Set-TeamCityDeploymentBuildNumber
    
    # prompt the user to select the target they want to deploy to
    $deployment_target = Select-DeploymentTarget
    
    Write-Host "Deployment Target: " $deployment_target.Name
    TeamCity-ReportBuildProgress ("Deploying to " + $deployment_target.Name)
	
    # assert that the deployment target has all of its required parts
    Assert (-not([string]::IsNullOrEmpty($deployment_target.Path))) "the deployment target's Path is required"
    
    # run the custom configuration for this target
    if ($deployment_target.ConfigTask -ne $null) {
        $deployment_target.ConfigTask | where { $_ -is [string] -and [string]::IsNullOrEmpty($_) -eq $false } | foreach { Invoke-Task $_ }
    }
    
    # generate the ClickOnce manifest and application if needed
    $clickonce_app_path = $null
    $deployment_version = (Get-FileVersionInfo).FileVersion
    $is_clickonce = $false
    if (-not([string]::IsNullOrEmpty($deployment_target.ClickOnceName))) {
        Write-Host "ClickOnce deployment detected"
        $is_clickonce = $true
			
        Generate-ClickOnceManifest -Name $deployment_target.ClickOnceName `
                                   -FromDirectory $build_path `
                                   -Version $deployment_version

        # default the provider url to the deployment path if a specific ClickOnce URL is not provided
        # the provider url is where the end-user will run the ClickOnce application from
        $provider_url = $deployment_target.ClickOnceUrl
        if ([string]::IsNullOrEmpty($provider_url)) {
            $provider_url = $deployment_target.Path
        }

        $clickonce_app_path = "$build_path\" + [System.IO.Path]::GetFileNameWithoutExtension($primary_assembly_path) + ".application"
        Generate-ClickOnceDeployment -Name $deployment_target.ClickOnceName `
                                     -File $clickonce_app_path `
                                     -ProviderUrl $provider_url `
                                     -Version $deployment_version `
									 -MapFileExtensions $true
		
		# append the .deploy extension so the web deployments will work correctly
		Write-Host "Appending .deploy extension to all files that don't already have it."
		Get-ChildItem -Path $build_path -Recurse -Exclude "*.deploy", "*.manifest", "*.application" `
			| where { $_ -is [IO.FileInfo] } `
			| foreach { Move-Item $_.FullName $($_.FullName + ".deploy") }
    }
    
    # try to parse the IIS server name from the deployment_path if it wasn't already specified
    if ($deployment_target.Server -eq $null) {
        $deployment_target.Path -match "^\\\\(?<server>[^\\/\s]+)\\" | out-null
        if ($matches -ne $null) {
            $deployment_target.Server = $matches["server"]
        }
    }
    
    # stop the IIS website and app pool if applicable
    if (-not([string]::IsNullOrEmpty($deployment_target.Server))) {
        if (-not([string]::IsNullOrEmpty($deployment_target.Website))) {
            Stop-IIS6WebSite -Name $deployment_target.Website -ComputerName $deployment_target.Server
        }
        if (-not([string]::IsNullOrEmpty($deployment_target.AppPool))) {
            Stop-IIS6AppPool -Name $deployment_target.AppPool -ComputerName $deployment_target.Server
        }
    }
    
    $deploy_to_path = $deployment_target.Path
    if ($is_clickonce) {
        # if this is a ClickOnce deployment
        # publish to a /{version} sub-directory
        $deploy_to_path = (Join-Path $deploy_to_path $deployment_version)
    }
    
    # publish the files to the deployment path (includes a backup of existing files)
	$skip_backup = $false
	if ($deployment_target.SkipBackup -is [bool]) {
		$skip_backup = $deployment_target.SkipBackup
	}
    Publish-Files -sourcePath $build_path -targetPath $deploy_to_path -skipBackup $skip_backup
    
    if ($is_clickonce) {
        # if this is a ClickOnce deployment
        # copy the .application file from the /{version} sub-directory into the parent directory
        $clickonce_app_filename = ([System.IO.Path]::GetFileName($clickonce_app_path))
        Deploy-ClickOnceDeploymentManifestToParentFolder (Join-Path $deploy_to_path $clickonce_app_filename)
    }
	
	# execute any post deployment tasks that have been specified
	if ($deployment_target.PostDeployTask -ne $null) {
        $deployment_target.PostDeployTask | where { $_ -is [string] -and [string]::IsNullOrEmpty($_) -eq $false } | foreach { Invoke-Task $_ }
    }
    
    # restart the IIS website and app pool if applicable
    if (-not([string]::IsNullOrEmpty($deployment_target.Server))) {
        if (-not([string]::IsNullOrEmpty($deployment_target.Website))) {
            Start-IIS6WebSite -Name $deployment_target.Website -ComputerName $deployment_target.Server
        }
        if (-not([string]::IsNullOrEmpty($deployment_target.AppPool))) {
            Start-IIS6AppPool -Name $deployment_target.AppPool -ComputerName $deployment_target.Server
        }
    }
}

#################################
##    HELPER FUNCTIONS
#################################
. "$script_path\build_helpers.ps1"
. "$script_path\config_helpers.ps1"
. "$script_path\deployment_helpers.ps1"
. "$script_path\iis_helpers.ps1"
. "$script_path\versioning_helpers.ps1"

function Get-CheckoutPath {
    $dir = [Environment]::GetEnvironmentVariable("teamcity.build.checkoutDir")
    if ($dir -eq $null -or $dir.length -eq 0) {
        $dir = Resolve-Path ./
    }
    return $dir.ToString().TrimEnd(@('/', '\'))
}

function Invoke-7zip {
param(
    [array] $zipArgs = $(throw "zipArgs is a required parameter.")
)
   exec { & 7za.exe @zipArgs }
}