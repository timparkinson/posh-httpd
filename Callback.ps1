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

            $shared_state = $result.AsyncState
            $listener =  $shared_state.Listener
            $context = $listener.EndGetContext($result)
            $listener.BeginGetContext($shared_state.Callback,$shared_state)
            $response = $context.Response
            $request = $context.Request

            $output_content = New-Object -TypeName PSObject -Property @{
                StatusCode = New-Object -TypeName System.Net.HttpStatusCode
                Raw = $null
            }

            try {
                $output_content.Raw = Invoke-Command -Scriptblock {
                    param($request)
        
                    REPLACEWITHSCRIPTBLOCK
                    
                } -ArgumentList $request
                 $output_content.StatusCode = [System.Net.HttpStatusCode]::OK
            }
            catch {
                $output_content.StatusCode = [System.Net.HttpStatusCode]::InternalServerError    
            }

            "$(get-date -format 'yyyy-MM-dd HH:mm:ss fffff') output $($output_content | ft | Out-String)" >> C:\users\tim\Documents\callback.log

            $response.StatusCode = $output_content.StatusCode
            $content_bytes = [Text.Encoding]::UTF8.GetBytes($output_content.Raw)
            $response.ContentLength64 = $content_bytes.Length
            $response.OutputStream.Write($content_bytes, 0, $content_bytes.Length)
            $response.close()
        }
    }

    process {
        [scriptblock]::Create($wrapper_scriptblock.ToString().Replace('REPLACEWITHSCRIPTBLOCK',$Scriptblock.ToString()))

    }

    end {}
}