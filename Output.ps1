# posh-httpd output conversion functions

function Register-HTTPOutputType {

    process {
        if (-not ("HTTPOutput" -as [type])) {
            Write-Verbose -Message "Registering HTTPOutput type"
            
            Add-Type -TypeDefinition @"
            using System;
            using System.Net;
            using System.IO;
             
            public class HTTPOutput
            {
                public String ContentType;

                public HttpStatusCode StatusCode;

                public Byte[] ContentBytes;

                public Stream ContentStream;
            }
"@
        }        
    }
}

function ConvertTo-HTTPOutput {
<#
    .SYNOPSIS
        Tries to convert output into something sensible
    
    .DESCRIPTION
        Makes guesses at what the output being returned is, and tries to convert it to an object with status attached, etc.

    .PARAMETER InputObject
        The object to convert into an HTTP Output object

    .INPUTS
        Object

    .OUTPUTS
        HTTPOutput
#>
    [CmdletBinding()]

    param([Parameter(Mandatory=$true,
                     ValueFromPipeline=$true)]
          $InputObject
    )

    begin {
        Register-HTTPOutputType
    }

    end {
        if($InputObject.GetType().Name -eq 'HTTPOutput') {
            Write-Verbose -Message "Already an HTTP output object"   
            $output = $InputObject
        } else {
            Write-Verbose "Creating output object"
            $output = New-Object -TypeName HTTPOutput


            if ($InputObject.GetType().BaseType.ToString() -eq  'System.IO.Stream') {
               $output.ContentStream = $InputObject 
            }


            elseif ($InputObject.GetType().Name -eq 'String') {
                $output.ContentBytes =  [Text.Encoding]::UTF8.GetBytes($InputObject)
            }  

            else {

                $output.ContentBytes =  [Text.Encoding]::UTF8.GetBytes(($InputObject | Out-String))
            }
        }

        if (-not $output.ContentType) {
            Write-Verbose "Adding a content type"
            $output.ContentType = 'text/html'
        }

        if ($output.StatusCode.ToString() -eq '0') {
            Write-Verbose "Adding status code"
            $output.StatusCode = [System.Net.HttpStatusCode]::OK

        }
        $output

        
    }



}

function Get-StatusPage {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpStatusCode]$Status,
        [Parameter()]
        $Path = $PSScriptRoot,
        [Parameter()]
        $Extension = '.html'
    )

    begin {
        Register-HTTPOutputType
    }

    process {
        $file_path = Join-Path -Path $Path -ChildPath "$($Status.value__)$Extension"

        if (Test-Path -Path $file_path) {
            [Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Path $file_path))
        } else {
            $false
        }
    }

    end {}
}


