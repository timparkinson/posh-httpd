posh-httpd
==========

Simple Powershell HTTP module, uses HTTP.sys driver and runs asynchronously. Should be as simple as doing:

```
add-httplistener -prefix 'http://+:8080/' -scriptblock {"<head><title>Hello world!</title><body>HELLO WORLD! at $(Get-Date)</body>"}
```
