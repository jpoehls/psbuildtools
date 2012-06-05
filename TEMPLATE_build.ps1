$scriptPath = (Split-Path -parent $MyInvocation.MyCommand.path)
. $scriptPath\build\teamcity.ps1

Framework "4.0"

properties {
	$checkoutPath = [Environment]::GetEnvironmentVariable("teamcity.build.checkoutDir")
	$buildPath = "$scriptPath\@build"
	$artifactPath = if ($checkoutPath.length -gt 0) { "$checkoutPath\@artifacts" } else { "$scriptPath\@artifacts" }
	$solution = "$scriptPath\WHAT.sln"
	$nuspec = "$scriptPath\nuget\WHAT.nuspec"
	$nuspecPath = [IO.Path]::GetDirectoryName($nuspec)
	$configuration = "Release"
}

###############################################################################
# Tasks
###############################################################################

task default -depends Compile

task Compile -depends Clean, Version {
	Write-Host "Compiling in $configuration configuration."

	# Use the TeamCity MSBuild logger if possible.
	$loggerArg = ""
	$msbuildLogger = [Environment]::GetEnvironmentVariable("teamcity.dotnet.nunitlauncher.msbuild.task")
	if ($msbuildLogger -and (Test-Path $msbuildLogger)) {
		$loggerArg = "/l:JetBrains.BuildServer.MSBuildLoggers.MSBuildLogger,$msbuildLogger"
	}

	exec { msbuild ""$solution"" `
	               /m /nologo `
	               /t:Rebuild `
	               /p:Configuration=$configuration `
	               /p:OutDir=""$buildPath\\"" `
	               $loggerArg }
}

task Version {
	# Create the assembly info file.
	$version = Generate-VersionNumber
	Generate-AssemblyInfo -company "WHO" `
						  -title "WHAT" `
						  -description "" `
						  -product "WHAT" `
						  -version $version `
						  -infoVersion (Generate-InfoVersion) `
						  -file "$scriptPath\WHAT\Properties\AssemblyInfo.cs"

	# Tell TeamCity what version we are building.
	TeamCity-SetBuildNumber $version
}

task Clean {
	if (Test-Path $buildPath)    { Remove-Item -Force -Recurse $buildPath    }
	if (Test-Path $artifactPath) { Remove-Item -Force -Recurse $artifactPath }
}

task PublishNuGet -depends PackNuGet {
	if ($ENV:COMPUTERNAME -eq "STW-DEV-01") {
		Write-Host "Publishing NuGet packages to STW-DEV-01."
		Copy-Item "$artifactPath\*.nupkg" "c:\nuget"
	}
	else {
		throw "Can only publish NuGet packages when built on STW-DEV-01"
	}
}

task PackNuGet -depends Compile, CleanNuGet {
	if (-not(Test-Path $artifactPath)) {
		New-Item $artifactPath -ItemType Directory | Out-Null
	}

	New-Item "$nuspecPath\tools" -ItemType Directory | Out-Null
	Copy-Item "$buildPath\*.exe" "$nuspecPath\tools\"
	Copy-Item "$buildPath\*.dll" "$nuspecPath\tools\"

	$version = (Get-Command "$nuspecPath\tools\WHAT.exe").FileVersionInfo.FileVersion

	exec { c:\tools\nuget\nuget.exe pack `"$nuspec`" -OutputDirectory `"$artifactPath`" -Version `"$version`" }
}

task CleanNuGet {
	if (Test-Path "$nuspecPath\tools") {
		Remove-Item "$nuspecPath\tools" -Recurse
	}
}


###############################################################################
# Helper functions
###############################################################################

function Get-BuildNumber {
<#
.SYNOPSIS
Gets the build number passed in by TeamCity.
Looks for the BUILD_NUMBER environment variable.
Defaults to 0.
#>
    $build_number = if ("$env:BUILD_NUMBER".length -gt 0) { "$env:BUILD_NUMBER" } else { "0" }
    return $build_number
}

function Get-RevisionNumber {
    # get the VCS revision number, if there are multiples, then barf
    $number = ($env:BUILD_VCS_NUMBER)
    
    $rev_number = 0
    if ($number.Length -gt 0) {
        $rev_number = $number
    }
    
    return $rev_number
}

function Generate-InfoVersion {
param(
	[string]$version = $(Generate-VersionNumber)
)
    $rev = Get-RevisionNumber
    return "$version ($rev)"
}

function Generate-VersionNumber {
    $build_number = Get-BuildNumber

	# if it looks like the build number is a full version number
	# then use it
	if ($build_number.Split('.').Length -gt 1) {
		$version = $build_number
	} else {
		# otherwise, use the build_number as the revision number
		# in a datestamp based version number
		$version = [DateTime]::Now.ToString("yy.M.d") + ".$build_number"  
	}
    return $version
}

function Generate-AssemblyInfo
{
param(
	[string]$title,
	[string]$description,
	[string]$company,
	[string]$product,
	[string]$copyright,
	[string]$version,
	[string]$infoVersion,
	[string]$file = $(throw "file is a required parameter.")
)  
  if ($copyright -eq $null) {
    $year = [DateTime]::Now.ToString("yyyy")
    $copyright = "Copyright (c) $company $year"
  }
 
  $asmInfo = "using System;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

[assembly: ComVisibleAttribute(false)]
[assembly: AssemblyTitleAttribute(""$title"")]
[assembly: AssemblyDescriptionAttribute(""$description"")]
[assembly: AssemblyCompanyAttribute(""$company"")]
[assembly: AssemblyProductAttribute(""$product"")]
[assembly: AssemblyCopyrightAttribute(""$copyright"")]
[assembly: AssemblyVersionAttribute(""$version"")]
[assembly: AssemblyInformationalVersionAttribute(""$infoVersion"")]
[assembly: AssemblyFileVersionAttribute(""$version"")]
[assembly: AssemblyDelaySignAttribute(false)]"
 
	$dir = [System.IO.Path]::GetDirectoryName($file)
	if ((Test-Path $dir) -eq $false)
	{
		Write-Host "Creating directory $dir"
		[System.IO.Directory]::CreateDirectory($dir) | out-null
	}
	Write-Host "Generating assembly info file: $file"
    if (Test-Path $file) {
	   (Get-Item $file).Attributes = 'Normal'
    }
	Write-Output $asmInfo > $file
}