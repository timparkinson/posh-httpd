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

function Get-CurrentUserName {
<#
    .SYNOPSIS
        Gets the username of the current user

    .DESCRIPTION
        Gets the username of the current user in DOMAIN

    .INPUTS
        None

    .OUTPUTS
        String
#>

    [CmdletBinding()]

    param()

    begin {}

    process {
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }

    end {}
}

function Register-URLPrefix {
<#
    .SYNOPSIS
        Registers a URL Prefix

    .DESCRIPTION
        Requires elevated privileges to register a URL prefix using netsh

    .PARAMETER Prefix
        The prefix to register

    .PARAMETER User
        The user (DOMAIN\User) to register the prefix for

    .INPUTS
        None

    .OUTPUTS
        None
#>

    [CmdletBinding()]

    param([Parameter(Mandatory=$true)]
          [String]$Prefix,
          [Parameter()]
          [String]$User=(Get-CurrentUserName)
    )

    begin {
        if (-not (Test-IsAdministrator)) {
            Write-Error -Message  "Elevated privileges required." -ErrorAction Stop
        }
    }

    process {
        $netsh_cmd = "netsh http add urlacl url=$Prefix user=$User"

        Write-Verbose "Registering URL prefix using $netsh_cmd"
        $result = Invoke-Expression -Command $netsh_cmd

        $result -match 'URL reservation successfully added'
    }

    end {}
}
function Test-IsAdministrator {
<#
    .SYNOPSIS
        Tests whether the user is an admistrator.
    
    .DESCRIPTION
        Tests whether the current user is an administrator

    .INPUTS
        None

    .OUTPUTS
        Boolean
#>
    [CmdletBinding()]

    param(
    )

    begin {

    }

    process {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal $User).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }

    end {}
}

function Write-HTTPLog {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix,
        [Parameter(Mandatory=$true)]
        $Message
    )

    begin {   
    }

    process {
        if ($script:HTTP_listeners.$Prefix.LogPath) {
            if ($script:HTTP_listeners.$Prefix.LogMutex) {
                New-Object System.Threading.Mutex $false,"$Prefix`_log_mutex"
            }
        
            $script:HTTP_listeners.$Prefix.LogMutex.WaitOne() | Out-Null
            $Message | Out-File -Append $script:HTTP_listeners.$Prefix.LogPath
            $script:HTTP_listeners.$Prefix.LogMutex.ReleaseMutex()
        }

    }

    end {}
}


function Initialize-HTTPLog {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix,
        [Parameter()]
        [ValidateSet('Access','Debug')]
        $Level = 'Access',
        [Parameter()]
        $Path
    )

    begin {
        $full_path = Join-Path -Path $Path -ChildPath "$Prefix`_$Level.log"
        Write-Verbose "Using path $full_path"

        if (Test-Path $full_path) {
            Write-Verbose "Rolling log file"
            Move-Item -Path $full_path -Destination "$full_path$(get-date -UFormat '%Y%m%d%H%M')"
        }
    
    }

    process {
        if (-not $script:HTTP_Listeners.$Prefix.Logs) {
            $script:HTTP_Listeners.$Prefix.Logs = @{}
        }
        $script:HTTP_Listeners.$Prefix.Logs.$Level = $full_path
    }

    end {}
}