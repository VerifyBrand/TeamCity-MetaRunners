###
. "$(Join-Path $PSScriptRoot '_TestContext.ps1')"
###

function Add-NuSpecVersion {
	param(
		[String]$Version,
		[String]$FileName
	)
	
	$nuspec_template = $(Get-Content $(Join-Path $PSScriptRoot template.nuspec)) -as [Xml]
	$nuspec_template.package.metadata.version = $Version
	Setup -File -Path $FileName -Content $nuspec_template.OuterXml
}

Fixture "Get-SemVer" {
	
	Mock Get-TeamCityVersion {return $build_counter }
	
	Given "that a nuspec filepath has been set" {
		Add-NuSpecVersion "1.4.0" "test.nuspec"
		$mr.NuSpecFilePath = 'test.nuspec'
		$expected = Get-NuSpecVersion
		
		Then "'MAJOR.MINOR.PATCH' should be read from the nuspec version" {
			Get-SemVer | Should Be $("$expected+$build_counter")
		}
	}
	
#	Given "that the nuspec file is not valid" {
#		Add-NuSpecVersion "n/a" "test.nuspec"
#		$mr.NuSpecFilePath = 'test.nuspec'
#		Mock Invoke-Exit {}
#		
#		Then "the execution should fail" {
#			Get-SemVer
#			
#			Assert-MockCalled Invoke-Exit -Exactly 1 {$ExitCode -eq 1}
#		}
#	}
}

Fixture "Get-TeamCityVersion" {
	$mr.BuildCounter = $build_counter
	
	# dropdown with values?
	
	Given "that the VCS type is GIT" {
		$mr.VCSType = "Git"
		$git_hash = "4112e01dabedb68fc66006085ae68df697b5ad9d"
		$git_short_hash = $git_hash.SubString(0,7)
		$mr.BuildVCSNumber = $git_hash
		
		Then "the version should include the short git hash" {
			Get-TeamCityVersion | Should Be $("{0}.{1}" -f $build_counter, $git_short_hash)
		}
	}
	
	Given "that no VCS type is set" {
		$mr.VCSType = ""
		
		Then "the version should not include the revision" {
			Get-TeamCityVersion | Should Be $build_counter
		}
	}
	

}

Fixture "Get-NuSpecVersion" {
	
	Given "that the nuspec file is not a valid nuspec file" {
		Setup -File notvalid.nuspec #no xml
		$mr.NuSpecFilePath = "notvalid.nuspec"
		Mock Write-Error {}
		
		Then "an error should be displayed" {
			Get-NuSpecVersion
			
			Assert-MockCalled Write-Error 1
		}
	}
	
	Given "that the nuspec file has no valid version" {
		Add-NuSpecVersion "$version$" "nuget.nuspec"
		$mr.NuSpecFilePath = 'nuget.nuspec'
		Mock Write-Error {}
		
		Then "an error should be displayed" {
			Get-NuSpecVersion
			
			Assert-MockCalled Write-Error 1
		}
	}
}



