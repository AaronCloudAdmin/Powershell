# Define the OU path
$ClinicsOU = "OU=Clinics,DC=yourdamin,DC=com"

# Get users with job title "Center Manager, Health Center Lead Clincian, or Lead RN" in the Clinics OU
$users = Get-ADUser -Filter {
    (Title -like "*Manager*") -or
    (Title -like "*Lead Clinician*") -or
    (Title -like "*Lead RN*") -or
    (Title -like "*Lead Registered Nurse*")
    } -SearchBase $ClinicsOU -Properties SamAccountName

# Export to CSV
$users | Select-Object SamAccountName | Export-Csv -Path "C:\NewE5users.csv" -NoTypeInformation

# Define E3 group name or DN
$E3Group = "CN=M365 - E3 Users,OU=sample,DC=yourdomain,DC=com"
$E5Group = "CN=M365 - E5 Users,OU=sample,DC=yourdomain,DC=com"

# Import CSV
$users = Import-Csv -Path "C:\NewE5users.csv"

foreach ($user in $users) {
    $sam = $user.SamAccountName
    $adUser = Get-ADUser -Identity $sam

    if ($adUser) {
        # Remove from E3 group if already a member
        if (Get-ADGroupMember -Identity $E3Group | Where-Object { $_.SamAccountName -eq $sam }) {
            Remove-ADGroupMember -Identity $E3Group -Members $adUser -Confirm:$false
            Write-Host "$sam removed from M365 - VDI Users"
        }

        # Add to E5 group
        Add-ADGroupMember -Identity $E5Group -Members $adUser
        Write-Host "$sam added to E5 group"
    } else {
        Write-Warning "User $sam not found in AD"
    }
}