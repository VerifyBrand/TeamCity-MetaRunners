###
. "$(Join-Path $PSScriptRoot '_TestContext.ps1')"
###
#$VerbosePreference = "Continue"
#$DebugPreference = "Continue"

Scenario "Invoke-MSBuild" {
	
	Mock Invoke-Executable {}
	Mock Get-ToolsVersion {return $null}
	$mr.WorkingDirectory = ""
	
	function When {
		Mock Get-MSBuild {return "msbuild.exe"}
		Mock Set-Location {}
		$mr.BuildFile = Setup -File "myproj.sln" -PassThru		
		Invoke-MSBuild
	}

	Given "a build file that is in a sub folder" {		
		$global:file = Setup -File "SubDir\myproj.sln" -PassThru
		$mr.BuildFile = "myproj.sln"
			
		And "a working directory that has been set to the same sub folder" {
			$mr.WorkingDirectory = "SubDir"		

			function When {
				Mock Get-MSBuild {return "msbuild.exe"}
				Invoke-MSBuild
			}
					
			Then "we should be able to find the build file" {
				Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "myproj.sln"}
			}	
		}
		
	}

	Given "that the ToolsVersion is 3.5" {
		Mock Get-ToolsVersion {return "3.5"}
		
		Then "the ToolsVersion switch should include the tools version 3.5" {						
			Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "/tv:3.5"}
		}
	}
	
	Given "that the MsBuild Targets switch is used" {
		$mr.MSBuild.Targets = "target1"
		
		Then "the Target switch should include target" {	
			Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "/t:target1"}
		}
	}
	
	Given "that the configuration is set to RELEASE" {
		$mr.MSBuild.Configuration = "RELEASE"
		
		Then "the configuration property should be included and say RELEASE" {
			Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "/p:Configuration=RELEASE"}
		}
	}
	
	Given "that the MSBuild property for WarningLevel is set to 2" {
		$mr.MSBuild.Properties = "WarningLevel=2"
		
		Then "that property and value should be sent to MSBuild" {
			Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "/p:WarningLevel=2"}
		}
		
		And "OutDir is set to pkg" {
			$mr.MSBuild.Properties += ";OutDir=pkg"
			
			Then "both properties and their values should be sent to MSBuild" {
				Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "/p:WarningLevel=2;OutDir=pkg"}
			}
		}
	}
	
	Given "that the MSBuild switch /nologo is added to the arguments" {
		$mr.MSBuild.Arguments = "/nologo"
		
		Then "it should be passed along to msbuild.exe" {
			Assert-MockCalled Invoke-Executable -Exactly 1 {$Parameters -contains "/nologo"}
		}
		
		And "that the verbosity is set to detailed" {
			$mr.MSBuild.Arguments += " /verbosity:detailed"
			
			Then "they should both be passed along to msbuild.exe" {
				Assert-MockCalled Invoke-Executable -Exactly 1 {($Parameters -contains "/nologo") -and ($Parameters -contains "/verbosity:detailed")}
			}
		}
	}
}

Scenario "Before-MSBuild" {
	
	Given "that no assembly version is added" {
		$mr.Version = ""
		Mock Update-AssemblyInformation {}
		
		Then "we shouldn't try to update any assembly information" {
			Before-MSBuild
			
			Assert-MockCalled Update-AssemblyInformation -Exactly 0
		}
	}
	
	Given "that the assembly version is 1.0.0" {
		$mr.Version = "1.0.0"
		Mock Update-AssemblyInformation {}
		
		And "there's just one assembly info file" {
			Mock Get-AssemblyInformationFiles{return @(@{FullName="AssemblyInfo.cs"})}
			
			Then "we should try to update just one file file" {
				Before-MSBuild
				
				Assert-MockCalled Update-AssemblyInformation -Exactly 1
			}
		}
		
		Or "there are two assembly info files" {	
			Mock Get-AssemblyInformationFiles{return @(@{FullName="AssemblyInfo.cs"},@{FullName="AssemblyInfo2.cs"})}
			
			Then "we should try to update those two files" {
				Before-MSBuild
				
				Assert-MockCalled Update-AssemblyInformation -Exactly 2
			}
		}	
	}
}

Scenario "After-MSBuild" {
	
	function When {
		After-MSBuild
	}
	
	Given "that the tempfiles contains one entry" {
		Mock Move-Item {}
		
		$mr.TempFiles = @{
			File1 = @{
				Original_FilePath = "xxx.yyy"
				Temp_FilePath = "Properties/AssemblyInfo.cs"
			}
		}
	
		Then "we should try to restore the original file" {
			Assert-MockCalled Move-Item -Exactly 1 { ($Path -eq "xxx.yyy") -and ($Destination -eq "Properties/AssemblyInfo.cs") }
		}
	}
	
}

Scenario "Update-AssemblyInformation" {	

	function When {		
		$global:file = Copy-Item $(Join-Path $PSScriptRoot "AssemblyInfo.cs") -Destination:$TestDrive -PassThru
		$mr.TempFiles = @{}
		Update-AssemblyInformation $file
	}
	
	function FormatAssemblyAttribute ($attribute, $version = $mr.Version) {
		return $('[assembly: {0}("{1}")]' -f $attribute, $version)	
	}
	
	function AttributeShouldContain {
		param(
			[Parameter(ValueFromPipeline=$true)]
			$Attribute,
			$Version
		)
		
		return $file | Should Contain $('^\[assembly\: {0}\("{1}"\)\]' -f $Attribute, $Version)
	}
		
	Given "a regular version" {		
		$mr.Version = "1.2.3.4"
		
		And "the attributes to update do not supply a custom version" {
			$mr.AssemblyAttributesFormat = "UseTheGlobalVersion"
			
			Then "the version should be default" {
				AttributeShouldContain "UseTheGlobalVersion" $mr.Version
			}
		}
		
		And "one of the attributes uses a custom version" {
			$mr.AssemblyAttributesFormat += ";UseCustomVersion=1.2.3+99"
			
			Then "that attribute should have the custom version" {
				AttributeShouldContain "UseCustomVersion" "1\.2\.3\+99"
			}
		}
		
		And "there are two attributes to update that are already present" {
			$mr.AssemblyAttributesFormat = "AssemblyVersion;AssemblyFileVersion"
			
			Then $("the first attribute should have value {0}" -f $mr.Version) {
				$file | Should Contain $(FormatAssemblyAttribute "AssemblyVersion")			
			}
		
			And -Then $("the second attribute should have value {0}" -f $mr.Version) {
				$file | Should Contain $(FormatAssemblyAttribute "AssemblyFileVersion")
			}
		}
				
		Or "the attribute isn't present" {
			$mr.AssemblyAttributesFormat = "AssemblyInformationalVersion"
			
			Then $("the attribute should have value {0}" -f $mr.Version) {
				$file | Should Contain $(FormatAssemblyAttribute "AssemblyInformationalVersion")
			}
			
			And -Then "the tempfiles should contain the original file and the temp file" {
				$item = $mr.TempFiles[$file.FullName]
				$item.Temp_FilePath | Should Be $file.FullName
				$item.Original_FilePath | Should Exist
			}			
		}
		
		Or "you haven't configured any attributes" {
			$mr.AssemblyAttributesFormat = ""
	
			Then "we should stamp the default attributes" {
				"AssemblyVersion" | AttributeShouldContain -Version:"1\.2\.3\.4"
				"AssemblyFileVersion" | AttributeShouldContain -Version:"1\.2\.3\.4"
			}
		}

	}
	
	Given "a semantic version with build meta data" {
		$mr.Version = "1.2.3+99"
		
		$examples = @{
			AssemblyInformationalVersion = "1\.2\.3\+99"
			AssemblyVersion = "1\.2\.3"
			AssemblyFileVersion = "1\.2\.3"
		}
		
		And $("the attributes to update are '{0}'" -f $($examples.Keys -join ',')) {			
			
			$mr.AssemblyAttributesFormat = $($examples.Keys -join ';')
			
			foreach ($key in $examples.Keys) {
				$example = $examples[$key]
				
				Then $("the attribute '{0}' should have value '{1}'" -f  $key, $example) {
					$file | Should Contain $('^\[assembly\: {0}\("{1}"\)\]' -f $key, $example)
				}
			}		
		}
		
		Or "the attributes to update doesn't include the AssemblyInformationalVersion attribute" {
			$mr.AssemblyAttributesFormat = "AssemblyVersion"
			
			Then "the updated attributes should have a simple version number" {
				$file | Should Contain $('^\[assembly\: AssemblyVersion\("1\.2\.3"\)\]')
			}
		}
		
		Or "you haven't configured any attributes" {
			$mr.AssemblyAttributesFormat = ""
			
				Then "the attribute that supports SemVer should get the complete version" {					
					 "AssemblyInformationalVersion" | AttributeShouldContain -Version:"1\.2\.3\+99"
				}
				
				And -Then "the attributes that doesn't support SemVer should get the simple version" {
					"AssemblyVersion" | AttributeShouldContain -Version:"1\.2\.3"
					"AssemblyFileVersion" | AttributeShouldContain -Version:"1\.2\.3"
				} 
		}
	}
	
	Given "a pre-release version" {
		$mr.Version = "1.2.3-beta"
		
		And "an attribute that supports semantic version numbers" {
			$mr.AssemblyAttributesFormat = "AssemblyInformationalVersion"
			
			And "an attribute that doesn't" {
				$mr.AssemblyAttributesFormat += ";AssemblyVersion"
				
				Then "the attribute that supports semver should get the complete version" {					
					 "AssemblyInformationalVersion" | AttributeShouldContain -Version:"1.2.3-beta"
				}
				
				And -Then "the attribute that doesn't support semver should get the simple version" {
					"AssemblyVersion" | AttributeShouldContain -Version:"1.2.3"
				}
			}
		}		

	}

}

Scenario "Get-AssemblyInformationFiles" {

	Mock Get-ChildItem {}
	$mr.Version = "1.2.3"
	
	Given "you're trying to find AssemblyInfo files without configuring which ones to look for" {
		$mr.AssemblyInformationFileLocation = ""
		
		Then "we should recursively look for default files" {
			Get-AssemblyInformationFiles
			
			Assert-MockCalled Get-ChildItem -Exactly 1 {$Recurse -eq $true}
		}
	}
}

Scenario "Get-BuildFile" {
	
	Given "you have configured a build file that doesn't exist" {
		$mr.BuildFile = "not-valid-path"
		
		Then "an error message should be displayed" {
			{Get-BuildFile} | Should Throw "not-valid-path"
		}
	}
}

Scenario "Get-ToolsVersion" {
	
	Given "you have configured a ToolsVersion that is not installed" {
		
		Mock Get-ChildItem {return $null} {$Path.StartsWith("HKLM:\Software\Microsoft\MSBuild\ToolsVersions\")}
		
		Then "an error should be displayed" {
			{Get-ToolsVersion} | Should Throw "ToolsVersion"			
		}	
	}
}

Scenario "Get-MSBuild" {

	$GetTeamCityParameter_Mock = {return $TestDrive}
	$TestPath_Mock = {return $true}
	
	function Setup-Mocks {
		Mock Get-TeamCityParameter $GetTeamCityParameter_Mock
		Mock Test-Path $TestPath_Mock
	}
	
	function When {		
		Setup-Mocks
		Get-MSBuild
	}	
	
	Given "that you try to locate msbuild.exe without configuring the path" {
	
		$mr.MSBuild.Bitness = ""
		$mr.MSBuild.Version = ""
		
		Then "we should try to look for msbuild.exe in the default location" {
			Assert-MockCalled Get-TeamCityParameter -Exactly 1 {$Key -like "*4.5_x86_*"}
		}
	}
	
	Given "that msbuild.exe doesn't exist at the path that has been configured" {
		$TestPath_Mock = {return $false}
		
		Then "an error message should display" {
			{Get-MSBuild} | Should Throw "msbuild.exe doesn't exist"
		} -When {Setup-Mocks}
	}
	
	Given "that you configure the version" {
		
		$mr.MSBuild.Version = "TestVersion"
	
		And "the bitness" {
			$mr.MSBuild.Bitness = "TestBitness"
			
			Then "it should ask for the correct msbuild path based on the configuration" {
				$expected = "DotNetFrameworkTestVersion_TestBitness_Path"	
				Assert-MockCalled Get-TeamCityParameter -Exactly 1 {$Key -eq $expected}
			}
		}

	}
}

Scenario "Get-TeamCityParameter" {
	
	Resolve-TeamCityParameters
	$Parameter = ""
	
	function When {		
		$global:Result = Get-TeamCityParameter $Parameter
	}
	
	$examples = @("4.5_x64", "4.5_x86", "4.0_x64", "4.0_x86", "3.5_x64", "3.5_x86", "2.0_x64", "2.0_x86")
	foreach($example in $examples) {
		
		Given $("that the parameter is DotNetFramework{0}_Path" -f $example) {
			$Parameter = $("DotNetFramework{0}_Path" -f $example)
			
			Then $("it should return %DotNetFramework{0}_Path%" -f $example) {
				$Result | Should Be $("%DotNetFramework{0}_Path%" -f $example)
			}
		}
	}	
}







