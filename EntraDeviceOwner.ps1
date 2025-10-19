# --------------------------------------------
# Created By: Aaron Holley
# This script's purpose is to add a user as the owner to their device in Entra ID
# In hybrid environments device ownership doesn't assign consistently
# This tool provides a quick way to cleanup those one-offs that get missed by Entra ID
# --------------------------------------------




# Requires a PIM account with at least Intune Administrator privileges
# --------------------------------------------

# Disconnect any existing Microsoft Graph session
try { Disconnect-MgGraph -Confirm:$false } catch {}

# Ensure required modules are installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
    Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force
}
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement)) {
    Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force
}

# Import only the necessary modules in Microsoft Graph
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# Connect to Microsoft Graph with required scopes & Prompt for the PIM account to use
Connect-MgGraph -Scopes "User.Read.All", "Device.ReadWrite.All" 

# Prompt for the user and device
$userPrincipalName = Read-Host "Enter the User Principal Name (UPN) of the user to assign as owner"
$deviceDisplayName = Read-Host "Enter the display name of the device (as shown in Entra ID)"

# Retrieve the user
$user = Get-MgUser -Filter "userPrincipalName eq '$userPrincipalName'" -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Host "`nâ Œ User not found: $userPrincipalName" -ForegroundColor Red
    Read-Host "`nPress Enter to exit"
    exit
}

# Retrieve the device and select the first match
$device = Get-MgDevice -Filter "displayName eq '$deviceDisplayName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $device) {
    Write-Host "`nâ Œ Device not found: $deviceDisplayName" -ForegroundColor Red
    Read-Host "`nPress Enter to exit"
    exit
}

# Confirm before making changes
Write-Host "`nAbout to assign $($user.DisplayName) as the owner of device '$($device.DisplayName)'"
$confirm = Read-Host "Type 'YES' to confirm"
if ($confirm -ne 'YES') {
    Write-Host "`nOperation cancelled by user."
    Read-Host "Press Enter to exit"
    exit
}

# Assign the user as the device owner
try {
    New-MgDeviceRegisteredOwnerByRef -DeviceId $device.Id -BodyParameter @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
    }

    Write-Host "`nâœ… Successfully assigned $($user.DisplayName) as owner of device '$($device.DisplayName)'" -ForegroundColor Green
}
catch {
    Write-Host "`nâ Œ Failed to assign owner:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# Pause at the end
Write-Host "`n--------------------------------------------"
Read-Host "Press Enter to close this window"
