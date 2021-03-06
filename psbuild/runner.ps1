
function Invoke-MSBuild {
	[CmdletBinding()]
	param()
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		if([String]::IsNullOrWhiteSpace($mr.WorkingDirectory) -eq $false) {
			Write-Debug "Changing working directory:"
			Set-Location $mr.WorkingDirectory
			Write-Debug $mr.WorkingDirectory
		}
	}
	
	process {
		
		$msbuild_exe = Get-MSBuild
		$build_file = Get-BuildFile		
		
		$arguments = @()
		$arguments += $build_file
		
		$tools_version = Get-ToolsVersion
		if($tools_version) {
			$arguments += $("/tv:{0}" -f $tools_version)
		}
		
		$targets = $mr.MSBuild.Targets
		if($targets) {
			$arguments += $("/t:{0}" -f $targets)
		}
		
		$configuration = $mr.MSBuild.Configuration
		if($configuration) {
			$arguments += $("/p:Configuration={0}" -f $configuration)
		}
		
		$properties = $mr.MSBuild.Properties
		if($properties) {
			$arguments += $("/p:{0}" -f $properties)
		}
		
		$msbuild_arguments += $mr.MSBuild.Arguments -split ' '
			foreach($arg in $msbuild_arguments) {
				$arguments += $arg
			}		
	
		Invoke-Executable $msbuild_exe $arguments -Before {Before-MSBuild} -After {After-MSBuild}
	}	
}

function Before-MSBuild {
	begin {Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)}
	
	process {
		Get-AssemblyInformationFiles | % {
			Write-Debug $_.FullName
			Update-AssemblyInformation $_
		} -Begin {Write-Debug "Updating assembly information files:"}
	}
	
	end {
		if($TeamCityMode) {
			Write-Host "##teamcity[blockOpened name='MSBuild']"
		}
	}
}

function After-MSBuild {
	begin {
		if($TeamCityMode) {
			Write-Host "##teamcity[blockClosed name='MSBuild']"
		}
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
	}
	
	process {
		
		$mr.TempFiles.Values | % {			
			Write-Debug $("{0} (source/original)" -f $_.Original_FilePath)
			Write-Debug $("{0} (dest/temp)" -f $_.Temp_FilePath)
			
			Move-Item -Path $_.Original_FilePath -Destination $_.Temp_FilePath -Force:$true			
		} -Begin {Write-Debug "Restoring assembly information files:"}
	}
}

function Invoke-Executable {
	param(
		[Parameter(ValueFromPipeline=$true)]
		[String]$Exe,
		[Array]$Parameters = @(),
		[ScriptBlock]$Before = {},
		[ScriptBlock]$After = {}
	)
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		Write-Debug $("Invoking '{0}'" -f $Exe)
		$Parameters | % {Write-Debug $_} -Begin {Write-Debug "With arguments:"}
	}
	
	process {
		& $Before
		& $Exe $Parameters | Out-String
		$success = $?	
		
		if($success -eq $false) {
			throw $("failed to execute {0}" -f $Exe)
		}
		
		& $After
	}
}

function Get-AssemblyInformationFiles {
	begin {Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)}
	
	process {
	
		if([String]::IsNullOrWhiteSpace($mr.Version) -eq $false) {	
			$assemblyinfo_pattern = $mr.AssemblyInformationFileLocation
			
			$arguments = @{} 
			if([String]::IsNullOrWhiteSpace($assemblyinfo_pattern)) {
				$arguments.Recurse = $true
				$arguments.Path = "AssemblyInfo.cs"
			} else {
				$arguments.Path = $assemblyinfo_pattern
			}
			
			Write-Debug "Invoking 'Get-ChildItem'"
			$arguments.Keys | % { Write-Debug $("-{0}:{1}" -f $_,$arguments[$_])} -Begin {Write-Debug "With arguments:" }
			return Get-ChildItem @arguments
			
		}
		
		Write-Debug "No global version information available. Interpreted as skip assembly version update."
		return @()		
	}
}

function Update-AssemblyInformation {
	param(
		$File
	)
	begin {
			Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
			
			$Version = $($mr.Version -split '\+' -split '-')
			$SemVer = $Version -is [Array]
			if($SemVer) {
				Write-Debug $("SemVer detected ({0})" -f $mr.Version)
				$Version = $Version[0]
			}
			
			if([String]::IsNullOrWhiteSpace($mr.AssemblyAttributesFormat)) {
				Write-Debug "No attributes specified. Using defaults."
				$mr.AssemblyAttributesFormat = "AssemblyVersion;AssemblyFileVersion"
				
				if($SemVer) {
					Write-Debug "Adding SemVer compatible attribute."
					$mr.AssemblyAttributesFormat += ";AssemblyInformationalVersion"
				}
			}
			
			if($mr.ContainsKey("TempFiles") -eq $false) {
				$mr.TempFiles = @{}
			}
			
		}
	
	process {
			
		$original_file = Copy-Item $File -Destination $(Join-Path $File.DirectoryName ([System.IO.Path]::GetRandomFileName())) -PassThru
		$mr.TempFiles.Add($file.FullName, @{
			Original_FilePath = $original_file.FullName
			Temp_FilePath = $File.FullName  
		})
		Write-Debug $("Original File: {0}" -f $original_file.FullName)
		Write-Debug $("Temporary File: {0}" -f $File.FullName)	
			
								
		$attributes = $mr.AssemblyAttributesFormat -split ';'
		$attributes | % {
			Write-Debug $_
				
			$pattern = $('^\[assembly\: {0}\(".*\)\]' -f $_)
			$content = Get-Content $File
				
			$custom_version = $($_ -split '=')
			if($custom_version -is [Array]) {
				Write-Debug "custom version detected"
				$_ = $custom_version[0]
				$v = $custom_version[1];
			}
			else { 
				if($_ -eq "AssemblyInformationalVersion" -and $SemVer) {
					Write-Debug "semver + supported semver attribute detected"
					$v = $mr.Version
				} else {
					$v = $Version
				}
			}
					
			if($content -match $pattern) {
				Write-Debug $("updating attribute {0} with {1}" -f $_,$v)
				$content -replace $pattern, $('[assembly: {0}("{1}")]' -f $_, $v) | Set-Content -Path:$File					
			} else {
				Write-Debug $("adding new attribute {0} with {1}" -f $_,$v)
				Add-Content $File $('[assembly: {0}("{1}")]' -f $_, $v)
			}					
		} -Begin {Write-Debug "Updating attributes:"}		
	}
	
	end {
		if($TeamCityMode) {
			Write-Host "##teamcity[message text='Assembly Information Updated']"
		}
	}


}

function Get-ToolsVersion {
	
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		Write-Debug $("MSBuild ToolsVersion={0}" -f $mr.MSBuild.ToolsVersion)
	}
	
	process {
				
		$match = Get-ChildItem -Path $("HKLM:\Software\Microsoft\MSBuild\ToolsVersions\{0}" -f $mr.MSBuild.ToolsVersion) -ErrorAction:SilentlyContinue
		if($match -eq $null) {
			throw $("ToolsVersion {0} is missing. You may be able to resolve this by installing the appropriate .NET Framework version." -f $mr.MSBuild.ToolsVersion)
		}
		
		return $mr.MSBuild.ToolsVersion
	}
	
}

function Get-MSBuild {
	
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		
		if([String]::IsNullOrWhiteSpace($mr.MSBuild.Version)) {
			Write-Debug "MSBuild version has not been configured. The default value will be used."
			$mr.MSBuild.Version = "4.5"
		}
		if([String]::IsNullOrWhiteSpace($mr.MSBuild.Bitness)) {
			Write-Debug "MSBuild bitness has not been configured. The default value will be used."
			$mr.MSBuild.Bitness = "x86"
		}
		Write-Debug $("MSBuild Version={0}" -f $mr.MSBuild.Version)	
		Write-Debug $("Bitness={0}" -f $mr.MSBuild.Bitness)
	}
	
	process {
		
		$key = $("DotNetFramework{0}_{1}_Path" -f $mr.MSBuild.Version, $mr.MSBuild.Bitness)	
		$msbuild_path = Get-TeamCityParameter $key | Join-Path -ChildPath "msbuild.exe"
		
		Write-Debug $("MSBuild Path={0}" -f $msbuild_path)
		if(Test-Path $msbuild_path -PathType:Leaf) {		
			return $msbuild_path
		}
		
		throw $("{0} doesn't exist" -f $msbuild_path)
	}	
	
}

function Get-BuildFile {
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		Write-Debug $("BuildFile Path={0}" -f $mr.BuildFile)
	}
	
	process {
	
		if(Test-Path $mr.BuildFile -PathType:Leaf) {		
			return $mr.BuildFile
		}
		
		throw $("can't find '{0}'" -f $mr.BuildFile)
	}
}

function Get-TeamCityParameter {
	param(
		[String]$Key
	)	
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		Write-Debug $("Requested Parameter={0}" -f $Key)
	}
	
	process {		
		$v = $mr.MSBuild.Paths[$Key]		
		return $v
	}
}

function Invoke-Exit {
	param(
		[Int]$ExitCode
	)
	
	[System.Environment]::Exit($ExitCode)
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

function Resolve-TeamCityParameters {
	begin {
		Write-Verbose $("{0} [EXEC]" -f $MyInvocation.MyCommand)
		$mr.MSBuild.Paths = @{}
	}
	
	process {
		$mr.MSBuild.Paths["DotNetFramework4.5_x64_Path"] = "%DotNetFramework4.5_x64_Path%"
		$mr.MSBuild.Paths["DotNetFramework4.5_x86_Path"] = "%DotNetFramework4.5_x86_Path%"
		$mr.MSBuild.Paths["DotNetFramework4.0_x64_Path"] = "%DotNetFramework4.0_x64_Path%"
		$mr.MSBuild.Paths["DotNetFramework4.0_x86_Path"] = "%DotNetFramework4.0_x86_Path%"
		$mr.MSBuild.Paths["DotNetFramework3.5_x64_Path"] = "%DotNetFramework3.5_x64_Path%"
		$mr.MSBuild.Paths["DotNetFramework3.5_x86_Path"] = "%DotNetFramework3.5_x86_Path%"
		$mr.MSBuild.Paths["DotNetFramework2.0_x64_Path"] = "%DotNetFramework2.0_x64_Path%"
		$mr.MSBuild.Paths["DotNetFramework2.0_x86_Path"] = "%DotNetFramework2.0_x86_Path%"		
	}
}

$mr = @{
	MSBuild = @{
		Version = "%mr.PSBuild.MSBuild.Version%"
		Bitness = "%mr.PSBuild.MSBuild.Bitness%"
		ToolsVersion = "%mr.PSBuild.MSBuild.ToolsVersion%"
		Targets = "%mr.PSBuild.MSBuild.Targets%"
		Configuration = "%mr.PSBuild.MSBuild.Configuration%"
		Properties = "%mr.PSBuild.MSBuild.Properties%"
		Arguments = "%mr.PSBuild.MSBuild.Arguments%"
	}
	BuildFile = "%mr.PSBuild.BuildFile%"
	Version = "%mr.PSBuild.Version%"
	AssemblyAttributesFormat = "%mr.PSBuild.AssemblyAttributesFormat%"
	AssemblyInformationFileLocation = "%mr.PSBuild.AssemblyInformationFileLocation%"
	WorkingDirectory = "%mr.PSBuild.WorkingDirectory%"
}

$VerbosePreference = "%mr.PSBuild.Verbose%"
$DebugPreference = "%mr.PSBuild.Debug%"
$TeamCityMode = if($env:TEAMCITY_VERSION) {$true} else {$false}

if ($TeamCityMode) {
    Set-PSConsole
	Resolve-TeamCityParameters
}

try {
	#Invoke-MSBuild -ea:Stop
} catch {
	Write-Error $_
	Invoke-Exit 1
}