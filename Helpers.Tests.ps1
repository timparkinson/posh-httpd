$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"

Describe "Get-CurrentUsername" {

    Context "when called" {
        $expected_result = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $result = Get-CurrentUsername
        It "should return the username" {
            $result | Should Be $expected_result
        }
    }
}

Describe "Test-IsAdministrator" {
    Context "when called as a non-administrator" {
        $result = Test-IsAdministrator
        
        It "should return false" {
            $result | Should Be $false
        }
    
    }

    # Can't think of how to easily test the administrator version

}

Describe "Get-URLPrefix" {
    $netsh_response = @"
URL Reservations: 
----------------- 

    Reserved URL            : http://+:8080/banana/ 
        User: NT AUTHORITY\Authenticated Users
            Listen: Yes
            Delegate: No
            SDDL: D:(A;;GX;;;AU)

    Reserved URL            : http://+:8080/apple/ 
        User: NT AUTHORITY\Authenticated Users
            Listen: Yes
            Delegate: No
            SDDL: D:(A;;GX;;;AU)
"@

    Mock Invoke-Expression {$netsh_response -split "`n"}

    Context "when called" {
        $result = Get-URLPrefix 

        It "should return 2 results" {
            $result.count | Should Be 2
        }
    }

}

Describe "Register-URLPrefix" {

    Context "when called as a non admin" { 

        It "should throw an error" {
            {Register-URLPrefix 'http://+:8080' 'domain\test' } | Should Throw
        }
    }

    Context "when called as an admin" {
        Mock Test-IsAdministrator {$true}
        Mock Invoke-Expression {'URL reservation successfully added'}

        $result = Register-URLPrefix 'http://+:8080' 'domain\test'

        It "should return $true" {
            
            $result | Should Be $true
        }
    }

    Context "when called as an admin and failing" {
        Mock Test-IsAdministrator {$true}
        Mock Invoke-Expression {'A different return from netsh'}
    
        $result = Register-URLPrefix 'http://+:8080' 'domain\test'

        It "should return $false" {
            
            $result | Should Be $false
        }
    }
}

Describe "Test-URLPrefix" {
    $netsh_response = @"
URL Reservations: 
----------------- 

    Reserved URL            : http://+:8080/banana/ 
        User: NT AUTHORITY\Authenticated Users
            Listen: Yes
            Delegate: No
            SDDL: D:(A;;GX;;;AU)

    Reserved URL            : http://+:8080/apple/ 
        User: NT AUTHORITY\Authenticated Users
            Listen: Yes
            Delegate: No
            SDDL: D:(A;;GX;;;AU)
"@

    Mock Invoke-Expression {$netsh_response -split "`n"}

    Context "when called with a matching prefix/user pair" {
        $result = Test-URLPrefix 'http://+:8080/banana/' 'NT AUTHORITY\Authenticated Users'

        It "should return $true" {
            $result | Should Be $true
        }
    }

    Context "when called with a non-matching prefix" {

        It "should Throw an error" {
            {Test-URLPrefix 'http://+:8080/cabbage/' 'NT AUTHORITY\Authenticated Users'} | Should Throw
        }
    }

    Context "when called with a matching prefix, non-matching user" {
        $result = Test-URLPrefix 'http://+:8080/banana/' 'DOMAIN\BANAMAN' 

        It "should return $false" {
            $result | Should Be $false
        }
    }

}

Describe "New-ScriptblockCallback" {
    Context "when called" {
        $result = New-ScriptblockCallback {'banana'}
        
        It "should return an System.AsyncCallback object" {
            $result.GetType().FullName | Should Be 'System.AsyncCallback'
        }
    }
}

Describe "ConvertTo-CallbackScriptblock" {
    $working_scriptblock_text = "'hello world'"
    $error_scriptblock_text = "'hello world'}"

    Context "when called with a non-parsing scriptblock" {
        It "should throw an error" {
            {ConvertTo-CallbackScriptblock $error_scriptblock_text} | Should Throw
        }
    }

    Context "when called with a parsing scriptblock" {
        $result = ConvertTo-CallbackScriptblock $working_scriptblock_text
        
        It "should return a scriptblock" {
            $result.GetType().Name | Should Be 'Scriptblock'
        }

        It "should contain a parameter statement" {
            $result.ToString() | Should Match 'param\(\$result\)'
        }

        It "should contain a module import" {
            $result.ToString() | Should Match 'Import-Module posh-httpd'
        }

        It "should contain a call to Invoke-Command" {
            $result.ToString() | Should Match 'Invoke-Command'
        }

        It "should contain a call to ConvertTo-HTTPOutput" {
            $result.ToString() | Should Match 'ConvertTo-HTTPOutput'
        }

        It "should contain a call to `$response.Close()" {
            $result.ToString() | Should Match '\$response.Close\(\)'
        }
        
        It "should contain a try/catch" {
            $result.ToString() | Should Match '(?smi)try.*catch'
        }

        It "should contain the passed in scriptblock" {
            $result.ToString() | Should Match $working_scriptblock_text
        }

        It "should contain a test for OK status" {
            $result.ToString() | Should Match 'if \(\$output_content.StatusCode -ne \[System.Net.HttpStatusCode\]\:\:OK\)'
        }

        It "should contain a test for ContentBytes" {
            $result.ToString() | Should Match 'if \(\$output_content.ContentBytes\)'
        }

        It "should contain a test for ContentStream" {
            $result.ToString() | Should Match 'elseif \(\$output_content.ContentStream\)'
        }

        It "should contain a fail to internalservererror" {
            $result.ToString() | Should Match '\$response.StatusCode = \[System.Net.HttpStatusCode\]\:\:InternalServerError'
        }
    }

}
