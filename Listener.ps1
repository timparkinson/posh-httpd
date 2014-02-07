# posh-httpd Listener functions

function Invoke-HTTPListener {
<#
.SYNOPSIS 
    Starts an HTTP Listener
.DESCRIPTION
    Starts an HTTP Listener at the specified prefix and using the specified content scriptblock to (asynchronously) handle content generation
.PARAMETER Prefix
    The URL Prefix to use, must be pre-registered on the machine
.PARAMETER Content
    A scriptblock which generates the content
.PARAMETER Timeout
    The timeout in milliseconds on the listener - without this the listener cannot be stopped
.NOTES
    Not meant to be called directly, ideally called from a wrapper which checks for validity of the prefix, etc
#>
    [CmdletBinding()]
    
    param(
        [Parameter(Mandatory=$true)]
        [String]$Prefix,
        [Parameter(Mandatory=$true)]
        $Content,
        [Parameter()]
        [int32]$Timeout = 5000
    )

    begin {
        $callback_scriptblock = ConvertTo-CallbackScriptblock -Content $Content
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
            $result.AsyncWaitHandle.WaitOne($Timeout);
        }
    }

    end {
        $listener.stop()
    }
}

function Test-HTTPDPrefix {
<#
.SYNOPSIS
    Tests whether a given prefix exists in the running prefixes variable
.DESCRIPTION
    Tests whether a given prefix exists in the running prefixes variable (script scope)
.PARAMETER Prefix
    The prefix to test
#>
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix
    )

    begin {}

    process {
        if ($script:HTTPDPrefixes.$Prefix) {
            $true
        } else {
            $false
        }
    }

    end {}
}

function Start-HTTPD {
<#
.SYNOPSIS
    Starts an HTTP Listener
.DESCRIPTION
    Invokes an HTTP Listener with the given prefix and content generation scriptblock.
.PARAMTER Prefix
    The URL Prefix to use
.PARAMETER Content
    The content generation scriptblock
#>
    [CmdletBinding()]

    param(
        [Parameter()]
        $Prefix = 'http://+:8080/',
        [Parameter()]
        [Scriptblock]$Content = {
            "<head><title>Hello world!</title><body>HELLO WORLD! at $(Get-Date)</body>"
          }
    )

    begin {
        Write-Verbose "Checking prefix"
        if (-not (Test-IsAdministrator) -and -not (Test-URLPrefix -Prefix $Prefix)) {
            Write-Error -Message "Cannot run without defined prefix or elevated privileges. Try Register-URLPrefix from an elevated shell."
        }

        if (-not (Test-Path -Path VARIABLE:SCRIPT:HTTPDPrefixes)) {
            Write-Verbose -Message "Creating tracking variable"
            $Script:HTTPDPrefixes = @{}
        }

        if (Test-HTTPDPrefix -Prefix $Prefix) {
            Write-Error "HTTP Server already running. Consider Stop-HTTPD" -ErrorAction Stop
        } 
    }

    process {
        Write-Verbose "Starting server $Prefix"
        $Script:HTTPDPrefixes.$Prefix = Start-Job -Name "HTTP_Listener_$Prefix" -ScriptBlock {Invoke-HTTPListener -Prefix $args[0] -Content $args[1] -Verbose} -ArgumentList @($Prefix,$Content)
    }

    end {}


}

function Stop-HTTPD {
<#
.SYNOPSIS
    Stops an HTTP Listener
.DESCRIPTION
    Stops an HTTP Listener
.PARAMETER Prefix
    The URL Prefix to use
#>
    [CmdletBinding()]

    param(
        [Parameter()]
        $Prefix = 'http://+:8080/'
    )

    begin {}

    process {
        Write-Verbose "Checking Prefix $Prefix"
        if ((Test-HTTPDPrefix -Prefix $Prefix)) {
            Write-Verbose "Stopping listener"
            Stop-Job -Job  $Script:HTTPDPrefixes.$Prefix
            $Script:HTTPDPrefixes.Remove($Prefix)

        } else {
            Write-Error "Prefix $Prefix is not present." -ErrorAction Stop
        }
    }

    end {}
}

function Restart-HTTPD {
<#
.SYNOPSIS
    Stops an HTTP Listener
.DESCRIPTION
    Stops an HTTP Listener
.PARAMETER Prefix
    The URL Prefix to use
#>
    [CmdletBinding()]

    param(
        [Parameter()]
        $Prefix = 'http://+:8080/'
    )

    begin {}

    process {
        Stop-HTTPD -Prefix $Prefix
        Start-HTTPD -Prefix $Prefix
    }

    end {}
}