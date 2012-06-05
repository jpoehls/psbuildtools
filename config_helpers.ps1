function Get-CamelCase {
param (
    [string] $str = $(throw "str is a required parameter")
)
    $str = $str -replace "[^a-zA-Z0-9 ]", ""
    $str = (Get-Culture).TextInfo.ToTitleCase((Get-Culture).TextInfo.ToLower($str))
    $str = $str -replace "[ ]", ""
    return $str
}

function Edit-XmlNodes {
param (
    [xml] $doc = $(throw "doc is a required parameter"),
    [string] $xpath = $(throw "xpath is a required parameter"),
    [string] $value = $(throw "value is a required parameter"),
    [bool] $condition = $true
)    
    if ($condition -eq $true) {
        $nodes = $doc.SelectNodes($xpath)
         
        foreach ($node in $nodes) {
            if ($node -ne $null) {
                if ($node.NodeType -eq "Element") {
                    $node.InnerXml = $value
                }
                else {
                    $node.Value = $value
                }
            }
        }
    }
}
 
function Set-XmlNodes {
<#
.SYNOPSIS
	Replaces all nodes in the given XML document
	that match the XPath expression.
#>
param (
    [xml] $doc = $(throw "doc is a required parameter"),
    [string] $xpath = $(throw "xpath is a required parameter"),
    [string] $value = $(throw "value is a required parameter"),
    [bool] $condition = $true
)    
    if ($condition -eq $true) {
        $nodes = $doc.SelectNodes($xpath)
        $newNodes = New-Object System.Xml.XmlDocument;
        $newNodes.LoadXml($value);
        foreach ($node in $nodes) {
            if ($node -ne $null) {
                $node.RemoveAll();
                $importNode = $doc.ImportNode($newNodes.DocumentElement, $true);
                $newNode = $node.ParentNode.ReplaceChild($importNode, $node);
            }
        }
    }
}
 
function Remove-XmlNodes {
<#
.SYNOPSIS
	Removes all nodes from the given XML document that
	match the XPath expression.
#>
param (
    [xml] $doc = $(throw "doc is a required parameter"),
    [string] $xpath = $(throw "xpath is a required parameter"),
    [bool] $condition = $true
)
    if ($condition -eq $true) {
        $nodes = $doc.SelectNodes($xpath)
         
        foreach($node in $nodes) {
            $nav = $node.CreateNavigator();
            $nav.DeleteSelf();
        }
    }
}

function Replace-XmlNodeValue {
<#
.SYNOPSIS
	Replaces the inner XML of the ContentRoot node
	with the inner XML of the SubstitutionsRoot node.
#>
param(
	[string]$ContentFile = $(throw "ContentFile is a required parameter."),
	[string]$SubstitutionsFile = $(throw "SubstitutionsFile is a required parameter."),
	[string]$ContentRoot = $(throw "ContentRoot is a required parameter."),
	[string]$SubstitutionsRoot = $(throw "SubstitutionsRoot is a required parameter.")
)
    $root_doc = [xml](Get-Content $ContentFile)
    $sub_doc = [xml](Get-Content $SubstitutionsFile)
    
    $sub_node = $sub_doc.SelectSingleNode($SubstitutionsRoot)
    Edit-XmlNodes $root_doc -xpath $ContentRoot -value $sub_node.InnerXml
    
    $root_doc.Save($ContentFile)
}

function Edit-AppSetting {
<#
.SYNOPSIS
	Changes the value of an existing appSetting in a
	web.config or app.config file.
#>
param (
	[xml]$Doc = $(throw "Doc is a required parameter."),
	[string]$Key = $(throw "Key is a required parameter."),
	[string]$Value = $(throw "Value is a required parameter.")
)
	Edit-XmlNodes $Doc -xpath "/configuration/appSettings/add[@key='$Key']/@value" `
	                   -value $Value
}