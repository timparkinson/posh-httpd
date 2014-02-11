$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"
. "$here\Helpers.ps1"
. "$here\Callback.ps1"

Describe "Add-HTTPListener" {
    $prefix = 'http://someprefix:8080/'
    $scriptblock = {'blah'}

    Context "when called with a valid, existing prefix" {
        Mock Test-URLPrefix {$true}
        Mock Initialize-HTTPRunspace {
            [pscustomobject]@{
                Pool = 'pool'
                Powershells = 'ps'
            }
        }
        Mock Start-HTTPListener {}

        Add-HTTPListener -Prefix $prefix -scriptblock $scriptblock

        It "should call Test-URLPrefix" {
            Assert-MockCalled -commandName Test-URLPrefix
        }

        It "should call Initialize-HTTPRunspace" {
            Assert-MockCalled -commandName Initialize-HTTPRunspace
        }

        It "should call Start-HTTPListener" {
            Assert-MockCalled -commandName Start-HTTPListener
        }


        It "should ensure HTTP_listeners variable exists" {
            'variable:script:HTTP_listeners' | Should Exist
        }

        #It "should set a prefix variable" {
        #    "variable:script:HTTP_listeners.$Prefix" | Should Exist
        #}

        It "should set the Listener variable" {
            $script:HTTP_listeners.$Prefix.Listener | Should Not BeNullOrEmpty
        }

        It "should set the Powershells variable" {
            $script:HTTP_listeners.$Prefix.Powershells | Should Not BeNullOrEmpty
        }
    }

    Context "when called with a non-existent prefix" {
        Mock Test-URLPrefix {$false}

        It "should throw an error" {
            {Add-HTTPListener -Prefix $prefix -scriptblock $scriptblock} | Should Throw
        }
    }

    Context "when the listener already exists" {
        Mock Test-URLPrefix {$true}
        $script:HTTP_listeners.$Prefix.RunspacePool = 'blah'
        It "should throw an error" {
            {Add-HTTPListener -Prefix $prefix -scriptblock $scriptblock} | Should Throw
        }
    }

    
}

Describe "Initialize-HTTPRunspace" {
    $prefix = 'http://someprefix:8080/'
    $hash = @{}

    Context "when called" {

        $return = Initialize-HTTPRunspace -Prefix $prefix -SharedState $hash

        It "should return an array of Powershells" {
            $return.Powershells.GetType().Name | Should Be "Object[]"
        }
    }
}

Describe "Start-HTTPListener" {
    $prefix = 'http://someprefix:8080/'
    Context "when called with an invalid or uninitialized prefix" {
        Mock Test-HTTPListener {$false}
    
        It "should throw an error" {
            {Start-HTTPListener -Prefix $prefix} | Should Throw
        }
    }
}

Describe "Stop-HTTPListener" {
    $prefix = 'http://someprefix:8080/'

    Context "when called with an invalid or uninitialized prefix" {
        Mock Test-HTTPListener {$false}
    
        It "should throw an error" {
            {Stop-HTTPListener -Prefix $prefix} | Should Throw
        }
    }
}

Describe "Restart-HTTPListener" {
    $prefix = 'http://someprefix:8080/'

    Mock -verifiable Start-HTTPListener {}
    Mock -verifiable Stop-HTTPListener {}

    Restart-HTTPListener -Prefix $Prefix

    Context "when called" {
        It "should run start and stop" {
            Assert-VerifiableMocks
        }
    }
}

