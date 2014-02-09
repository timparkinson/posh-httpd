$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"

Describe "Test-URLPrefix" {
    $prefix = 'http://someprefix:8080/'
    $user = 'user'

    Context "when called against a valid prefix/user pair" {
        Mock Get-URLPrefix {
            @{
                url = $prefix
                user = $user
            }
        }

        $result = Test-URLPrefix -Prefix $prefix -User $user

        It "should return $true" {
            $result | Should Be $true
        }
    }

    Context "when called against a non-existing prefix" {
        Mock Get-URLPrefix {
            @{
                url = "$prefix`NOTEXIST"
                user = $user
            }
        }

        $result = Test-URLPrefix -Prefix $prefix -User $user

        It "should return $false" {
            $result | Should Be $false
        }
    }

    Context "when called against an invalid user" {
        Mock Get-URLPrefix {
            @{
                url = "$prefix"
                user = "$user`NOTEXIST"
            }
        }

        $result = Test-URLPrefix -Prefix $prefix -User $user

        It "should return $false" {
            $result | Should Be $false
        }
    } 
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