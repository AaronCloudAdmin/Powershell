@{
    RootModule           = 'PortalTools.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a3f2c7d1-6b4e-4f8a-9c21-5e7d0b3a9f64'
    Author               = 'Aaron Holley'
    Copyright            = '(c) Aaron Holley. All rights reserved.'
    Description          = 'Shared helpers for the IT Admin Portal: portal logging and logged toasts.'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Write-PortalLog'
        'Show-PortalToast'
        'Move-PortalBack'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}