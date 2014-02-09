# posh-httpd helper functions

function Test-URLPrefix {
<#
    .SYNOPSIS
        Tests whether a given prefix and user exist

    .DESCRIPTION
        Tests whether a prefix and user exist

    .PARAMETER Prefix
        The prefix to test

    .PARAMETER Username
        The username to test

    .INPUTS
        None

    .OUTPUTS
        Boolean
#>
    [CmdletBinding()]

    param([Parameter(Mandatory=$true)]        
          [String]$Prefix,
          [Parameter()]
          [String]$Username = (Get-CurrentUserName)
    )

    begin {}

    process {
        $url_prefix = Get-URLPrefix | 
            Where-Object {$_.url -eq $Prefix}

        if (-not $url_prefix) {
            $false
        } elseif ($url_prefix.User -ne $Username) {
            $false
        } else {
            $true
        }
    }

    end {}
}

function Get-URLPrefix {
<#
    .SYNOPSIS
        Gets registered URL Prefixes

    .DESCRIPTION
        Gets the registered URL Prefixes using netsh

    .INPUTS
        None

    .OUTPUTS
        PSObject
#>

    [CmdletBinding()]

    param()

    begin {}

    process {
        $netsh_cmd = "netsh http show urlacl"

        $result = Invoke-Expression -Command $netsh_cmd

        $result |
            ForEach-Object {
                if ($_ -match 'Reserved URL\s+\: (?<url>.*)') {
                    $url = $matches.url
                } elseif ($_ -match 'User\: (?<user>.*)') {
                    $user = $matches.user
                    
                    New-Object -TypeName PSObject -Property @{
                        'URL' = $url.Trim()
                        'User' = $user.Trim()
                    }
                }
            }
    }

    end {}

}
