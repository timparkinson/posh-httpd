﻿function Add-HTTPListener {

    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        [String]$Prefix,
        [Parameter(Mandatory=$true)]
        [Scriptblock]$Scriptblock,
        [Parameter()]
        [Scriptblock]$SetupScriptblock,
        [Switch]$Start = $true,
        [Parameter()]
        [Int]$Throttle = 4,
        [Parameter()]
        [System.Net.AuthenticationSchemes]$AuthenticationScheme,
        [Parameter()]
        $Log
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
            $script:HTTP_listeners.$Prefix.Callback =  ConvertTo-HTTPCallback -Scriptblock $scriptblock
            $script:HTTP_listeners.$Prefix.SetupScriptblock = $SetupScriptblock

            #$script:HTTP_listeners.$Prefix.LogPath = $LogPath

            if ($Log) {
                $Log.Keys | 
                    ForEach-Object {
                        Initialize-HTTPLog -Prefix $Prefix -Level $_ -Path $Log.$_
                    }
            }

            if ($script:HTTP_listeners.$Prefix.Logs.Debug) {Write-HTTPLog -Prefix $Prefix -Level Debug -Path $script:HTTP_listeners.$Prefix.Logs.Debug -Message "$(Get-Date -UFormat '%Y-%m-%dT%H:%M:%S') Logs initialised"}

            $runspaces = Initialize-HTTPRunspace -Prefix $Prefix -SharedState $script:HTTP_listeners -Throttle $Throttle
            #$script:HTTP_listeners.$Prefix.RunspacePool = $runspaces.Pool
            $script:HTTP_listeners.$Prefix.Powershells = $runspaces.Powershells
            if ($script:HTTP_listeners.$Prefix.Logs.Debug) {Write-HTTPLog -Prefix $Prefix -Level Debug -Path $script:HTTP_listeners.$Prefix.Logs.Debug -Message "$(Get-Date -UFormat '%Y-%m-%dT%H:%M:%S') Runspaces created"}

            $script:HTTP_listeners.$Prefix.Listener = New-Object -TypeName System.Net.HttpListener
            $script:HTTP_listeners.$Prefix.Listener.Prefixes.Add($Prefix)
            if ($script:HTTP_listeners.$Prefix.Logs.Debug) {Write-HTTPLog -Prefix $Prefix -Level Debug -Path $script:HTTP_listeners.$Prefix.Logs.Debug -Message "$(Get-Date -UFormat '%Y-%m-%dT%H:%M:%S') Listener created"}

            if ($AuthenticationScheme) {
                $script:HTTP_listeners.$Prefix.Listener.AuthenticationSchemes = $AuthenticationScheme
            }

            if ($Start) {
                Start-HTTPListener -Prefix $Prefix
                if ($script:HTTP_listeners.$Prefix.Logs.Debug) {Write-HTTPLog -Prefix $Prefix -Level Debug -Path $script:HTTP_listeners.$Prefix.Logs.Debug -Message "$(Get-Date -UFormat '%Y-%m-%dT%H:%M:%S') Listener started"}
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
        $SharedState,
        [Parameter()]
        [int]$Throttle = 4
    )

    begin {
         $scriptblock = {
            param($Prefix,$SharedState)           
            
            if ($SharedState.$Prefix.SetupScriptblock) {
                Invoke-Command -NoNewScope -ScriptBlock $SharedState.$Prefix.SetupScriptblock
            }
            

            $callback = New-ScriptblockCallBack -Scriptblock $SharedState.$Prefix.Callback
            

            $callback_state = New-Object -TypeName psobject -Property @{
                'Listener' = $SharedState.$Prefix.Listener
                'Callback' = $callback
                'Prefix' = $Prefix
                'Logs' = $SharedState.$Prefix.Logs
            }
            #$callback_state = $SharedState.$Prefix
                        
            $result = $SharedState.$Prefix.Listener.BeginGetContext($callback,$callback_state)

            while ($SharedState.$Prefix.Listener.Listening) {
                Start-Sleep -Seconds 1
            }
         }

    }

    process {
        $session_state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        #$runspace_pool = [RunspaceFactory]::CreateRunspacePool(1, $Throttle, $session_state, $Host)
        #$runspace_pool.Open()
        $powershells = @()

        0..($Throttle-1) | 
            ForEach-Object {
                $powershells += [powershell]::Create()
                #$powershells[$_].RunspacePool = $runspace_pool
                $powershells[$_].AddScript($scriptblock).AddArgument($Prefix).AddArgument($SharedState)
                $powershells[$_].Runspace = [RunspaceFactory]::CreateRunspace($session_state).Open()
            }
        

        New-Object -TypeName PSObject -Property @{
            #'Pool' = $runspace_pool
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
        if (-not $script:HTTP_listeners.$Prefix.Powershells) {
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
        #$script:HTTP_listeners.$Prefix.RunspacePool.Dispose()
        #$script:HTTP_listeners.$Prefix.RunspacePool = $null
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

function Restart-HTTPListener {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        $Prefix
    )

    begin {}

    process {
        Stop-HTTPListener -Prefix $Prefix
        Start-HTTPListener -Prefix $Prefix
    }  
    
    end {}
}