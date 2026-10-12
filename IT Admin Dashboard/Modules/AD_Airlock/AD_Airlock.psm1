#Requires -Modules ActiveDirectory

<#
    AD_Airlock
    DISABLE and AIRLOCK:
      1. Disable the account
      2. Remove every group except "Domain Users"
      3. Append the note (required) to Telephone Notes
      4. Clear Title, Department, Company, Office and Manager (only the ones that have a value)
      5. Move the user to the "___" OU


#>

$script:DefaultDC = '_____'

function Confirm-ADAction {
    param([Parameter(Mandatory)][string]$Message)
    $answer = Read-Host "$Message (y/n)"
    if ($answer -match '^(y|yes)$') { return $true }
    Write-Warning 'Cancelled. No changes made.'
    return $false
}

function Invoke-UserAirlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Note,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Note)) {
        throw 'Notes are required to proceed. Action cancelled.'
    }

    if (-not $Force -and -not (Confirm-ADAction "Are you sure you want to disable $SamAccountName and move them to '___' OU?")) { return }

    $warnings = [System.Collections.Generic.List[string]]::new()

    # 1. Disable
    Disable-ADAccount -Identity $SamAccountName -Server $Server -ErrorAction Stop
    $u = Get-ADUser -Identity $SamAccountName -Properties MemberOf, DistinguishedName, info -Server $Server -ErrorAction Stop

    # 2. Remove all groups except Domain Users
    foreach ($g in $u.MemberOf) {
        try {
            $groupObj = Get-ADGroup -Identity $g -Server $Server -ErrorAction Stop
            if ($groupObj.Name -ne 'Domain Users') {
                Remove-ADGroupMember -Identity $g -Members $u.DistinguishedName -Confirm:$false -Server $Server -ErrorAction Stop
            }
        }
        catch { $warnings.Add("Group '$g': $($_.Exception.Message)") }
    }

    # 3. Append note (isolated so it cannot block the OU move)
    try {
        $updatedNotes = "$($u.info)$([Environment]::NewLine)$Note".Trim()
        Set-ADUser -Identity $SamAccountName -Replace @{ info = $updatedNotes } -Server $Server -ErrorAction Stop
    }
    catch { $warnings.Add("Notes: $($_.Exception.Message)") }

    # 4. Clear org fields that have a value
    try {
        $uOrg = Get-ADUser -Identity $SamAccountName -Properties Title, Department, Company, Manager, physicalDeliveryOfficeName -Server $Server -ErrorAction Stop
        $clearAttribs = @()
        if ($uOrg.Title) { $clearAttribs += 'title' }
        if ($uOrg.Department) { $clearAttribs += 'department' }
        if ($uOrg.Company) { $clearAttribs += 'company' }
        if ($uOrg.physicalDeliveryOfficeName) { $clearAttribs += 'physicalDeliveryOfficeName' }
        if ($uOrg.Manager) { $clearAttribs += 'manager' }
        if ($clearAttribs.Count -gt 0) { Set-ADUser -Identity $SamAccountName -Clear $clearAttribs -Server $Server -ErrorAction Stop }
    }
    catch { $warnings.Add("Org fields: $($_.Exception.Message)") }

    # 5. Move to ___
    $air = Get-ADOrganizationalUnit -Filter "Name -eq '___'" -Server $Server -ErrorAction Stop
    Move-ADObject -Identity $u.DistinguishedName -TargetPath $air.DistinguishedName -Server $Server -ErrorAction Stop

    [PSCustomObject]@{
        SamAccountName = $SamAccountName
        MovedTo        = $air.DistinguishedName
        Warnings       = @($warnings)
    }
}

Export-ModuleMember -Function 'Invoke-UserAirlock'