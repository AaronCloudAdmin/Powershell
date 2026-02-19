# uncomment this if needed: 
#Install-Module ExchangeOnlineManagement -Scope CurrentUser

Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline

# Prompt for distro email
$distro = Read-Host "Enter distro email"

# Prompt for desired file name (without extension)
$rawName = Read-Host "Enter file name (no extension). Leave blank to use the distro email"
if ([string]::IsNullOrWhiteSpace($rawName)) {
    $rawName = $distro
}

# Ensure output directory exists
$outDir = "C:\CSV"
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Sanitize the file name (remove invalid characters)
$invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
$regex = "[{0}]" -f [Regex]::Escape($invalid)
$baseName = ($rawName -replace $regex, '_').Trim()
if ([string]::IsNullOrWhiteSpace($baseName)) {
    $baseName = "DistroMembers"
}

# Build a non-overwriting file path by adding a numeric suffix if needed
$ext = ".csv"
$path = Join-Path $outDir ($baseName + $ext)
$counter = 1
while (Test-Path -LiteralPath $path) {
    $path = Join-Path $outDir ("{0} ({1}){2}" -f $baseName, $counter, $ext)
    $counter++
}

# Fetch and export members
Get-DistributionGroupMember -Identity $distro |
    Select-Object Name, PrimarySmtpAddress |
    Export-Csv -Path $path -NoTypeInformation

Write-Host "Export complete:" -ForegroundColor Green
Write-Host "  Group: $distro"
Write-Host "  File : $path"