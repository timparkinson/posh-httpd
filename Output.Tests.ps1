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
        $result = ConvertTo-HTTPOutput 'blah'
        It "should register an HTTP Output type" {
            [type]"HTTPOutput" | Should Be $true
        }
    }

    Context "when called with an HTTPOutput object" {
        $output = New-Object HTTPOutput
        $output.ContentBytes =  [Text.Encoding]::UTF8.GetBytes('blah')

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

    Context "when called with an IOStream" {
        $bytes = [Text.Encoding]::UTF8.GetBytes('blah')
        $result = ConvertTo-HTTPOutput (New-Object System.IO.MemoryStream (,$bytes))

        It "should return OK status" {
            $result.StatusCode | Should Be $ok_status
        }

        It "should return an object with ContentStream set" {
            $result.ContentStream | Should Not BeNullOrEmpty
        }
    }

    Context "when called with a string" {
        $result = ConvertTo-HTTPOutput 'blah'
        It "should return OK status" {
            $result.StatusCode | Should Be $ok_status
        }

        It "should return an object with ContentBytes set" {
            $result.ContentBytes | Should Not BeNullOrEmpty
        }
    }

    Context "when called with pipelined input" {
        $result = @('blah', 'di blah') | ConvertTo-HTTPOutput

        It "should return OK status" {
            $result.StatusCode | Should Be $ok_status
        }
        It "should return a single object" {
            $result.count | Should Be 1
        }
    }
}

Describe "Get-StatusPage" {
    Setup -File '.\404.html' 'not found'
    $status = [System.Net.HttpStatusCode]::NotFound
    Context "when called with 'not found' status" {
        $result = Get-StatusPage $status -Path 'TestDrive:'
        $expected_result = [Text.Encoding]::UTF8.GetBytes('not found')
        It "should return not found (bytes)" {
            $result | Should Be $expected_result
        }
    }
}