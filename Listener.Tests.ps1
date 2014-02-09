$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"

Describe "Add-HTTPListener" {
    $prefix = 'http://someprefix:8080/'
    $scriptblock = {'blah'}

    Context "when called with a valid, existing prefix" {
        Mock Test-URLPrefix {$true}
        Mock Initialize-HTTPDRunspace {}

        Add-HTTPListener -Prefix $prefix -scriptblock $scriptblock

        It "should call Test-URLPrefix" {
            Assert-MockCalled -commandName Test-URLPrefix
        }

        It "should call Initialize-HTTPRunspace" {
            Assert-MockCalled -commandName
        }
    }

    Context "when called with a non-existent prefix" {
        Mock Test-URLPrefix {$false}

        It "should throw an error" {
            {Add-HTTPListener} | Should Throw
        }
    }
}