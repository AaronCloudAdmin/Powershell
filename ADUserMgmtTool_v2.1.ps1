<#	/
	.NOTES
	===========================================================================
	 Created on:    12/29/2025
	 Created by:    Aaron Holley
	 Organization: 	The original has been customized to work for PPPSW
	 Filename:     	ADUserMgmtTool.ps1
	===========================================================================
	.DESCRIPTION
	    This is a customized Active Directory GUI to  run administrative actions
        to automate workflow. It is user focused with a read-only view on computers.
        The GUI optimizes tasks in Neurons that require AD lookup or edits. The 
        Copy user button will create a new user with the traits from the original
        while setting the default password, (which is hard encoded in the script
        on lines 243 & 279). It also removes the M365 security group. This will 
        need to be manually added afterwards. The purpose is to prevent a mailbox
        being created in the M365 cloud before it is made on-prem. Eventually a later
        version of this script will include creating the mailbox then re-adding
        the M365 license. The DISABLE and AIRLOCK button diabled the account. removes
        ALL security groups EXCEPT "Domain Users" then moves them to "TheAirlock - M365" OU.

#>



# --- 1. ENVIRONMENT & ASSEMBLY LOAD ---
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# --- 2. GLOBAL HELPER FUNCTIONS ---

function Update-UserList { 
    if ($global:tvOU.SelectedNode) { 
        $current = $global:tvOU.SelectedNode
        $global:tvOU.SelectedNode = $null
        $global:tvOU.SelectedNode = $current 
    } 
}

function Enable-ADAdvancedFeatures {
    try {
        $featureKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Active Directory Management"
        if (-not (Test-Path $featureKey)) { [void](New-Item $featureKey -Force) }
        Set-ItemProperty -Path $featureKey -Name "AdvancedFeatures" -Value 1
    } catch { }
}

function Add-ActionBtn($text, $color, $top) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text; $btn.Size = "280,42"; $btn.Location = "20,$top" # Reduced height slightly from 45 to 42
    $btn.BackColor = [System.Drawing.ColorTranslator]::FromHtml($color)
    $btn.FlatStyle = "Flat"; $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    [void]$global:pnlRight.Controls.Add($btn) 
    return $btn
}

# --- 3. MAIN FORM & UI LAYOUT ---
& {
    $global:Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Active Directory User Management Tool"
    $Form.Size = "1300,900" # Reduced height from 1000 to 900 to avoid taskbar cutoff
    $Form.BackColor = [System.Drawing.Color]::White
    $Form.StartPosition = "CenterScreen"

    $global:SplitContainer = New-Object System.Windows.Forms.SplitContainer
    $SplitContainer.Dock = "Fill"; $SplitContainer.SplitterDistance = 75; $SplitContainer.BorderStyle = "Fixed3D"
    [void]$Form.Controls.Add($SplitContainer)

    $global:tvOU = New-Object System.Windows.Forms.TreeView
    $tvOU.Dock = "Fill"
    [void]$SplitContainer.Panel1.Controls.Add($tvOU)

    $global:pnlRight = New-Object System.Windows.Forms.Panel
    $pnlRight.Dock = "Right"; $pnlRight.Width = 320
    [void]$Form.Controls.Add($pnlRight)

    $global:pnlCenter = New-Object System.Windows.Forms.TableLayoutPanel
    $pnlCenter.Dock = "Fill"; $pnlCenter.RowCount = 4; $pnlCenter.ColumnCount = 1

    [void]$pnlCenter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 30)))
    [void]$pnlCenter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 35)))
    [void]$pnlCenter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
    [void]$pnlCenter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 35)))
    [void]$SplitContainer.Panel2.Controls.Add($pnlCenter)

    $global:lbUsers = New-Object System.Windows.Forms.ListBox
    $lbUsers.Dock = "Fill"
    [void]$pnlCenter.Controls.Add($lbUsers, 0, 0)

    $global:txtDetails = New-Object System.Windows.Forms.TextBox
    $txtDetails.Multiline = $true; $txtDetails.Dock = "Fill"; $txtDetails.ReadOnly = $true
    $txtDetails.Font = New-Object System.Drawing.Font("Consolas", 10); $txtDetails.ScrollBars = "Vertical"
    [void]$pnlCenter.Controls.Add($txtDetails, 0, 1)

    $global:lblGroupTitle = New-Object System.Windows.Forms.Label
    $lblGroupTitle.Text = "Groups (Security vs Distribution):"; $lblGroupTitle.Dock = "Fill"
    $lblGroupTitle.TextAlign = "BottomLeft"; $lblGroupTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    [void]$pnlCenter.Controls.Add($lblGroupTitle, 0, 2)

    $global:txtGroups = New-Object System.Windows.Forms.TextBox
    $txtGroups.Multiline = $true; $txtGroups.Dock = "Fill"; $txtGroups.ReadOnly = $true
    $txtGroups.Font = New-Object System.Drawing.Font("Consolas", 9); $txtGroups.ScrollBars = "Vertical"
    [void]$pnlCenter.Controls.Add($txtGroups, 0, 3)
} > $null

# --- 4. ACTION BUTTON DEFINITIONS ---
$btnSearch   = Add-ActionBtn "Search" "#90EE90" 10
$btnOpenAD   = Add-ActionBtn "Open AD" "#90EE90" 56
$btnRefresh  = Add-ActionBtn "Refresh List" "#90EE90" 102
$btnUnlock   = Add-ActionBtn "Unlock Account" "#90EE90" 148
$btnReset    = Add-ActionBtn "Reset Password" "#ADD8E6" 194
$btnEnable   = Add-ActionBtn "ENABLE Account" "#ADD8E6" 240
$btnCopyUser = Add-ActionBtn "COPY User" "#ADD8E6" 286
$btnGroups   = Add-ActionBtn "Edit Member Of (Groups)" "#3CB371" 332
$btnLOAStart = Add-ActionBtn "LOA Start" "#FFFACD" 395 
$btnLOAEnd   = Add-ActionBtn "LOA Return" "#B0C4DE" 441
$btnDisable  = Add-ActionBtn "DISABLE User" "#F08080" 505
$btnAirlock  = Add-ActionBtn "DISABLE and AIRLOCK" "#F08080" 551

# --- 5. AD LOGIC: TREE NAVIGATION ---
# [Logic remains unchanged]
try {
    $domain = (Get-ADDomain).DistinguishedName
    $rootNode = $tvOU.Nodes.Add($domain, $domain)
    $rootNode.Tag = $domain
    [void]$rootNode.Nodes.Add("Loading...")
} catch { [System.Windows.Forms.MessageBox]::Show("AD Connection Error.") }

$tvOU.Add_BeforeExpand({
    $node = $_.Node; $node.Nodes.Clear()
    try {
        $subItems = Get-ADObject -Filter 'ObjectClass -eq "organizationalUnit" -or ObjectClass -eq "container"' `
                                 -SearchBase $node.Tag -SearchScope OneLevel -Properties Name
        foreach ($item in $subItems) {
            $newNode = $node.Nodes.Add($item.DistinguishedName, $item.Name)
            $newNode.Tag = $item.DistinguishedName
            $hasChildren = Get-ADObject -Filter 'ObjectClass -eq "organizationalUnit" -or ObjectClass -eq "container"' `
                                        -SearchBase $item.DistinguishedName -SearchScope OneLevel
            if ($hasChildren) { [void]$newNode.Nodes.Add("Loading...") }
        }
    } catch {}
})

$tvOU.Add_AfterSelect({
    $lbUsers.Items.Clear()
    if ($null -ne $_.Node.Tag) {
        try {
            $items = Get-ADObject -Filter 'ObjectClass -eq "user" -or ObjectClass -eq "computer"' `
                                  -SearchBase "$($_.Node.Tag)" -SearchScope OneLevel -Properties SamAccountName, Name | Sort-Object Name
            foreach ($i in $items) { 
                if ($i.ObjectClass -eq "computer") { [void]$lbUsers.Items.Add($i.Name) }
                else { [void]$lbUsers.Items.Add($i.SamAccountName) }
            }
        } catch { }
    }
})

$lbUsers.Add_SelectedIndexChanged({
    if ($null -eq $lbUsers.SelectedItem) { return }
    try {
        $selection = $lbUsers.SelectedItem
        $adObj = Get-ADObject -Filter "Name -eq '$selection' -or SamAccountName -eq '$selection'" -Properties ObjectClass
        
        if ($adObj.ObjectClass -eq "computer") {
            $comp = Get-ADComputer -Identity $selection -Properties IPv4Address, OperatingSystem, Enabled, Description
            $status = if ($comp.Enabled) { "Active" } else { "Disabled" }
            $txtDetails.Text = "COMPUTER NAME: $($comp.Name)`r`nOS: $($comp.OperatingSystem)`r`nIP: $($comp.IPv4Address)`r`nSTATUS: $status`r`n---`r`nDESC: $($comp.Description)"
            $txtGroups.Text = "Groups not displayed for computers."
            return
        }

        $user = Get-ADUser -Identity $selection -Properties Title, Department, Manager, LockedOut, MemberOf, info, CannotChangePassword, PasswordLastSet, PasswordNeverExpires, AccountExpirationDate, 'msDS-UserPasswordExpiryTimeComputed', Enabled, DisplayName, SamAccountName, EmailAddress, OfficePhone
        $managerDisplay = if ($user.Manager) { try { (Get-ADUser -Identity $user.Manager -Properties DisplayName).DisplayName } catch { $user.Manager } } else { "(none)" }
        $pwdLastSetText = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToLocalTime().ToString("yyyy-MM-dd HH:mm") } else { "(never set)" }
        
        $pwdExpireText = "Password never expires"
        if (-not $user.PasswordNeverExpires) {
            $expiryFileTime = $user.'msDS-UserPasswordExpiryTimeComputed'
            if ($expiryFileTime -and [int64]$expiryFileTime -ne 0) {
                $expiryDT = [DateTime]::FromFileTimeUtc([int64]$expiryFileTime).ToLocalTime()
                $pwdExpireText = $expiryDT.ToString("yyyy-MM-dd HH:mm")
                if ($expiryDT -lt (Get-Date)) { $pwdExpireText += " (EXPIRED)" }
            }
        }

        $acctExpireText = if ($user.AccountExpirationDate) { $user.AccountExpirationDate.ToLocalTime().ToString("yyyy-MM-dd HH:mm") } else { "(none)" }
        $statusText = if ($user.Enabled) { "Active" } else { "Disabled" }

        $userEmail = if ($user.EmailAddress) { $user.EmailAddress } else { "(none)" }
        $userPhone = if ($user.OfficePhone) { $user.OfficePhone } else { "(none)" }

$txtDetails.Text = @"
DISPLAY NAME: $($user.DisplayName)
USERNAME: $($user.SamAccountName)
EMAIL: $userEmail
PHONE: $userPhone
TITLE: $($user.Title)
DEPT: $($user.Department)
MANAGER: $managerDisplay
STATUS: $statusText
LOCKED: $($user.LockedOut)
PASSWORD LAST SET: $pwdLastSetText
PASSWORD EXPIRES: $pwdExpireText
ACCOUNT EXPIRES: $acctExpireText
-----------------------------------------------
TELEPHONE NOTES:
$($user.info)
"@

        $secGroups = New-Object System.Collections.Generic.List[string]
        $distLists = New-Object System.Collections.Generic.List[string]
        foreach ($dn in $user.MemberOf) {
            try {
                $g = Get-ADGroup -Identity $dn -Properties GroupCategory
                if ($g.GroupCategory -eq "Security") { $secGroups.Add("[SEC] $($g.Name)") }
                else { $distLists.Add("[DL] $($g.Name)") }
            } catch {}
        }
        $txtGroups.Text = "--- SECURITY GROUPS ---`r`n" + (($secGroups | Sort-Object) -join "`r`n") + "`r`n`r`n--- DISTRIBUTION LISTS ---`r`n" + (($distLists | Sort-Object) -join "`r`n")
    } catch { $txtDetails.Text = "Error loading details." }
})

# --- 6. BUTTON LOGIC: ACTIONS ---
# [Button event logic remains unchanged]
$btnSearch.Add_Click({
    $inputStr = [Microsoft.VisualBasic.Interaction]::InputBox("Search entire domain:", "Domain Search", "")
    if ([string]::IsNullOrWhiteSpace($inputStr)) { return }
    try {
        $ldapFilter = "(&(|(objectClass=user)(objectClass=computer))(anr=$($inputStr.Trim())))"
        $results = Get-ADObject -LDAPFilter $ldapFilter -SearchBase $domain -SearchScope Subtree -Properties SamAccountName, Name | Sort-Object Name
        $lbUsers.Items.Clear()
        if (-not $results) { [System.Windows.Forms.MessageBox]::Show("No matches found."); return }
        foreach ($obj in $results) { 
            if ($obj.ObjectClass -eq "computer") { [void]$lbUsers.Items.Add($obj.Name) }
            else { [void]$lbUsers.Items.Add($obj.SamAccountName) }
        }
        $lbUsers.SelectedIndex = 0
    } catch { }
})

$btnOpenAD.Add_Click({
    try {
        Enable-ADAdvancedFeatures 
        Start-Process "dsa.msc"
        Update-UserList
    } catch { [System.Windows.Forms.MessageBox]::Show("Could not open ADUC: $($_.Exception.Message)") }
})

$btnRefresh.Add_Click({ Update-UserList; $txtDetails.Clear(); $txtGroups.Clear() })

$btnUnlock.Add_Click({ 
    if ($lbUsers.SelectedItem) { 
        $target = $lbUsers.SelectedItem
        Unlock-ADAccount -Identity $target
        [System.Windows.Forms.MessageBox]::Show("Unlocked.")
        Update-UserList
        $lbUsers.SelectedItem = $target
    } 
})

$btnReset.Add_Click({
    $sel = $lbUsers.SelectedItem
    if (-not $sel) { return }
    if ([System.Windows.Forms.MessageBox]::Show("Reset password for $sel ?", "Confirm", "YesNo") -eq "No") { return }
    try {
        $pass = ConvertTo-SecureString "Inthistogether1:" -AsPlainText -Force
        Unlock-ADAccount -Identity $sel
        Set-ADAccountPassword -Identity $sel -NewPassword $pass -Reset
        Set-ADUser -Identity $sel -ChangePasswordAtLogon $true
        [System.Windows.Forms.MessageBox]::Show("Password Reset Complete.")
        Update-UserList
        $lbUsers.SelectedItem = $sel
    } catch { [System.Windows.Forms.MessageBox]::Show("Reset Failed: $($_.Exception.Message)") }
})

$btnEnable.Add_Click({
    $sel = $lbUsers.SelectedItem 
    if ($sel) { 
        Enable-ADAccount -Identity $sel
        Update-UserList
        $lbUsers.SelectedItem = $sel
        [System.Windows.Forms.MessageBox]::Show("$sel has been Enabled.") 
    }
})

$btnCopyUser.Add_Click({
    $src = $lbUsers.SelectedItem
    if (-not $src) { return }
    $fName = [Microsoft.VisualBasic.Interaction]::InputBox("First Name:", "Clone", "")
    $lName = [Microsoft.VisualBasic.Interaction]::InputBox("Last Name:", "Clone", "")
    $note = [Microsoft.VisualBasic.Interaction]::InputBox("Notes:", "Clone", "")
    if (-not $fName -or -not $lName) { return }
    try {
        $fInit = $fName.Substring(0,1).ToUpper()
        $capSur = $lName.Substring(0,1).ToUpper() + $lName.Substring(1).ToLower()
        $baseSam = $fInit + $capSur
        $finalSam = $baseSam; $count = 1
        while (Get-ADObject -Filter "SamAccountName -eq '$finalSam'") { $finalSam = $baseSam + $count; $count++ }
        $finalUPN = "$finalSam@$((Get-ADDomain).DNSRoot)"
        $template = Get-ADUser -Identity $src -Properties DistinguishedName, MemberOf
        $targetOU = $template.DistinguishedName -replace '^CN=.*?,(?=OU=|CN=)',''
        $pass = ConvertTo-SecureString "Inthistogether1:" -AsPlainText -Force
        New-ADUser -Name "$lName, $fName" -SamAccountName $finalSam -UserPrincipalName $finalUPN -DisplayName "$lName, $fName" -GivenName $fName -Surname $lName -Instance $template -AccountPassword $pass -ChangePasswordAtLogon $true -Enabled $true -Path $targetOU
        if ($note) { Set-ADUser -Identity $finalSam -Replace @{info=$note} }
        $excludedGroups = @("M365 - VDI Users", "M365 - Users")
        foreach ($groupDN in $template.MemberOf) {
            $groupObj = Get-ADGroup -Identity $groupDN
            if ($excludedGroups -notcontains $groupObj.Name) {
                Add-ADGroupMember -Identity $groupObj -Members $finalSam
            }
        }
        [System.Windows.Forms.MessageBox]::Show("User Created: $finalSam")
        Update-UserList
        $lbUsers.SelectedItem = $finalSam
    } catch { [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)") }
})

$btnGroups.Add_Click({
    if (-not $lbUsers.SelectedItem) { return }
    $targetUser = $lbUsers.SelectedItem
    $grpForm = New-Object System.Windows.Forms.Form
    $grpForm.Text = "Manage Groups for: $targetUser"
    $grpForm.Size = "500,550"; $grpForm.StartPosition = "CenterParent"
    $txtS = New-Object System.Windows.Forms.TextBox; $txtS.Location = "10,10"; $txtS.Width = 300
    $btnF = New-Object System.Windows.Forms.Button; $btnF.Text = "Find Group"; $btnF.Location = "320,10"
    $lbR = New-Object System.Windows.Forms.ListBox; $lbR.Location = "10,40"; $lbR.Size = "460,350"
    $btnA = New-Object System.Windows.Forms.Button; $btnA.Text = "Add to Group"; $btnA.Location = "10,400"; $btnA.Width = 150; $btnA.BackColor = [System.Drawing.Color]::LightGreen
    $btnR = New-Object System.Windows.Forms.Button; $btnR.Text = "Remove from Group"; $btnR.Location = "170,400"; $btnR.Width = 150; $btnR.BackColor = [System.Drawing.Color]::LightPink
    $btnDone = New-Object System.Windows.Forms.Button; $btnDone.Text = "Close"; $btnDone.Location = "380,470"
    $grpForm.Controls.AddRange(@($txtS, $btnF, $lbR, $btnA, $btnR, $btnDone))
    $btnF.Add_Click({ $lbR.Items.Clear(); (Get-ADGroup -LDAPFilter "(anr=$($txtS.Text))").SamAccountName | % { [void]$lbR.Items.Add($_) } })
    $btnA.Add_Click({ if ($lbR.SelectedItem) { try { Add-ADGroupMember -Identity $lbR.SelectedItem -Members $targetUser -ErrorAction Stop; Update-UserList; $lbUsers.SelectedItem = $targetUser } catch { [System.Windows.Forms.MessageBox]::Show("Add failed: $($_.Exception.Message)") } } })
    $btnR.Add_Click({ if ($lbR.SelectedItem) { try { Remove-ADGroupMember -Identity $lbR.SelectedItem -Members $targetUser -Confirm:$false -ErrorAction Stop; Update-UserList; $lbUsers.SelectedItem = $targetUser } catch { [System.Windows.Forms.MessageBox]::Show("Remove failed: $($_.Exception.Message)") } } })
    $btnDone.Add_Click({ $grpForm.Close() })
    $grpForm.ShowDialog()
})

$btnLOAStart.Add_Click({
    if (-not $lbUsers.SelectedItem) { return }
    $sel = $lbUsers.SelectedItem
    $date = [Microsoft.VisualBasic.Interaction]::InputBox("Expiration (MM/DD/YYYY):", "LOA Start", (Get-Date).ToShortDateString())
    $note = [Microsoft.VisualBasic.Interaction]::InputBox("Ticket/Notes:", "LOA Start", "")
    if (-not $date -or -not $note) { return }
    try {
        Set-ADAccountExpiration -Identity $sel -DateTime ([DateTime]$date); Set-ADUser -Identity $sel -CannotChangePassword $true
        $cur = Get-ADUser -Identity $sel -Properties info; Set-ADUser -Identity $sel -Replace @{info="$($cur.info)`r`n$note".Trim()}
        [System.Windows.Forms.MessageBox]::Show("LOA Started."); Update-UserList; $lbUsers.SelectedItem = $sel
    } catch { [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)") }
})

$btnLOAEnd.Add_Click({
    if (-not $lbUsers.SelectedItem) { return }
    $sel = $lbUsers.SelectedItem
    $note = [Microsoft.VisualBasic.Interaction]::InputBox("Ticket/Notes:", "LOA End", "")
    if (-not $note) { return }
    try {
        Clear-ADAccountExpiration -Identity $sel; Set-ADUser -Identity $sel -CannotChangePassword $false
        $cur = Get-ADUser -Identity $sel -Properties info; Set-ADUser -Identity $sel -Replace @{info="$($cur.info)`r`n$note".Trim()}
        [System.Windows.Forms.MessageBox]::Show("LOA Returned."); Update-UserList; $lbUsers.SelectedItem = $sel
    } catch { [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)") }
})

$btnDisable.Add_Click({
    $sel = $lbUsers.SelectedItem 
    if ($sel) { 
        Disable-ADAccount -Identity $sel
        Update-UserList; $lbUsers.SelectedItem = $sel
        [System.Windows.Forms.MessageBox]::Show("$sel has been Disabled.") 
    }
})

$btnAirlock.Add_Click({
    # 1. Capture the selection immediately for the message box
    $sel = $lbUsers.SelectedItem
    if (-not $sel) { return }

    # 2. Custom Confirmation Pop-up
    $confirmMsg = "Are you sure you want to disable $sel and move them to `"TheAirlock - M365 OU`"?"
    $result = [System.Windows.Forms.MessageBox]::Show($confirmMsg, "Confirm Airlock", "YesNo", "Warning")
    
    if ($result -eq "No") { return }

    try {
        # 3. Disable the account
        Disable-ADAccount -Identity $sel
        
        # 4. Remove Groups (Except Domain Users)
        $u = Get-ADUser -Identity $sel -Properties MemberOf, DistinguishedName
        foreach ($g in $u.MemberOf) { 
            try { 
                $groupObj = Get-ADGroup -Identity $g
                if ($groupObj.Name -ne "Domain Users") {
                    Remove-ADGroupMember -Identity $g -Members $u.DistinguishedName -Confirm:$false -ErrorAction SilentlyContinue 
                }
            } catch {} 
        }

        # 5. Move to the Airlock OU
        $air = Get-ADOrganizationalUnit -Filter "Name -eq 'TheAirlock - M365'"
        Move-ADObject -Identity $u.DistinguishedName -TargetPath $air.DistinguishedName
        
        # 6. Final UI Refresh (No more pop-ups here)
        Update-UserList
        
    } catch { 
        [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)") 
    }
})

# Final Show and Explicit Exit
[void]$Form.ShowDialog()
Stop-Process -Id $PID -Force