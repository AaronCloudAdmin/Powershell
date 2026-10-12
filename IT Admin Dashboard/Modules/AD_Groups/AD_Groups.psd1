@{
    RootModule           = 'AD_Groups.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'c6e1b2a4-8d3f-4e5a-b7c9-0f1d2e3a4b5c'
    Author               = 'Aaron Holley'
    Copyright            = '(c) Aaron Holley. All rights reserved.'
    Description          = 'Active Directory group membership tasks (Edit Groups).'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    RequiredModules      = @('ActiveDirectory')

    FunctionsToExport    = @(
        'Get-UserGroupNames'
        'Find-ADGroupName'
        'Add-UserToGroup'
        'Remove-UserFromGroup'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}