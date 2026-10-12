#Requires -Modules ExchangeOnlineManagement

$script:Connected = $false

function Connect-ExchangeTools {

    [CmdletBinding()]
    param()

    if (-not $script:Connected) {

        Connect-ExchangeOnline -ShowBanner:$false

        $script:Connected = $true
    }
}

function Disconnect-ExchangeTools {

    [CmdletBinding()]
    param()

    if ($script:Connected) {

        Disconnect-ExchangeOnline `
            -Confirm:$false

        $script:Connected = $false
    }
}

function Search-MailboxUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm
    )

    Connect-ExchangeTools

    Get-EXOMailbox `
        -ResultSize Unlimited `
        -Properties DisplayName,Alias,PrimarySmtpAddress |
    Where-Object {

        $_.DisplayName -like "*$SearchTerm*" -or
        $_.Alias -like "*$SearchTerm*" -or
        $_.PrimarySmtpAddress -like "*$SearchTerm*"
    } |
    Select-Object `
        DisplayName,
        Alias,
        PrimarySmtpAddress
}

function Get-MailboxUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity
    )

    Connect-ExchangeTools

    Get-EXOMailbox `
        -Identity $Identity `
        -Properties *
}

function Search-DistributionGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm
    )

    Connect-ExchangeTools

    Get-DistributionGroup `
        -ResultSize Unlimited |
    Where-Object {

        $_.DisplayName -like "*$SearchTerm*" -or
        $_.PrimarySmtpAddress -like "*$SearchTerm*"
    } |
    Select-Object `
        DisplayName,
        PrimarySmtpAddress,
        Identity
}

function Get-DistributionGroupDetails {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity
    )

    Connect-ExchangeTools

    Get-DistributionGroup `
        -Identity $Identity
}

function Get-DLMembers {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Group
    )

    Connect-ExchangeTools

    $DL = Get-DistributionGroup `
        -Identity $Group `
        -ErrorAction Stop

    Get-DistributionGroupMember `
        -Identity $DL.Identity `
        -ResultSize Unlimited |
    Select-Object `
        DisplayName,
        PrimarySmtpAddress,
        RecipientType
}

function Add-DLMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Group,

        [Parameter(Mandatory)]
        [string]$Member
    )

    Connect-ExchangeTools

    Add-DistributionGroupMember `
        -Identity $Group `
        -Member $Member `
        -BypassSecurityGroupManagerCheck `
        -ErrorAction Stop
}

function Remove-DLMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Group,

        [Parameter(Mandatory)]
        [string]$Member
    )

    Connect-ExchangeTools

    Remove-DistributionGroupMember `
        -Identity $Group `
        -Member $Member `
        -Confirm:$false `
        -BypassSecurityGroupManagerCheck `
        -ErrorAction Stop
}

function Get-UserDistributionGroups {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserEmail
    )

    Connect-ExchangeTools

    Get-DistributionGroup `
        -ResultSize Unlimited |
    Where-Object {

        (
            Get-DistributionGroupMember `
                -Identity $_.Identity `
                -ResultSize Unlimited `
                -ErrorAction SilentlyContinue
        ).PrimarySmtpAddress -contains $UserEmail

    } |
    Select-Object `
        DisplayName,
        PrimarySmtpAddress
}

Export-ModuleMember -Function @(
    'Connect-ExchangeTools',
    'Disconnect-ExchangeTools',
    'Search-MailboxUser',
    'Get-MailboxUser',
    'Search-DistributionGroup',
    'Get-DistributionGroupDetails',
    'Get-DLMembers',
    'Add-DLMember',
    'Remove-DLMember',
    'Get-UserDistributionGroups'
)