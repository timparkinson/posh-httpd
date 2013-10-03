# Powershell Simple HTTP Server

#region Start/Stop functions
function Start-HTTPListener {
<#
.SYNOPSIS
    Starts an HTTP Listener
.DESCRIPTION
    Invokes an HTTP Listener with the given prefix and content generation scriptblock.
.PARAM Prefix
    The URL Prefix to use
.PARAM Content
    The content generation scriptblock
#>
    [CmdletBinding()]

    param(
        [Parameter()]
        $Prefix = 'http://+:8080/',
        [Parameter()]
        [Scriptblock]$Content = {
            "<head><title>Hello world!</title><body>HELLO WORLD!</body>"
          }
    )

    begin {
        Write-Verbose "Checking prefix"
        if (-not (Test-IsAdministrator) -and -not (Test-URLPrefix -Prefix $Prefix)) {
            Write-Error -Message "Cannot run without defined prefix or elevated privileges. Try Register-URLPrefix from an elevated shell."
        }

        if (-not (Test-Path -Path VARIABLE:SCRIPT:HTTPListener)) {
            Write-Verbose -Message "Creating tracking variable"
            $Script:HTTPListener = @{}
        } else {
            Write-Verbose -Message "Checking tracking variable"
            if ($Script:HTTPListener.$Prefix) {
                Write-Error "HTTP Server already running. Consider Stop-HTTPListener."
            }
        }
    }

    process {
        Write-Verbose "Starting server $Prefix"
        #$Script:HTTPListener.$Prefix = [powershell]::Create() 
        #$Script:HTTPListener.$Prefix.AddCommand('Invoke-HTTPListener') | Out-Null
        #$Script:HTTPListener.$Prefix.AddParameter('Prefix', $Prefix) | Out-Null
        #$Script:HTTPListener.$Prefix.AddParameter('Content', $Content) | Out-Null
        #$Script:HTTPListener.$Prefix.BeginInvoke()
        Write-Verbose "Content scriptblock $Content"
        $Script:HTTPListener.$Prefix = Start-Job -Name "HTTP_Listener_$Prefix" -ScriptBlock {Invoke-HTTPListener -Prefix $args[0] -Content $args[1] -Verbose} -ArgumentList @($Prefix,$Content)
    }

    end {}

}

function Stop-HTTPListener {
    [CmdletBinding()]

    param(
        [Parameter()]
        [String]$Prefix = 'http://+:8080/'
    )

    begin {}

    process {
        Write-Verbose "Checking Prefix $Prefix"
        if ($Script:HTTPListener.$Prefix) {
            Write-Verbose "Stopping listener"
            Stop-Job -Job  $Script:HTTPListener.$Prefix
            $Script:HTTPListener.Remove($Prefix)

        } else {
            throw "Prefix $Prefix is not present."
        }
    }

    end {}
}

function Restart-HTTPListener {
}

function Invoke-HTTPListener {
<#
.SYNOPSIS
    Starts an HTTP Listener
.DESCRIPTION
    Starts an HTTP Listener on the specified URL prefix and bound to the specified scriptblock for content generation
.PARAM Prefix
    A Mandatory prefix 
.PARAM Content
    A Scriptblock which generates the content
.NOTES
    Ideally called by Start-HTTPListener, which does some checks on the prefix, etc
#>

    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        [String]$Prefix,
        [Parameter(Mandatory=$true)]
        $Content
    )

    begin {
        Write-Verbose "Content scriptblock is: $Content"


        $callback_scriptblock = [scriptblock]::Create(@"
    param(`$result)
    
    "`$(get-date) callback Started" >> C:\Users\cs1trp\Documents\scratch\debug.log
   `$listener = `$result.AsyncState
   `$context = `$listener.EndGetContext(`$result)
   `$response = `$context.Response
   `$request = `$context.Request
   "`$(get-date) got state of request and response" >> C:\Users\cs1trp\Documents\scratch\debug.log
   "`$(get-date) `$listener" >> C:\Users\cs1trp\Documents\scratch\debug.log
   "`$(get-date) `$context" >> C:\Users\cs1trp\Documents\scratch\debug.log
   "`$(get-date) `$response" >> C:\Users\cs1trp\Documents\scratch\debug.log
   "`$(get-date) `$request" >> C:\Users\cs1trp\Documents\scratch\debug.log

   `$response.ContentType = 'text/plain'

    `$output_content = & {$($Content.ToString())}
   
    [byte[]] `$buffer = [System.Text.Encoding]::UTF8.GetBytes(`$output_content)
    `$response.ContentLength64 = `$buffer.length
    `$output = `$response.OutputStream
    `$output.Write(`$buffer, 0, `$buffer.length)
    `$output.Close()

"@)
    
    }

    process {
        $listener = New-Object -TypeName Net.HTTPListener
        
        Write-Verbose -Message "Adding $Prefix to listener"
        $listener.Prefixes.Add($Prefix)

        Write-Verbose -Message "Starting Listener"
        $listener.Start()

        Write-Verbose -Message "Registering Asynchronous callback"
        Write-Verbose $callback_scriptblock.ToString()
        $callback = New-ScriptblockCallback -Callback $callback_scriptblock

        Write-Verbose "callback registered"
        Write-Verbose "waiting for result"
        
        while ($true) {
            $result = $listener.BeginGetContext(($callback), $listener)
            $result.AsyncWaitHandle.WaitOne([timespan]'0:0:5');
        }
        
    }

    end {
        $listener.stop()
    }

}
#endregion

#region Helper functions
#requires -version 2.0
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
        Invoke-Expression -Command $netsh_cmd
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

        $i = 0
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
#endregion