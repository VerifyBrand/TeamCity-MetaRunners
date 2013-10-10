function Update-BuildNumber {
	param(
		[Parameter(ValueFromPipeline=$true)]
		[String]$BuildNumber
	)
	Write-Verbose $("Starting: '{0}'" -f $MyInvocation.MyCommand)
	Write-Debug $("Build Number: {0}" -f $BuildNumber)
	
	Write-Host "##teamcity[buildNumber '$BuildNumber']"
}


function Get-NuSpecVersion {
	[CmdletBinding()]
	param()
	
	Write-Verbose $("Starting: '{0}'" -f $MyInvocation.MyCommand)
	Write-Debug $("NuSpec File: {0}" -f $mr.NuSpecFilePath)
	
	$nuspec_file = $(Get-Content $mr.NuSpecFilePath -ErrorAction:SilentlyContinue) -as [Xml]
	if($nuspec_file)
	{
		$version = $nuspec_file.package.metadata.version -as [System.Version]
		if($version) {
			return $version
		} else {
			Write-Error "The NuSpec file contains no valid version information"
		}		
	} else {
		Write-Error $("NuSpec file path invalid or it wasn't a valid nuspec file.")
	}
}

function Get-TeamCityVersion {
	Write-Verbose $("Starting: '{0}'" -f $MyInvocation.MyCommand)
	Write-Debug $("VCS Type: {0}" -f $mr.VCSType)
	Write-Debug $("Build Counter: {0}" -f $mr.BuildCounter)
	
	switch ($mr.VCSType) {
		"Git" {
			$git_short_hash = $mr.BuildVCSNumber.SubString(0,7)
			Write-Debug $("Git ShortHash: {0}" -f $git_short_hash)
		
			return $("{0}.{1}" -f $mr.BuildCounter, $git_short_hash)
		}
		default {return $mr.BuildCounter} #same as None
	}
	
}

function Invoke-Exit {
	param(
		[Int]$ExitCode
	)
	
	[System.Environment]::Exit($ExitCode)
}

function Get-SemVer {
	Write-Verbose $("Starting: '{0}'" -f $MyInvocation.MyCommand)
	
	if($mr.NuSpecFilePath) {
		$version = Get-NuSpecVersion -ea:Stop
	}
	
	$teamcity_version = Get-TeamCityVersion
	Write-Debug $("TeamCity Version: {0}" -f $teamcity_version)
	
	return $("{0}+{1}" -f $version, $teamcity_version) 
}

function Set-PSConsole {
  try {
        $max = $host.UI.RawUI.MaxPhysicalWindowSize
        if($max) {
        $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(9999,9999)
        $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($max.Width,$max.Height)
    }
    } catch {}
}

$mr = @{
	NuSpecFilePath = "%mr.SemVer.NuSpecFilePath%"
	BuildCounter = "%build.counter%"
	BuildVCSNumber = "%build.vcs.number%"
	VCSType = "%mr.SemVer.VCSType%"
}

$VerbosePreference = "%mr.SemVer.Verbose%"
$DebugPreference = "%mr.SemVer.Debug%"

if ($env:TEAMCITY_VERSION) {
    Set-PSConsole
}

try {
	#Get-SemVer | Update-BuildNumber
} catch {
	Write-Error $_
	Invoke-Exit 1
}