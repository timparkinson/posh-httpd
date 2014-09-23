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
          [Scriptblock]$Scriptblock
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
        Register-ObjectEvent -input $bridge -EventName callbackcomplete -action $Scriptblock -messagedata $args | Out-Null
        Write-Verbose "Invoking callback"
        $bridge.callback
    }

    end {}
}

function ConvertTo-HTTPCallback {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$true)]
        [Scriptblock]$Scriptblock
    )

    begin {
        $wrapper_scriptblock = {
            param($result)


            $callback_state = $result.AsyncState
            if ($callback_state.Logs.Debug) {Write-HTTPLog -Prefix $Prefix -Level Debug -Path $callback_state.Logs.Debug -Message "$(Get-Date -UFormat '%Y-%m-%dT%H:%M:%S') Callback state: $($callback_state | Format-List | Out-String)"}

            $listener =  $callback_state.Listener
            $context = $listener.EndGetContext($result)
            
            $listener.BeginGetContext($callback_state.Callback,$callback_state)
            $response = $context.Response
            $request = $context.Request
            
            if ($callback_state.Logs.Application) {
                $application_log = $callback_state.Logs.Application
            } else {
                $application_log = $null
            }

            try {
                $output_content = Invoke-Command -Scriptblock {
                    param($request, $identity, $application_log)
        
                    REPLACEWITHSCRIPTBLOCK
                    
                } -ArgumentList $request, $context.User, $application_log
                 
            }
            catch {
                $output_content = @{
                    StatusCode = [System.Net.HttpStatusCode]::InternalServerError 
                    Content = "$_"
                    ContentType =''
                }   
            }

            $output_content = $output_content | ConvertTo-HTTPOutput

            $response.StatusCode = $output_content.StatusCode
            if ($output_content.Content) {
                if ($output_content.Content.GetType().BaseType.ToString() -eq  'System.IO.Stream') {
                    $response.ContentLength64 = $output_content.Content.Length
                    $output_content.Content.CopyTo($response.OutputStream)

                } else {

                    $content_bytes = [Text.Encoding]::UTF8.GetBytes($output_content.Content)
                    $response.ContentLength64 = $content_bytes.Length
                    $response.OutputStream.Write($content_bytes, 0, $content_bytes.Length)
                }
            }
            
            if ($callback_state.Logs.Access) {Write-HTTPLog -Prefix $Prefix -Level Access -Path $callback_state.Logs.Access -Message "$(Get-Date -UFormat '%Y-%m-%d %H:%M:%S') server=$($env:COMPUTERNAME) URL=$($request.RawUrl) status=$($response.StatusCode) bytes=$($response.ContentLength64)"}
            $response.close()
        }
    }

    process {
        [scriptblock]::Create($wrapper_scriptblock.ToString().Replace('REPLACEWITHSCRIPTBLOCK',$Scriptblock.ToString()))
    }

    end {}
}