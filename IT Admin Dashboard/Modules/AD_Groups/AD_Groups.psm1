#Requires -Modules ActiveDirectory

<#
    AD_Groups
    Group membership tasks.
      - list the user's groups (CN names from MemberOf)
      - find groups by name (first 20 matches)
      - add / remove the user

    Errors are not swallowed (-ErrorAction Stop), and changes ask (y/n)
    at the prompt unless -Force is used (the web page passes -Force).
#>

$script:DefaultDC = '____'

function Confirm-ADAction {
    param([Parameter(Mandatory)][string]$Message)
    $answer = Read-Host "$Message (y/n)"
    if ($answer -match '^(y|yes)$') { return $true }
    Write-Warning 'Cancelled. No changes made.'
    return $false
}

function Get-UserGroupNames {
    <# The user's groups as CN names. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [string]$Server = $script:DefaultDC
    )

    (Get-ADUser -Identity $SamAccountName -Properties MemberOf -Server $Server -ErrorAction Stop).MemberOf |
    ForEach-Object { ($_ -split ',')[0].Replace('CN=', '') }
}

function Find-ADGroupName {
    <# "Find Group": group names containing the text, first 20. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SearchTerm,
        [string]$Server = $script:DefaultDC
    )

    $term = $SearchTerm.Trim().Replace("'", "''")

    Get-ADGroup -Filter "Name -like '*$term*'" -Server $Server -ErrorAction Stop |
    Select-Object -First 20 |
    ForEach-Object { $_.Name }
}

function Add-UserToGroup {
    <# "Add": adds the user to the group. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$GroupName,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Add $SamAccountName to '$GroupName'?")) { return }

    Add-ADGroupMember -Identity $GroupName -Members $SamAccountName -Server $Server -ErrorAction Stop
    [PSCustomObject]@{ SamAccountName = $SamAccountName; Group = $GroupName; Change = 'Added' }
}

function Remove-UserFromGroup {
    <# "Remove": removes the user from the group (no AD confirmation prompt). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$GroupName,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Remove $SamAccountName from '$GroupName'?")) { return }

    Remove-ADGroupMember -Identity $GroupName -Members $SamAccountName -Confirm:$false -Server $Server -ErrorAction Stop
    [PSCustomObject]@{ SamAccountName = $SamAccountName; Group = $GroupName; Change = 'Removed' }
}

Export-ModuleMember -Function 'Get-UserGroupNames', 'Find-ADGroupName', 'Add-UserToGroup', 'Remove-UserFromGroup'