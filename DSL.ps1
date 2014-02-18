﻿# posh-httpd Domain Specific Language
$script:http_methods = @(
    'get',
    'post',
    'put',
    'delete'
)

function New-HTTPRoute {
    [CmdletBinding()]

    param(
        [Parameter()]
        $Pattern,
        [Parameter()]
        $Scriptblock
    )

    begin {
        
    }

    process {
        $method = $MyInvocation.InvocationName

        if ($script:http_methods -inotcontains $method) {
            $method = 'get'
        }

        New-Object -TypeName psobject -Property @{
            'Method' = $method
            'Pattern' = ConvertTo-HTTPRoutePattern -Pattern $Pattern
            'Scriptblock' = $scriptblock
        }
    }

    end {}
}

foreach ($http_method in $script:http_methods) {
    New-Alias -Name $http_method -Value New-HTTPRoute -ErrorAction SilentlyContinue
}

function ConvertTo-HTTPRoutePattern {
    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$true)]
        $Pattern
    )

    begin {}

    process {
        

        $Pattern | 
            Select-String -AllMatches -Pattern '(?<!\?):(\w+)' | 
                ForEach-Object {
                    $_.matches | 
                        ForEach-Object {
                            $param_name = $_.value -replace ':', ''
                    
                            $Pattern = $Pattern -replace ":$param_name", "(?<$param_name>\w+)"    
                        }
                }

        $Pattern | 
            Select-String -AllMatches -Pattern '\?\:(\w+)\?' | 
                ForEach-Object {
                    $_.matches | 
                        ForEach-Object {
                            $param_name = ($_.value -replace '\?', '') -replace ':', ''
                    
                            $Pattern = $Pattern -replace "\?:$param_name\?", "(?<$param_name>\w+)?"    
                        }
                }

        $param_num = 0
        $param_base = 'splatted_param_'
        $Pattern | 
            Select-String -AllMatches -Pattern '\*' | 
                ForEach-Object {
                    
                    $_.matches | 
                        ForEach-Object {
                            $param_num++
                            $param_name = "$param_base$param_num"
                            $regex = [regex]"(?<!$param_base`\d+\>\.)\*" 
                            $Pattern = $regex.Replace($Pattern,"(?<$param_name>.*)",1)

                        }
                }

        $Pattern
    }

    end {}
}

function Get-HTTPRouter {
    [CmdletBinding()]

    param(
        [Parameter()]
        $Path=(Join-Path -path $Pwd -ChildPath 'routes.ps1')
    )

    begin {}

    process {
        $routes = . $Path        
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
        $utf8 = New-Object -TypeName System.Text.UTF8Encoding

        # setup each route as a function
        $setup_scriptblock_as_string = @"
        `$global:routes = @()

        $($routes | 
            ForEach-Object {
                $function_name = "Invoke-HTTPRoute$([System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($_.Pattern))))"
                "`$global:routes += @{'Method'='$($_.Method)';'Pattern'='$($_.Pattern)';'Scriptblock'={$($_.Scriptblock.ToString())};'Function'='$function_name'}"

                @" 

                function $function_name {
                    param(`$request,`$params)
                
                    $($_.Scriptblock.ToString())
                }
"@
            })

"@

        $callback_scriptblock = {
            $matching_route_methods = ($global:routes |
                Where-Object {$_.method -eq $request.HttpMethod})
                   
            if ($matching_route_methods) {
                foreach ($route in $matching_route_methods) {
                    
                    if ($request.RawUrl -match $route.Pattern) {
                        $found_match = $true
                    
                        # setup the parameters
                        $params = @{}
                        $params.splat = @()

                        $route_matches = $matches 
                        $params.splat = $route_matches.keys | 
                            Where-Object {$_ -ne '0' -and $_ -match 'splatted_param_'} |
                                ForEach-Object {
                                    $route_matches.$_
                            }
                            $route_matches.keys | 
                                Where-Object {$_ -ne '0' -and $_ -notmatch 'splatted_param_'} |
                                    ForEach-Object {
                                        $params.$_ = $route_matches.$_
                                    }

                            # call the function
                            
                            try {
                                & $route.Function $request $params
                            
                            } catch {
                                
                                @{
                                    
                                    'Content' = ''
                                    'ContentType' = ''
                                    'StatusCode' = [System.Net.HttpStatusCode]::InternalServerError
                                }
                            }
                                
                            break    
                    } else {
                        $found_match = $false
                    }
                }
                  
            } else {
                $found_match = $false
            }

            if ($found_match -eq $false) {
                @{
                    'Content' = ''
                    'ContentType' = ''
                    'StatusCode' = [System.Net.HttpStatusCode]::NotFound
                }
            }
        }

        New-Object -TypeName psobject -Property @{
            'SetupScriptblock' = [scriptblock]::create($setup_scriptblock_as_string)
            'CallbackScriptblock' = $callback_scriptblock
        }

    }

    end {}
}

function Initialize-HTTPRouter {
    param(
        [Parameter(Mandatory=$true)]
        $Prefix,
        [Parameter()]
        $Path=(Join-Path -path $Pwd -ChildPath 'routes.ps1')
    )

    begin {}

    process {
        $scriptblocks = Get-HTTPRouter -Path $Path

        Add-HTTPListener -Prefix $Prefix -Scriptblock $scriptblocks.CallbackScriptblock -SetupScriptblock $scriptblocks.SetupScriptblock
    }

    end {}
}
