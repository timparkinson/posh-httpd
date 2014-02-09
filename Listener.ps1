﻿function Add-HTTPListener {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        [String]$Prefix,
        [Parameter(Mandatory=$true)]
        [Scriptblock]$Scriptblock,
        [Parameter()]
        [Switch]$Start = $true
    )

    begin {
        if (-not (Test-URLPrefix -Prefix $Prefix)) {
            Write-Error "Prefix is not valid, check registration" -ErrorAction Stop
        }

        if (-not (Test-Path -Path 'VARIABLE:script:HTTP_listeners')) {
            $script:HTTP_listeners = [hashtable]::Synchronized(@{})
        }

        if (-not $script:HTTP_listeners.$Prefix) {
            $script:HTTP_listeners.$Prefix = @{}
        }
    }

    process {
        if (-not $script:HTTP_listeners.$Prefix.RunspacePool) {
            $runspaces = Initialize-HTTPRunspace -Prefix $Prefix -Hash $script:HTTP_listeners
            $script:HTTP_listeners.$Prefix.RunspacePool = $runspaces.Pool
            $script:HTTP_listeners.$Prefix.Powershells = $runspaces.Powershells
            $script:HTTP_listeners.$Prefix.Callback = New-ScriptblockCallBack -Scriptblock $Scriptblock
            $script:HTTP_listeners.$Prefix.Listener = New-Object -TypeName System.Net.HttpListener
            $script:HTTP_listeners.$Prefix.Listener.Prefixes.Add($Prefix)

            if ($Start) {
                Start-HTTPListener -Prefix $Prefix
            }

        } else {
            Write-Error "This prefix listener already exists, consider Remove-HTTPListener" -ErrorAction Stop
        }
        
    }

    end {}
}

function Initialize-HTTPRunspace {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix,
        [Parameter(Mandatory=$true)]
        $Hash,
        [Parameter()]
        [int]$Throttle = 4
    )

    begin {
         $scriptblock = {
            param($Prefix,$HTTP_listener)
            "$(get-date -format 'yyyy-MM-dd HH:mm:ss fffff') In Runspace with $Prefix" >> C:\users\tim\Documents\runspace.log
        }
    }

    process {
        $session_state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $runspace_pool = [RunspaceFactory]::CreateRunspacePool(1, $Throttle, $session_state, $Host)
        $runspace_pool.open()
        $powershells = @()


        0..($Throttle-1) | 
            ForEach-Object {
                $powershells += [powershell]::Create()
                $powershells[$_].RunspacePool = $runspace_pool
                $powershells[$_].AddScript($scriptblock).AddArgument($Prefix).AddArgument($hash)
            }
        

        New-Object -TypeName PSObject -Property @{
            'Pool' = $runspace_pool
            'Powershells' = $powershells
        }
    }

    end {}
}

function Start-HTTPListener {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix
    )

    begin {}

    process {
        if (-not (Test-HTTPListener -Prefix $Prefix)) {
            Write-Error "Problem with finding fully initialised listener for $Prefix" -ErrorAction Stop
        } else {
            $script:HTTP_listeners.$Prefix.Listener.Start()
            $script:HTTP_listeners.$Prefix.Powershells | 
                ForEach-Object {
                    $_.BeginInvoke() | Out-Null
                }
        }
    }

    end {}
}

function Test-HTTPListener {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix
    )

    begin {}

    process {
        if (-not $script:HTTP_listeners.$Prefix.RunspacePool) {
            $false
        } elseif (-not $script:HTTP_listeners.$Prefix.Callback) {
            $false
        } elseif (-not $script:HTTP_listeners.$Prefix.Listener) {
            $false
        } else {
            $true
        }
    }

    end {}
}
        
function Stop-HTTPListener {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix
    )

    begin {}

    process {
        if (-not (Test-HTTPListener -Prefix $Prefix)) {
            Write-Error "Problem with finding fully initialised listener for $Prefix" -ErrorAction Stop
        } else {
            $script:HTTP_listeners.$Prefix.Powershells | 
                ForEach-Object {
                    $_.Stop() | Out-Null
                }
            $script:HTTP_listeners.$Prefix.Listener.Stop()
        }
    }
    
    end {}

}

function Remove-HTTPListener {
    [CmdletBinding()]

    param(
        [Parameter()]
        $Prefix
    )

    begin {
        if(Test-HTTPListenerListening -Prefix $Prefix) {
            Write-Error "Listener is listening, consider Stop-HTTPListener $Prefix"
        }
    }

    process {
        $script:HTTP_listeners.$Prefix.Listener.Close()
        $script:HTTP_listeners.$Prefix.Listener = $null
        $script:HTTP_listeners.$Prefix.Powershells | 
            ForEach-Object {
                $_.Dispose()
            }
        $script:HTTP_listeners.$Prefix.Powershells = $null
        $script:HTTP_listeners.$Prefix.RunspacePool.Dispose()
        $script:HTTP_listeners.$Prefix.RunspacePool = $null
        $script:HTTP_listeners.Remove($Prefix)
    }

    end {}

}

function Test-HTTPListenerListening {
    [CmdletBinding()]

    param(
        [Parameter()]
        $Prefix
    )

    begin {}

    process {
        if ($Script:HTTP_listeners.$Prefix.Listener.IsListening) {
            $true
        } else {
            $false
        }
    }

    end {}
}