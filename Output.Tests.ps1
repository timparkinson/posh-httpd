$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"

Describe "Register-HTTPOutputType" {

    Context "when called" {
        Register-HTTPOutputType 
        $expected_type = 'HTTPOutput'
        
        It "should have an $expected_type type available" {
            [type]"HTTPOutput" | Should Be $true
        }
    }
}

Describe "ConvertTo-HTTPOutput" {
    $expected_content_type = 'text/html'
    $ok_status = [System.Net.HttpStatusCode]::OK
    $error_status = [System.Net.HttpStatusCode]::InternalServerError

    Context "when called" {
    
        Mock -verifiable Register-HTTPOutputType {}

        Register-HTTPOutputType

        It "should register an output type" {
            Assert-VerifiableMocks
        }
    }

    Context "when called with an HTTPOutput object" {
        $output = New-Object HTTPOutput
        $output.Content = 'blah'

        $result = ConvertTo-HTTPOutput $output
        It "should return the object" {
            $result.GetType().Name | Should Be 'HTTPOutput'
        }

        It "should return OK status when status is not set" {
            $result.StatusCode | Should Be $ok_status
        }

        It "should return the expected content type if not set" {
            $result.ContentType | Should Be $expected_content_type
        }

        $output.StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        $output.ContentType = 'text/plain'
        $result = ConvertTo-HTTPOutput $output

        It "should return the original status code when it is set" {
            $result.StatusCode | Should Be $error_status
        }

        It "should return the original content type when it is set" {
            $result.ContentType | Should Be $output.ContentType
        }
    }

    Context "when called with a string" {
        $result = ConvertTo-HTTPOutput 'blah'
        It "should return OK status" {
            $result.StatusCode | Should Be $ok_status
        }

        It "should return an object with Content set" {
            $result.Content | Should Not BeNullOrEmpty
        }
    }

    Context "when called with a hash containing Content,ContentType" {
        $expected_content_type = 'text/plain'
        $content = 'blah'
        
        $result = ConvertTo-HTTPOutput @{
                                            'ContentType'=$expected_content_type
                                            'Content'=$content
                                         }
        It "should return an object" {
            $result.GetType().Name | Should Be 'HTTPOutput'    
        }

        It "should return the correct content type" {
            $result.ContentType | Should Be $expected_content_type
        }
        
        It "should return the correct content" {
            $result.Content | Should Be $content
        } 
        
    }

    Context "when called with a pipeline" {
        $result = @('blah', 'di blah') | ConvertTo-HTTPOutput
        $expected_result = @('blah', 'di blah') | Out-String

        It "should return a single object" {
            $result.count | Should Be 1
        }

        It "should return a representation of all of the objects" {
            $result.Content | Should Be $expected_result
        }
    }

    Context "when called with a null input" {
        $result = convertto-httpoutput $null

        It "should return a server error" {
            $result.StatusCode | Should Be  ([System.Net.HttpStatusCode]::InternalServerError.ToString())
        }
    }

    Context "when called with content, but no status" {
        $result = convertto-httpoutput 'blah'

        It "should return OK status" {
            $result.StatusCode | Should Be  ([System.Net.HttpStatusCode]::OK.ToString())
        }
    }
}
