function Generate-AssemblyInfo
{
param(
	[string]$title,
	[string]$description,
	[string]$company = $company_name,
	[string]$product,
	[string]$copyright,
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
[assembly: AssemblyInformationalVersionAttribute(""$info_version"")]
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

function Generate-InfoVersion {
param(
	[string]$version = $(Generate-VersionNumber)
)
    $rev = Get-RevisionNumber
    return "$version ($rev)"
}

function Get-BuildNumber {
    $build_number = if ("$env:BUILD_NUMBER".length -gt 0) { "$env:BUILD_NUMBER" } else { "0" }
    return $build_number
}

function Get-RevisionNumber {
    # get the VCS revision number, if there are multiples, select the latest one
    $numbers = (Get-ChildItem env:\BUILD_VCS_NUMBER*) | sort value -Descending | select value
    
    $rev_number = 0
    if ($numbers.Length -gt 0) {
        $rev_number = $numbers[0].Value
    }
    
    return $rev_number
}

