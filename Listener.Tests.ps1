$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"
. "$here\helpers.ps1"

# Pester does not appear to mock .NET objects and their methods currently, so no obvious tests for the core component: Invoke-HTTPListener

Describe "Start-HTTPD" {
    $non_existent_prefix = 'http://+:8080/qazwsxedcrfvtgbyhnujmikolp'
    $content = {'blah'}
    
    Context "when called as a non admin or without an existing prefix" {
        It "should throw an error" {
            {Start-HTTPD -Prefix $non_existent_prefix -Content $content} | Should Throw
        }
    }

    Context "when called with an already running prefix" {
        Mock Test-HTTPDPrefix {$true}
        Mock Test-URLPrefix {$true}

        It "Should throw an error" {
            {Start-HTTPD -Prefix $non_existent_prefix -Content $content} | Should Throw
        }
    }

    Context "when called with a non-running prefix" {
        $mock_job = 'JOB!'

        Mock Test-HTTPDPrefix {$false}
        Mock Test-URLPrefix {$true}
        Mock Start-Job {$mock_job}

        Start-HTTPD -Prefix $non_existent_prefix -Content $content

        It "Should set the running HTTPD prefix variable" {
            $Script:HTTPDPrefixes.$non_existent_prefix | Should Not BeNullOrEmpty
        }

        $Script:HTTPDPrefixes.remove($non_existent_prefix)
    }

}

Describe "Test-HTTPDPrefix" {
    $prefix = 'http://+:8080/working'
    

    Context "when the HTTPD for a prefix is running" {
        if (-not (Test-Path -Path VARIABLE:SCRIPT:HTTPDPrefixes)) {
            $Script:HTTPDPrefixes = @{}
        }

        $Script:HTTPDPrefixes.Add($prefix, 'blah')

        $result = Test-HTTPDPrefix -Prefix $prefix

        It "should return $true" {
            $result | Should Be $true
        }
    }

    Context "when the HTTPD for a prefix is not running" {
        try {
            $Script:HTTPDPrefixes.Remove($prefix) 
        } catch {}

        $result = Test-HTTPDPrefix -Prefix $prefix

        It "should return $false" {
            $result | Should Be $false
        }
    }
}

Describe "Stop-HTTPD" {
    $non_existent_prefix = 'http://+:8080/qazwsxedcrfvtgbyhnujmikolp'
    $existing_prefix = 'http://+:8080/working'

    if (-not (Test-Path -Path VARIABLE:SCRIPT:HTTPDPrefixes)) {
            $Script:HTTPDPrefixes = @{}
    }

    $Script:HTTPDPrefixes.Add($existing_prefix, (new-object System.Management.Automation.ContainerParentJob 'blah'))
    
    Context "when called with a non-existant prefix" {
        It "should throw an error" {
            {Stop-HTTPD -Prefix $non_existent_prefix} | Should Throw
        }
    }

    Context "when called with an existing prefix" {
        Mock Stop-Job -verifiable  {$true}

        Stop-HTTPD -Prefix $existing_prefix

        It "should remove the prefix" {
            $Script:HTTPDPrefixes.containskey($existing_prefix) | Should Be $false
        }

        It "should call Stop-Job" {
            Assert-VerifiableMocks
        }
    }
}

Describe "Restart-HTTPD" {
    Mock Stop-HTTPD -verifiable {}
    Mock Start-HTTPD -verifiable {}

    Restart-HTTPD

    Context "when called" {
        It "should call the Stop/Start functions" {
            Assert-VerifiableMocks
        }
    }

}