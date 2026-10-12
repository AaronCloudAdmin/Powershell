@{
    RootModule           = 'AD_Users.psm1'
    ModuleVersion        = '1.1.0'
    GUID                 = '51273ec0-6014-4e28-913a-5f2272dd97f1'
    Author               = 'Aaron Holley'
    Copyright            = '(c) Aaron Holley. All rights reserved.'
    Description          = 'Daily Active Directory user tasks: search, unlock, reset, enable/disable, attribute updates.'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    RequiredModules      = @('ActiveDirectory')

    # Explicit lists: faster auto-discovery, and private helpers stay private.
    FunctionsToExport    = @(
        'Search-ADUser'
        'Search-ADUserByAttribute'
        'Get-ADUserDetails'
        'Unlock-User'
        'Reset-UserPassword'
        'Enable-User'
        'Disable-User'
        'Update-UserPhone'
        'Update-UserNotes'
        'Update-UserManager'
        'Update-UserTitle'
        'Get-UserGroups'
        'Get-UserManager'
        'Get-ADDomainDnsRoot'
        'Copy-ADUserFromTemplate'
        'Add-UserLicenseGroups'
        'Update-UserIdentity'
        'Update-UserTitleWithNote'
        'Add-UserNote'
        'Find-ADManagerCandidate'
        'Start-UserLOA'
        'Stop-UserLOA'
        'Get-ADOUList'
        'Move-UserToOU'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags = @('ActiveDirectory', 'Pode', 'Admin')
        }
    }
}
