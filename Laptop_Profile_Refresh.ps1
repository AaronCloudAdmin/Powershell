# 1. Define the "IT" account name to protect
$ITAdminName = "IT" # Replace with your exact account name if different

# 2. Disable the default built-in Administrator account
Write-Host "Disabling built-in Administrator account..."
Disable-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue

# 3. Get all user profiles
$Profiles = Get-CimInstance -Class Win32_UserProfile

foreach ($Profile in $Profiles) {
    # Extract the folder name from the path (e.g., C:\Users\John -> John)
    $ProfileName = Split-Path $Profile.LocalPath -Leaf
    
    # Define Logic: Do NOT delete if...
    # - It's a special system profile ($_.Special -eq $true)
    # - It's currently in use ($_.Loaded -eq $true)
    # - It's your "IT" admin account
    # - It's the 'Public' or 'Default' folder
    $IsProtected = $Profile.Special -or 
                   $Profile.Loaded -or 
                   ($ProfileName -eq $ITAdminName) -or 
                   ($ProfileName -eq "Public") -or
                   ($ProfileName -eq "Default")

    if (-not $IsProtected) {
        try {
            Write-Host "Deleting profile for: $ProfileName" -ForegroundColor Cyan
            $Profile | Remove-CimInstance
        } catch {
            Write-Warning "Could not delete $ProfileName. It may be locked."
        }
    } else {
        Write-Host "Skipping protected profile: $ProfileName" -ForegroundColor Yellow
    }
}