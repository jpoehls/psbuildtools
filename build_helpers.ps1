function Invoke-NUnitRunner {
param(
    [string] $assembly_path = $(throw "assembly_path is a required parameter. should be a path to an existing file or directory.")
)
    $envName = "teamcity.dotnet.nunitlauncher"
    $nunitLauncher = [Environment]::GetEnvironmentVariable("$envName")
       
    if ($nunitLauncher -eq $null) {
        "Skipping tests. The $envName environment variable was not found."
    } else {
		if ([System.IO.Directory]::Exists($assembly_path)) {
			"Searching for *.Tests.dll files in $assembly_path"
			# automatically find and run all test assemblies in the given path
            Get-ChildItem -Path $assembly_path -Recurse -Filter "*.Tests.dll" | foreach { Invoke-NUnitRunner $_.FullName }
		} elseif ([System.IO.File]::Exists($assembly_path)) {
			"Running tests in $assembly_path"
			# run tests for the assembly passed in
            exec { & $nunitLauncher v$framework x86 NUnit-2.5.2 $assembly_path }
		} else {
            "Skipping tests. The `$assembly_path is not a value file or directory. `$assembly = `"$assembly`""
        }
    }
}

function Invoke-MSBuild {
param(
    [string] $project = $(throw "project is a required parameter."),
    [string] $configuration = "Release"
)
	TeamCity-ReportBuildProgress "Building project $project"
	
	Assert (Test-Path $project) "specified project file does not exist."
    exec { msbuild ""$project"" /m /nologo /t:Rebuild /p:Configuration=$configuration /p:OutDir=""$build_path\\"" }
	
	TeamCity-ReportBuildProgress "Build completed"
}

function Get-PrimaryArtifactZipPath {
    Assert (-not([string]::IsNullOrEmpty($product_name))) "product_name property is required"
    Assert (-not([string]::IsNullOrEmpty($version))) "version property is required"
    
    $short_name = (Get-CamelCase $product_name)

    $zip_name = "$artifact_path\$short_name-$version.zip";
	return $zip_name
}

function Zip-BuildOutput {
param(
	[string] $zipFile = $(throw "zipFile is a required parameter.")
)
	# create the artifact_path if needed
	if (-not(Test-Path $artifact_path)) {
		New-Item $artifact_path -ItemType Directory
	}

	# add a build_number.txt file to the zip containing the version being built
	# this will be used by the deploy task to set the TeamCity build number to the version being deployed
	Out-File -FilePath "$artifact_path\build_number.txt" -InputObject "$version" -Encoding "OEM"

	Invoke-7zip "a", "-tzip", "`"$zipFile`"", "`"$build_path\`"", "`"$artifact_path\build_number.txt`""
}

function Zip-BuildTools {
param(
	[string] $zipFile = $(throw "zipFile is a required parameter.")
)
	Invoke-7zip "a", "-tzip", "`"$zipFile`"", "`"$script_path`"", "-xr!*.chm"
}

# if a website was built, this handles
# cleaning up the build output into something
# we expect from a website
function Move-PublishedWebsiteBuildOutput {
	
	$published_websites_path = "$build_path\_PublishedWebsites"
	if (Test-Path $published_websites_path) {
		# remove all build output except the _PublishedWebsites folder
		Remove-Item "$build_path\*" -Recurse -Exclude "_PublishedWebsites"

		# get the children of the _PublishedWebsitesFolder
		$published_websites_children = (Get-ChildItem $published_websites_path)

		if ($published_websites_children.Count -gt 1) {
			# if there is more than one child, move them all up a level
			Move-Item "$published_websites_path\**" -Destination $build_path
		} else {
			if ($published_websites_children -is [System.IO.DirectoryInfo]) {
				# if there is just one sub-directory then move its contents to the build path
				Move-Item ($published_websites_children.FullName + "\**") -Destination $build_path
			} else {
				# else just move whatever it is to the build path
				Move-Item $published_websites_children.FullName -Destination $build_path
			}
		}

		# if it's still around, delete the _PublishedWebsites folder
		if (Test-Path $published_websites_path) {
			Remove-Item $published_websites_path -Recurse -Force
		}
	}

}

# publishes a build artifact (ZIP file) that contains
# all of the build output, any deployment scripts and build tools
function Publish-BuildOutput {
	TeamCity-ReportBuildProgress "Publishing build output"

    $zip_name = Get-PrimaryArtifactZipPath
	Zip-BuildOutput $zip_name
    
    # if a deployment scripts are detected then
    # include all the build tools and the deployment script(s)
	Write-Host "Checking for deployment scripts matching the pattern `"$deploy_file_pattern`" in $checkout_path (if not rooted)"
	$deploy_file_pattern2 = $deploy_file_pattern
	if (-not([IO.Path]::IsPathRooted($deploy_file_pattern))) {
		$deploy_file_pattern2 = (Join-Path $checkout_path $deploy_file_pattern)
	}
    if ((Get-ChildItem $deploy_file_pattern2).Length -gt 0) {
		Write-Host "Deployment scripts found. Including scripts and build tools in artifact ZIP file."
        Invoke-7zip "a", "-tzip", "`"$zip_name`"", "`"$deploy_file_pattern2`""#, "-i!$deploy_file_pattern"
		Zip-BuildTools $zip_name
    } else {
		Write-Host "No deployment scripts found."
	}
   
    TeamCity-PublishArtifact ("$artifact_path_rel\" + [System.IO.Path]::GetFileName($zip_name))
	
	TeamCity-ReportBuildProgress "Publish completed"
}