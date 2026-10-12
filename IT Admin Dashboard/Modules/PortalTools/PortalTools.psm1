<#
    PortalTools
    Shared helpers for the IT Admin Portal pages (AD now; Exchange, Teams, Intune later).

    Write-PortalLog Appends one row to the daily portal log:
                      _____\Portal_yyyy-MM-dd.csv
                      Columns: Timestamp, AdminUser, TargetUser, Action, Result, Details

    Show-PortalToast Shows a 3-second toast in the browser AND writes it to the portal log.
                      Use it in page script blocks in place of Show-PodeWebToast.

    Move-PortalBack   After an Active Directory action, reloads the view the page was showing.
#>

$script:PortalLogFolder = '_____'

function Write-PortalLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [string]$Target = '',

        [string]$Details = '',

        [ValidateSet('Info', 'Success', 'Failed')]
        [string]$Result = 'Info'
    )

    try {
        if (-not (Test-Path $script:PortalLogFolder)) {
            New-Item -Path $script:PortalLogFolder -ItemType Directory -Force | Out-Null
        }

        $LogFile = Join-Path $script:PortalLogFolder ('Portal_{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd'))

        $Row = [PSCustomObject]@{
            Timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            AdminUser  = $env:USERNAME
            TargetUser = $Target
            Action     = $Action
            Result     = $Result
            Details    = $Details
        }

        # Several browser requests can log at the same moment; the mutex stops them colliding on the file
        $Mutex = [System.Threading.Mutex]::new($false, 'AdminDashboardPortalLog')
        $HasLock = $false
        try {
            $HasLock = $Mutex.WaitOne(5000)
            $Row | Export-Csv -Path $LogFile -Append -NoTypeInformation -Encoding UTF8
        }
        finally {
            if ($HasLock) { $Mutex.ReleaseMutex() }
            $Mutex.Dispose()
        }
    }
    catch {
        # Logging must never break the action itself
        Write-Warning "Portal log write failed: $($_.Exception.Message)"
    }
}

function Show-PortalToast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Title = 'Message',

        [string]$Action = 'General',

        [string]$Target = '',

        [ValidateSet('Info', 'Success', 'Failed')]
        [string]$Result = 'Info'
    )

    Write-PortalLog -Action $Action -Target $Target -Details $Message -Result $Result

    # The toast object must be the output, so Pode.Web sends it to the browser
    Show-PodeWebToast -Title $Title -Message $Message -Duration 3000
}

function Move-PortalBack {
    # After an AD action: reload the user's details view, or the search view (keeping results),
    # depending on which view the Active Directory page was showing (state 'AD_View').
    param([string]$Sam)

    if ((Get-PodeState -Name 'AD_View') -eq 'details') { Move-PodeWebUrl -Url "?value=$Sam" }
    else { Move-PodeWebUrl -Url '?restore=1' }
}

Export-ModuleMember -Function 'Write-PortalLog', 'Show-PortalToast', 'Move-PortalBack'