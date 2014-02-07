# posh-httpd module
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Get-ChildItem -Path "$here\*" -Include "*.ps1" -Exclude "*.Tests.ps1" |
    ForEach-Object {
        . $_.FullName
    }
