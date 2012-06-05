# used during deployments to set the Teamcity build number
# from the build_number.txt file that was created during the build
# or from the Get-FileVersionInfo function
function Set-TeamCityDeploymentBuildNumber {
param (
	[string] $buildNumber
)
	if ([string]::IsNullOrEmpty($buildNumber)) {
        
        if (Test-Path "$checkout_path\build_number.txt") {
            $buildNumber = (Get-Content "$checkout_path\build_number.txt" -TotalCount 1).Trim()
        }
        else {
		    $buildNumber = (Get-FileVersionInfo).FileVersion
        }
	}

	Assert (-not([string]::IsNullOrEmpty($buildNumber))) "No buildNumber was specified and `"$checkout_path\build_number.txt`" was not found."

	TeamCity-SetBuildNumber $buildNumber
}

# gets the version from the primary assembly that was created during the build
function Get-FileVersionInfo {
param (
    [string] $File = $primary_assembly_path
)
    Assert (Test-Path $File) "File path not found. [ `$File = $File ]"

    return (Get-Command $File).FileVersionInfo
}

# backs up the given path to a timestamped zip file
# in the parent directory
function Backup-PublishTarget {
param (
    [string]$path = $(throw "path is a required parameter")
)
    if (Test-Path $path) {
		TeamCity-ReportBuildProgress "Backing up $path"
		
        # get the parent folder path
        $parentPath = [System.IO.Directory]::GetParent($path).FullName
        
        $folderName = (New-Object System.IO.DirectoryInfo $path).Name
		$timestamp = [DateTime]::Now.ToString("yyyy-MM-ddTHH-mm-ss");
	
		# zip the existing program files
        Invoke-7zip "a", "-tzip", ("`"$parentPath\" + $folderName + "_$timestamp.bak.zip`""), "`"$path`""
		
		TeamCity-ReportBuildProgress "Backup completed"
    }
}

# backs up the targetPath and then copies all items
# from the sourcePath to the targetPath
function Publish-Files {
param (
    [string]$sourcePath = $(throw "sourcePath is a required parameter."),
    [string]$targetPath = $(throw "targetPath is a required parameter."),
	[bool]$skipBackup = $false
)	
    Assert (Test-Path $sourcePath) "sourcePath does not exist. nothing to publish."
    Assert ([string]::IsNullOrEmpty($targetPath) -eq $false) "targetPath cannot be null or empty."
    
    if (Test-Path $targetPath) {
		if ($skipBackup -eq $false) {
        	Backup-PublishTarget $targetPath
		} else {
			Write-Host "Skipping backup"
		}

    	# remove any existing files in the target path
		if ($preserve_App_Data) {
			Remove-Item "$targetPath\**" -Force -Recurse -Exclude "App_Data"
		} else {
			Remove-Item "$targetPath\**" -Force -Recurse
		}
    } else {
        New-Item $targetPath -ItemType directory | out-null   
    }

	# publish files from the source path
	TeamCity-ReportBuildProgress "Publishing files to $targetPath"
	Copy-Item $sourcePath\* $targetPath -Recurse
	
	TeamCity-ReportBuildProgress "Publish completed"
}

# prompts the user to select a deployment target
# and returns the selected target
# if a default was provided when the script launched
# then the default will be returned and the user
# will not be prompted
function Select-DeploymentTarget {
    $prompt = "`nChoose deployment target:"
    
    [array]$options = @()
    $deploy_targets | foreach { $options += @($_.Name) }
    
    if ($options.Length -eq 0) {
        throw "`$deploy_targets array must have at least 1 item"
    }

    $option_delimiter = "`n    -> "
    $options_prompt = $option_delimiter + [string]::Join($option_delimiter, $options)

    $selection = $deployment_target #deployment_target may have been passed into the script as a property or parameter
    while ($options -notcontains $selection) {
        $selection = Read-Host -prompt "`n$prompt$options_prompt`n >"
        
        $matches = $options | where { $_ -like "$selection*" }
        if ($matches -is [array] -and $matches.Length -eq 1) {
            $selection = $matches[0]
        } elseif ($matches -is [array] -and $matches.Length -gt 1) {
            Write-Warning "Your selection wasn't specific enough."
        } elseif ($matches -is [string]) {
            $selection = $matches
        } else {
            Write-Warning "No option matched your selection."
        }
    }

    return $deploy_targets | where { $_.name -eq $selection }
}

function Generate-ClickOnceManifest {
param(
    [string]$Name = $(throw "Name is a required parameter."),
    [string]$File = $($primary_assembly_path + ".manifest"),
    [string]$Version = $(throw "Version is a required parameter."),
    [string]$FromDirectory = $(throw "FromDirectory is a required parameter."),
    [string]$CertFile = $clickonce_cert_path,
	[string]$CertPassword = $clickonce_cert_password,
    [string]$Processor = "msil",
	[string]$TrustLevel = $clickonce_trust_level
)
	TeamCity-ReportBuildProgress "Generating ClickOnce application manifest"
	
    Assert (-not([string]::IsNullOrEmpty($File))) "File is a required parameter."
    Assert (-not([string]::IsNullOrEmpty($Version))) "Version is a required parameter."
    Assert (-not([string]::IsNullOrEmpty($FromDirectory)) -and (Test-Path $FromDirectory)) "FromDirectory does not exist. Unable to generate manifest."

    $mageArgs = @(
                    "-New", "Application",
                    "-Processor", "$Processor",
                    "-ToFile", "`"$File`"",
                    "-Name", "`"$Name`"",
                    "-Version", $Version,
                    "-FromDirectory", "`"$FromDirectory`"",
					"-TrustLevel", $TrustLevel
                 )

    if (-not([string]::IsNullOrEmpty($CertFile))) {
        $mageArgs += "-CertFile"
        $mageArgs += "`"$CertFile`""
    }
	
    if (-not([string]::IsNullOrEmpty($CertPassword))) {
        $mageArgs += "-Password"
        $mageArgs += "`"$CertPassword`""
    }

	Write-Host "mage.exe $mageArgs`n"
    exec { & mage.exe @mageArgs }
	
	TeamCity-ReportBuildProgress "Application manifest generated"
}

function Sign-ClickOnceManifest {
param (
	[string]$File = $(throw "File is a required parameter."),
    [string]$CertFile = $clickonce_cert_path,
	[string]$CertPassword = $clickonce_cert_password
)
	Assert (Test-Path $File -PathType Leaf) "Manifest file not found. [ `$File = $File ]"
	
	# resign the deployment if we are using a certificate
	if (-not([string]::IsNullOrEmpty($CertFile))) {
		$mageArgs = @(
						"-Sign",
						"`"$File`"",
        				"-CertFile",
        				"`"$CertFile`""
					 )
		
		if (-not([string]::IsNullOrEmpty($CertPassword))) {
	        $mageArgs += "-Password"
	        $mageArgs += "`"$CertPassword`""
    	}
		
		Write-Host "mage.exe $mageArgs`n"
		exec { & mage.exe @mageArgs }
    }
}

function Generate-ClickOnceDeployment {
param(
    [string]$Name = $(throw "Name is a required parameter."),
    [string]$File = $(throw "File is a required parameter."),
    [string]$Version = $(throw "Version is a required parameter."),
    [string]$Publisher = $((Get-FileVersionInfo).CompanyName),
    [string]$ProviderUrl = $(throw "ProviderUrl is a required parameter."),
    [string]$ManifestFile = $($primary_assembly_path + ".manifest"),
    [string]$CertFile = $clickonce_cert_path,
	[string]$CertPassword = $clickonce_cert_password,
    [string]$Processor = "msil",
	[bool]$Install = $clickonce_install, # specifies whether the ClickOnce app should install to the local machine or run from the deployment folder
	[bool]$MapFileExtensions = $false
)
	TeamCity-ReportBuildProgress "Generating ClickOnce deployment manifest"
	
    Assert (-not([string]::IsNullOrEmpty($ManifestFile))) "ManifestFile is a required parameter."
    Assert (-not([string]::IsNullOrEmpty($Version))) "Version is a required parameter."
    Assert (-not([string]::IsNullOrEmpty($Publisher))) "Publisher is a required parameter."
    Assert (Test-Path $ManifestFile) "ManifestFile does not exist. Cannot create ClickOnce deployment."

	# if provider url is a UNC or local path, just append on the filename
	$ProviderUrl -match "^(http|https):\\\\" | out-null
    if ($matches -ne $null) {
        # trim any trailing slashes off the URL and append on the file name
		$ProviderUrl = $ProviderUrl.Trim(@('/', '\')) + "/" + $([IO.Path]::GetFileName($File))
    } else {
		# if the provider URL wasn't a URL, then assume it was a UNC or local drive path
		$ProviderUrl = (Join-Path $ProviderUrl $([IO.Path]::GetFileName($File)))
	}

    $mageArgs = @(
                    "-New", "Deployment",
                    "-Processor", "$Processor",
                    "-Install", $Install.ToString().ToLower(),
                    "-Publisher", "`"$Publisher`"",
                    "-ProviderUrl", "`"$ProviderUrl`"",
                    "-Name", "`"$Name`"",
                    "-Version", "`"$Version`"",
                    "-AppManifest", "`"$ManifestFile`"",
                    "-ToFile", "`"$File`""
                 )

    if (-not([string]::IsNullOrEmpty($CertFile))) {
        $mageArgs += "-CertFile"
        $mageArgs += "`"$CertFile`""
    }
	
    if (-not([string]::IsNullOrEmpty($CertPassword))) {
        $mageArgs += "-Password"
        $mageArgs += "`"$CertPassword`""
    }
	
	Write-Host "mage.exe $mageArgs`n"
    exec { & mage.exe @mageArgs }
	
	if ($MapFileExtensions) {
	    $doc = [xml](Get-Content $File)
	    $doc.assembly.deployment.SetAttribute("mapFileExtensions", "true");
	    $doc.save($File)
		
		Sign-ClickOnceManifest -File $File -CertFile $CertFile -CertPassword $CertPassword
	}
	
	TeamCity-ReportBuildProgress "Deployment manifest generated"
}

function Deploy-ClickOnceDeploymentManifestToParentFolder {
param (
    [string]$File = $(throw "File is a required parameter."),
    [string]$CertFile = $clickonce_cert_path,
	[string]$CertPassword = $clickonce_cert_password
)
	TeamCity-ReportBuildProgress "Deploying the ClickOnce manifest"
	
    Assert (Test-Path $File -PathType Leaf) "Deployment file not found. [ `$File = $File ]"

    $dir = (Get-ChildItem $File).Directory
    $parent_dir = $dir.Parent.FullName
    Assert (Test-Path $parent_dir -PathType Container) "Parent directory not found. [ `$parent_dir = $parent_dir ]"
       
    # edit the deployment file to point to the manifest in the sub-directory
    $doc = [xml](Get-Content $File)
    $codebase = $doc.assembly.dependency.dependentAssembly.codebase
    $codebase = (Join-Path $dir.Name $codebase)
    $doc.assembly.dependency.dependentAssembly.codebase = $codebase.ToString()
                       
    $doc.save($File)
	
	# resign the deployment
	Sign-ClickOnceManifest -File $File -CertFile $CertFile -CertPassword $CertPassword
	
	# copy the deployment manifest into the parent directory
	#
	# note that we also leave the manifest in the app's directory
	# so that you can always copy the manifest out of the app directory
	# back into the parent directory if you need rollback later
	$new_file = (Join-Path $parent_dir ((Get-ChildItem $File).Name))
    Copy-Item -Path $File -Destination $new_file -Force   
	
	TeamCity-ReportBuildProgress "Manifest deployed"
}

function Set-WritePermissions {
<#
.SYNOPSIS
	Grants the given account Modify, Read, Write access to the specified path.
	If the path does not exist, then a directory will be created.
	Well-known Windows SIDs - http://support.microsoft.com/kb/243330
	
.PARAMETER Path
	Path to the file or directory to grant access to.

.PARAMETER Account
	User account, group or SID who should have access.
#>
param(
	[string]$Path = $(throw "Path is a required parameter."),
	[string]$Account = $(throw "Account is a required parameter.")
)
	if ((Test-Path $Path) -eq $false) {
		New-Item $Path -ItemType "Directory"
	}

	$inherit = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
	if ((Get-Item $Path) -is [IO.FileInfo]) {
		# don't try to set inheritance flags if this is a file
		$inherit = [System.Security.AccessControl.InheritanceFlags]::None
	}
	$propogation = [System.Security.AccessControl.PropagationFlags]::None

	$acl = Get-Acl $Path
	$usersGroup = $Account
	if ($Account -match "S\-1\-[\w\d\-]+") {
		# Account looks like a SID, try and get the SecurityIdentifier for it
		$usersGroup = New-Object System.Security.Principal.SecurityIdentifier "$Account"
	}
	$rule = New-Object System.Security.AccessControl.FileSystemAccessRule $usersGroup, "Modify, Read, Write", $inherit, $propogation, "Allow"
	$acl.SetAccessRule($rule)
	$acl | Set-Acl $Path
}