# STEP 0: Setup and Prerequisites
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

# Install required modules/scripts silently
try {
    if (-not (Get-Command Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue)) {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false
    }

    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        Install-Module -Name PnP.PowerShell -RequiredVersion 1.12.0 -Force -Confirm:$false
    }
    Import-Module PnP.PowerShell -ErrorAction Stop
} catch {
    # Log and exit silently if setup fails
    Exit 1
}

# STEP 1: Define Paths and SharePoint Info
$localExportPath = "$env:TEMP\AutopilotHWID_temp.csv"
$localMasterPath = "$env:TEMP\AutopilotHWID.csv"

$siteURL = "_________________"
$documentLibraryName = "______________"
$sharepointFolder = "___________________"
$masterFileName = "AutopilotHWID.csv"

# STEP 2: Connect to SharePoint
try {
    Connect-PnPOnline -Url $siteURL -UseWebLogin -ErrorAction Stop
} catch {
    Exit 2
}

# STEP 3: Download Master CSV from SharePoint
$serverRelativePath = "/sites/Information_Technology/$documentLibraryName/$sharepointFolder/$masterFileName"
try {
    Get-PnPFile -Url $serverRelativePath -Path "$env:TEMP" -FileName $masterFileName -AsFile -Force -ErrorAction Stop
} catch {
    Exit 3
}

# STEP 4: Collect Hardware Hash
try {
    Get-WindowsAutopilotInfo -OutputFile $localExportPath
} catch {
    Exit 4
}

# STEP 5: Clean BOM from Master CSV
try {
    Set-ItemProperty -Path $localMasterPath -Name IsReadOnly -Value $false
    $rawContent = Get-Content $localMasterPath -Raw
    $cleanContent = $rawContent -replace ([char]0xFEFF), ""
    $cleanContent | Set-Content $localMasterPath -Encoding UTF8
} catch {
    Exit 5
}

# STEP 6: Append New Hash to Master CSV
try {
    $masterData = Import-Csv $localMasterPath
    $masterHeaders = @("Device Serial Number", "Windows Product ID", "Hardware Hash")

    $newHashData = Import-Csv $localExportPath | ForEach-Object {
        $aligned = @{
            "Device Serial Number" = $_."Device Serial Number"
            "Windows Product ID"   = $_."Windows Product ID"
            "Hardware Hash"        = $_."Hardware Hash"
        }
        New-Object PSObject -Property $aligned
    }

    $combinedData = @($masterData) + @($newHashData) | Sort-Object -Property "Device Serial Number" -Unique
    $combinedData | Export-Csv -Path $localMasterPath -NoTypeInformation
} catch {
    Exit 6
}

# STEP 7: Upload Updated Master CSV to SharePoint
try {
    Remove-PnPFile -ServerRelativeUrl $serverRelativePath -Force -ErrorAction SilentlyContinue
    Add-PnPFile -Path $localMasterPath -Folder "$documentLibraryName/$sharepointFolder" -NewFileName $masterFileName
} catch {
    Exit 7
}

# STEP 8: Cleanup
Remove-Item $localExportPath -ErrorAction SilentlyContinue
Exit 0