@{
    RootModule           = 'AD_Airlock.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'e2f4a6c8-1b3d-4f5e-9a7c-2d4f6b8e0a1c'
    Author               = 'Aaron Holley'
    Copyright            = '(c) Aaron Holley. All rights reserved.'
    Description          = 'DISABLE and AIRLOCK: disable, strip groups, clear org fields, move to Disabled Users OU.'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    RequiredModules      = @('ActiveDirectory')

    FunctionsToExport    = @('Invoke-UserAirlock')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}