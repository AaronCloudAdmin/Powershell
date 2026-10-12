$env:PSModulePath = "C:\Path;$env:PSModulePath"

Import-Module Pode
Import-Module Pode.Web

Import-Module AD_Users -Force
Import-Module AD_Groups -Force
Import-Module AD_Airlock -Force
Import-Module PortalTools -Force

Start-PodeServer {

    Add-PodeEndpoint `
        -Address localhost `
        -Port 8080 `
        -Protocol Http

    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

    Use-PodeWebTemplates `
        -Title 'IT Admin Portal' -NoPageFilter

    Import-PodeWebJavaScript -Url '/table-filters.js'

    . "$PSScriptRoot\Pages\ActiveDirectory.ps1"

    # . "$PSScriptRoot\Pages\Exchange.ps1"
}