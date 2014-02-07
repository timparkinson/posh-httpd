# posh-httpd helper functions
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

function Test-URLPrefix {
<#
    .SYNOPSIS
        Tests whether a given prefix and user exist

    .DESCRIPTION
        Tests whether a prefix and user exist

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
            Write-Error "Prefix $Prefix not found" -ErrorAction Stop
        } elseif ($url_prefix.User -ne $Username) {
            $false
        } else {
            $true
        }
    }

    end {}
}

function New-ScriptblockCallback {
<#
    .SYNOPSIS
        Allows running ScriptBlocks via .NET async callbacks.
 
    .DESCRIPTION
        Allows running ScriptBlocks via .NET async callbacks. Internally this is
        managed by converting .NET async callbacks into .NET events. This enables
        PowerShell 2.0 to run ScriptBlocks indirectly through Register-ObjectEvent.         
 
    .PARAMETER Callback
        Specify a ScriptBlock to be executed in response to the callback.
        Because the ScriptBlock is executed by the eventing subsystem, it only has
        access to global scope. Any additional arguments to this function will be
        passed as event MessageData.
         
    .EXAMPLE
        You wish to run a scriptblock in reponse to a callback. Here is the .NET
        method signature:
         
        void Bar(AsyncCallback handler, int blah)
         
        ps> [foo]::bar((New-ScriptBlockCallback { ... }), 42)                        
 
    .OUTPUTS
        A System.AsyncCallback delegate.

    .NOTES
        Shamelessly stolen from: http://www.nivot.org/blog/post/2009/10/09/PowerShell20AsynchronousCallbacksFromNET
#>
    [CmdletBinding()]

    param([Parameter(Mandatory=$true)]
          [Scriptblock]$Callback
    )

    begin {
        Write-Verbose -Message "Creating new callback event bridge"
        
        if (-not ("CallbackEventBridge" -as [type])) {
            Write-Verbose -Message "Registering CallBackEventBridge type"
            Add-Type -TypeDefinition @"
            using System;
             
            public sealed class CallbackEventBridge
            {
                public event AsyncCallback CallbackComplete = delegate { };
 
                private CallbackEventBridge() {}
 
                private void CallbackInternal(IAsyncResult result)
                {
                    CallbackComplete(result);
                }
 
                public AsyncCallback Callback
                {
                    get { return new AsyncCallback(CallbackInternal); }
                }
 
                public static CallbackEventBridge Create()
                {
                    return new CallbackEventBridge();
                }
            }
"@
        }
    }

    process {
        Write-Verbose "Creating Event Bridge"
        $bridge = [callbackeventbridge]::create()
        Write-Verbose "Registering Event Bridge"
        Register-ObjectEvent -input $bridge -EventName callbackcomplete -action $Callback -messagedata $args | Out-Null
        Write-Verbose "Invoking callback"
        $bridge.callback
    }

    end {}
}

function ConvertTo-CallbackScriptblock {
<#
.SYNOPSIS
    Wraps a content generation scriptblock in the code necessary to make it an HTTPD callback
.DESCRIPTION
    Wraps a content generation scriptblock in the necessary code to make it an HTTPd callback
.PARAMETER Content 
    The scriptblock which generates the content
.OUTPUTS
    SCriptblock
#>

    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Content
    )

    begin {}

    process {
        $callback_scriptblock = [scriptblock]::Create(@"
    param(`$result)
    
    Import-Module posh-httpd

    `$listener = `$result.AsyncState
    `$context = `$listener.EndGetContext(`$result)
    `$response = `$context.Response
    `$request = `$context.Request

    try {`$output_content = Invoke-Command -Scriptblock {
        param(`$request)
        Import-Module posh-httpd
        $($Content.ToString())} -ArgumentList `$request

    `$output_content = ConvertTo-HTTPOutput -InputObject `$output_content
    } catch {
        Register-HTTPOutputType
        New-Object HTTPOutput

        `$output_content.StatusCode = [System.Net.HttpStatusCode]::InternalServerError
    }

    if (`$output_content.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
        if (-not `$output_content.ContentBytes) {
            `$output_content.ContentBytes = Get-StatusPage -Status `$output_content.StatusCode
        } 
    }

    if (`$output_content.ContentBytes) {
        `$response.StatusCode = `$output_content.StatusCode
        `$response.ContentLength64 = `$output_content.ContentBytes.Length
        `$response.OutputStream.Write(`$output_content.ContentBytes, 0, `$output_content.ContentBytes.Length)  
    } elseif (`$output_content.ContentStream) {
        `$response.StatusCode = `$output_content.StatusCode
        `$output_content.ContentStream.CopyTo(`$response.OutputStream)
    } else {
        `$response.StatusCode = [System.Net.HttpStatusCode]::InternalServerError
    }

    `$response.Close()
"@)
    $callback_scriptblock
    }

    end {}
}