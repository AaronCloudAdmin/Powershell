# =========================================================================
# ACTIVE DIRECTORY
#
# Selecting a user: single-click a row in Matches or Report Results = select it (highlighted)
# double-click a row = open the user's details
# (handled by Public\table-filters.js, which tells the server via /api/ad/select)
#
# Actions: sidebar items under Active Directory (added by table-filters.js; each one
# clicks a hidden "ADSidebar..." button on this page). They work on both the
# search view and the details view. All act on the selected user.
# Cyan: Unlock Account, Reset Password, ENABLE Account, COPY User
# Green: Edit Name / Email, Edit Groups, Title Change, Manager Change,
# Update Phone Number, Move User, Update Notes
# Yellow: LOA Start, LOA Return
# Red: DISABLE User, DISABLE and AIRLOCK
#
# Needs modules: AD_Users, AD_Groups, AD_Airlock, PortalTools (imported in app.ps1)
#
# After an action: the page reloads to where you were. The page remembers which view is
# showing in state 'AD_View' (search or details).
# =========================================================================

# -------------------------------------------------------------------------
# Remembers which user is selected (posted by table-filters.js on single-click)
# -------------------------------------------------------------------------
Add-PodeRoute -Method Post -Path '/api/ad/select' -ScriptBlock {
    $Sam = "$($WebEvent.Data.sam)".Trim()
    $Name = "$($WebEvent.Data.name)".Trim()

    if ($Sam) {
        Set-PodeState -Name 'AD_SelectedUser' -Value @{ Sam = $Sam; Name = $Name } | Out-Null
    }

    Write-PodeJsonResponse -Value @{ ok = $true }
}

# -------------------------------------------------------------------------
# The page
# -------------------------------------------------------------------------
Add-PodeWebPage -Name 'Active Directory' -Icon 'account-search' -ScriptBlock {

    # Double-clicking a row reloads this page as ?value=<SamAccountName>
    $SelectedUser = $WebEvent.Query['value']

    # =====================================================================
    # ACTION POP-UPS (modals). Rendered on both views, hidden until opened.
    # Each one acts on the selected user (state AD_SelectedUser) and, when done,
    # reloads the details view ("?value=<sam>") or the search view ("?restore=1").
    # =====================================================================
    $RenderActionModals = {

        # ---------------- Unlock Account ----------------
        New-PodeWebModal -Name 'Confirm Unlock' -SubmitText 'Yes, Unlock' -AsForm -Content @(
            New-PodeWebText -Id 'UnlockConfirmText' -Value 'Unlock the selected user?'
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Unlock Account'; return }
            $Sam = $Selected.Sam

            try {
                $Result = Unlock-User -SamAccountName $Sam -Force
                Hide-PodeWebModal
                Show-PortalToast -Message "$Sam unlocked. LockedOut = $($Result.LockedOut)" -Action 'Unlock Account' -Target $Sam -Result Success
                Move-PortalBack -Sam $Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Unlock failed' -Message $_.Exception.Message -Action 'Unlock Account' -Target $Sam -Result Failed
            }
        }

        # ---------------- Reset Password ----------------
        # Reset-UserPassword -Force: your default password, must change at next logon, unlock.
        New-PodeWebModal -Name 'Confirm Reset Password' -SubmitText 'Yes, Reset' -AsForm -Content @(
            New-PodeWebText -Id 'ResetConfirmText' -Value 'Reset the password for the selected user?'
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Reset Password'; return }
            $Sam = $Selected.Sam

            try {
                $Result = Reset-UserPassword -SamAccountName $Sam -Force
                Hide-PodeWebModal
                Show-PortalToast -Message "Password reset for $Sam. Must change at next logon. LockedOut = $($Result.LockedOut)" -Action 'Reset Password' -Target $Sam -Result Success
                Move-PortalBack -Sam $Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Reset password failed' -Message $_.Exception.Message -Action 'Reset Password' -Target $Sam -Result Failed
            }
        }

        # ---------------- COPY User ----------------
        # Four pop-ups in a row. The selected user is the template.
        #   1. Copy User from Template: create the user and copy every group except the M365
        #      license group(s) (Copy-ADUserFromTemplate).
        #   2. Remote Mailbox: shows the Enable-RemoteMailbox command to run on the Exchange Tools
        #      Server. "Yes" adds the held-back license group(s) (Add-UserLicenseGroups).
        #   3. Copy Office Phone: Yes / No (skipped when the template has no office phone).
        #   4. Telephone Notes: note appended to Telephone Notes (info); blank = skip.
        # Between steps the new user is kept in state 'AD_PendingCopy'.
        New-PodeWebModal -Name 'Copy User from Template' -SubmitText 'Create User' -AsForm -Content @(
            New-PodeWebText -Id 'CopyWhoText' -Value 'Template: the selected user'
            New-PodeWebTextbox -Name 'CopyFirst' -DisplayName 'First Name'
            New-PodeWebTextbox -Name 'CopyLast' -DisplayName 'Last Name'
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'COPY User'; return }

            $First = "$($WebEvent.Data.CopyFirst)".Trim()
            $Last = "$($WebEvent.Data.CopyLast)".Trim()
            if (-not $First -or -not $Last) {
                Show-PortalToast -Message 'First Name and Last Name are required.' -Action 'COPY User' -Target $Selected.Sam
                return
            }

            try {
                $Result = Copy-ADUserFromTemplate -TemplateSamAccountName $Selected.Sam -FirstName $First -LastName $Last -Force
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Copy user failed' -Message $_.Exception.Message -Action 'COPY User' -Target $Selected.Sam -Result Failed
                return
            }

            Set-PodeState -Name 'AD_PendingCopy' -Value @{
                Sam           = $Result.SamAccountName
                Name          = "$Last, $First"
                HeldGroups    = @($Result.HeldGroups)
                TemplatePhone = $Result.TemplatePhone
            } | Out-Null
            Set-PodeState -Name 'AD_SelectedUser' -Value @{ Sam = $Result.SamAccountName; Name = "$Last, $First" } | Out-Null

            Show-PortalToast -Message "User created: $($Result.SamAccountName). Groups copied except the M365 license group(s)." -Action 'COPY User' -Target $Result.SamAccountName -Result Success

            Hide-PodeWebModal
            Update-PodeWebText -Id 'MailboxWhoText' -Value "Run this on the Exchange Tools Server for $($Result.SamAccountName), then press Yes to add the M365 license group(s):"
            Update-PodeWebText -Id 'MailboxCommandText' -Value $Result.MailboxCommand
            Show-PodeWebModal -Name 'Remote Mailbox'
        }

        New-PodeWebModal -Name 'Remote Mailbox' -SubmitText 'Yes, it has been run' -AsForm -Content @(
            New-PodeWebText -Id 'MailboxWhoText' -Value 'Run this on the Exchange Tools Server:'
            New-PodeWebText -Id 'MailboxCommandText' -Value ''
            New-PodeWebText -Value 'Has Enable-RemoteMailbox been run on the Exchange Tools Server?'
        ) -ScriptBlock {
            $Pending = Get-PodeState -Name 'AD_PendingCopy'
            if (-not $Pending) { Hide-PodeWebModal; Show-PortalToast -Message 'No copied user is waiting for this step.' -Action 'COPY User'; return }

            try {
                $Added = Add-UserLicenseGroups -SamAccountName $Pending.Sam -GroupDistinguishedName @($Pending.HeldGroups) -Force
                Show-PortalToast -Message "M365 license group(s) added to $($Pending.Sam): $($Added.GroupsAdded)" -Action 'COPY User' -Target $Pending.Sam -Result Success
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Adding license group failed' -Message $_.Exception.Message -Action 'COPY User' -Target $Pending.Sam -Result Failed
                return
            }

            Hide-PodeWebModal
            if ($Pending.TemplatePhone) {
                Update-PodeWebText -Id 'CopyPhoneText' -Value "Copy the template's Office Phone ($($Pending.TemplatePhone)) to $($Pending.Sam)?"
                Show-PodeWebModal -Name 'Copy Office Phone'
            }
            else {
                Update-PodeWebText -Id 'CopyNotesText' -Value "Telephone Notes for $($Pending.Sam) (leave blank to skip)"
                Show-PodeWebModal -Name 'Copy User Notes'
            }
        }

        # Yes / No. (Two small forms: in pop-ups with several forms, press the button.)
        New-PodeWebModal -Name 'Copy Office Phone' -Content @(
            New-PodeWebText -Id 'CopyPhoneText' -Value 'Copy the template Office Phone?'

            New-PodeWebForm -Name 'CopyPhoneYesForm' -SubmitText 'Yes' -Content @(
                New-PodeWebHidden -Name 'CopyPhoneYes' -Value '1'
            ) -ScriptBlock {
                $Pending = Get-PodeState -Name 'AD_PendingCopy'
                if (-not $Pending) { Hide-PodeWebModal; return }

                try {
                    Update-UserPhone -SamAccountName $Pending.Sam -PhoneNumber $Pending.TemplatePhone -Force | Out-Null
                    Show-PortalToast -Message "Office Phone for $($Pending.Sam) set to $($Pending.TemplatePhone)" -Action 'COPY User' -Target $Pending.Sam -Result Success
                }
                catch {
                    Show-PortalToast -Title 'Copy office phone failed' -Message $_.Exception.Message -Action 'COPY User' -Target $Pending.Sam -Result Failed
                }

                Hide-PodeWebModal
                Update-PodeWebText -Id 'CopyNotesText' -Value "Telephone Notes for $($Pending.Sam) (leave blank to skip)"
                Show-PodeWebModal -Name 'Copy User Notes'
            }

            New-PodeWebForm -Name 'CopyPhoneNoForm' -SubmitText 'No' -Content @(
                New-PodeWebHidden -Name 'CopyPhoneNo' -Value '1'
            ) -ScriptBlock {
                $Pending = Get-PodeState -Name 'AD_PendingCopy'
                if (-not $Pending) { Hide-PodeWebModal; return }

                Hide-PodeWebModal
                Update-PodeWebText -Id 'CopyNotesText' -Value "Telephone Notes for $($Pending.Sam) (leave blank to skip)"
                Show-PodeWebModal -Name 'Copy User Notes'
            }
        )

        # Last step: note appended to Telephone Notes (info), then open the new user
        New-PodeWebModal -Name 'Copy User Notes' -SubmitText 'Finish' -AsForm -Content @(
            New-PodeWebText -Id 'CopyNotesText' -Value 'Telephone Notes (leave blank to skip)'
            New-PodeWebTextbox -Name 'CopyNotes' -DisplayName 'Note' -Multiline
        ) -ScriptBlock {
            $Pending = Get-PodeState -Name 'AD_PendingCopy'
            if (-not $Pending) { Hide-PodeWebModal; return }

            $Note = "$($WebEvent.Data.CopyNotes)".Trim()
            if ($Note) {
                try {
                    Add-UserNote -SamAccountName $Pending.Sam -Note $Note -Force | Out-Null
                }
                catch {
                    Show-PortalToast -Title 'Add notes failed' -Message $_.Exception.Message -Action 'COPY User' -Target $Pending.Sam -Result Failed
                }
            }

            Remove-PodeState -Name 'AD_PendingCopy' | Out-Null
            Hide-PodeWebModal
            Show-PortalToast -Message "COPY User finished for $($Pending.Sam)" -Action 'COPY User' -Target $Pending.Sam -Result Success
            Move-PodeWebUrl -Url "?value=$($Pending.Sam)"
        }

        # ---------------- Edit Name / Email ----------------
        # Update-UserIdentity: fields are filled with the user's current values when it opens.
        New-PodeWebModal -Name 'Edit Name and Email' -SubmitText 'Save and Sync All Attributes' -AsForm -Content @(
            New-PodeWebText -Id 'EditWhoText' -Value 'The selected user'
            New-PodeWebTextbox -Name 'EditFirst' -Id 'EditFirst' -DisplayName 'First Name'
            New-PodeWebTextbox -Name 'EditLast' -Id 'EditLast' -DisplayName 'Last Name'
            New-PodeWebTextbox -Name 'EditDisplay' -Id 'EditDisplay' -DisplayName 'Display Name'
            New-PodeWebTextbox -Name 'EditEmail' -Id 'EditEmail' -DisplayName 'Email'
            New-PodeWebTextbox -Name 'EditSam' -Id 'EditSam' -DisplayName 'SamAccountName'
            New-PodeWebTextbox -Name 'EditNote' -DisplayName 'Append Note' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Edit Name / Email'; return }

            $Edit = @{
                SamAccountName    = $Selected.Sam
                FirstName         = "$($WebEvent.Data.EditFirst)"
                LastName          = "$($WebEvent.Data.EditLast)"
                DisplayName       = "$($WebEvent.Data.EditDisplay)"
                Email             = "$($WebEvent.Data.EditEmail)"
                NewSamAccountName = "$($WebEvent.Data.EditSam)"
                Note              = "$($WebEvent.Data.EditNote)"
                Force             = $true
            }

            try {
                $Result = Update-UserIdentity @Edit
                Hide-PodeWebModal
                Show-PortalToast -Message "Name / Email updated. Username: $($Result.SamAccountName)" -Action 'Edit Name / Email' -Target $Selected.Sam -Result Success
                Set-PodeState -Name 'AD_SelectedUser' -Value @{ Sam = $Result.SamAccountName; Name = $Result.DisplayName } | Out-Null
                Move-PortalBack -Sam $Result.SamAccountName
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Edit Name / Email failed' -Message $_.Exception.Message -Action 'Edit Name / Email' -Target $Selected.Sam -Result Failed
            }
        }

        # ---------------- Edit Groups ----------------
        # Find Group (first 20 matches), Add, Remove. The window stays open between changes.
        # Note: in pop-ups that hold several small forms, press the button (Enter does nothing).
        New-PodeWebModal -Name 'Edit Group Membership' -Content @(
            New-PodeWebText -Id 'GroupsWhoText' -Value 'The selected user'

            New-PodeWebForm -Name 'GroupFindForm' -SubmitText 'Find Group' -Content @(
                New-PodeWebTextbox -Name 'GroupSearch' -DisplayName 'Group name contains'
            ) -ScriptBlock {
                $Term = "$($WebEvent.Data.GroupSearch)".Trim()
                if (-not $Term) { Show-PortalToast -Message 'Enter part of a group name.' -Action 'Edit Groups'; return }

                try {
                    $Found = @(Find-ADGroupName -SearchTerm $Term)
                    if ($Found.Count -eq 0) {
                        Update-PodeWebSelect -Id 'GroupAddList' -Options @('(no matches)')
                        Show-PortalToast -Message "No groups matched '$Term'." -Action 'Edit Groups' -Target $Term
                        return
                    }
                    Update-PodeWebSelect -Id 'GroupAddList' -Options $Found
                }
                catch {
                    Show-PortalToast -Title 'Find group failed' -Message $_.Exception.Message -Action 'Edit Groups' -Target $Term -Result Failed
                }
            }

            New-PodeWebForm -Name 'GroupAddForm' -SubmitText 'Add' -Content @(
                New-PodeWebSelect -Name 'GroupAddList' -Id 'GroupAddList' -DisplayName 'Groups found' -Options @('(find a group first)')
            ) -ScriptBlock {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'No user is selected.' -Action 'Edit Groups'; return }

                $Group = "$($WebEvent.Data.GroupAddList)"
                if (-not $Group -or $Group.StartsWith('(')) { Show-PortalToast -Message 'Find and pick a group to add.' -Action 'Edit Groups'; return }

                try {
                    Add-UserToGroup -SamAccountName $Selected.Sam -GroupName $Group -Force | Out-Null
                    Update-PodeWebSelect -Id 'GroupRemoveList' -Options @(Get-UserGroupNames -SamAccountName $Selected.Sam | Sort-Object)
                    Show-PortalToast -Message "Added $($Selected.Sam) to $Group" -Action 'Edit Groups' -Target $Selected.Sam -Result Success
                }
                catch {
                    Show-PortalToast -Title 'Add to group failed' -Message $_.Exception.Message -Action 'Edit Groups' -Target $Selected.Sam -Result Failed
                }
            }

            New-PodeWebForm -Name 'GroupRemoveForm' -SubmitText 'Remove' -Content @(
                New-PodeWebSelect -Name 'GroupRemoveList' -Id 'GroupRemoveList' -DisplayName 'Current groups' -Options @('(loading)')
            ) -ScriptBlock {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'No user is selected.' -Action 'Edit Groups'; return }

                $Group = "$($WebEvent.Data.GroupRemoveList)"
                if (-not $Group -or $Group.StartsWith('(')) { Show-PortalToast -Message 'Pick a group to remove.' -Action 'Edit Groups'; return }

                try {
                    Remove-UserFromGroup -SamAccountName $Selected.Sam -GroupName $Group -Force | Out-Null
                    $Left = @(Get-UserGroupNames -SamAccountName $Selected.Sam | Sort-Object)
                    if ($Left.Count -eq 0) { $Left = @('(no groups)') }
                    Update-PodeWebSelect -Id 'GroupRemoveList' -Options $Left
                    Show-PortalToast -Message "Removed $($Selected.Sam) from $Group" -Action 'Edit Groups' -Target $Selected.Sam -Result Success
                }
                catch {
                    Show-PortalToast -Title 'Remove from group failed' -Message $_.Exception.Message -Action 'Edit Groups' -Target $Selected.Sam -Result Failed
                }
            }

            # Done: reloads the page so the groups list is current. (A form button rather than the
            # pop-up's own Submit, so pressing Enter in "Find Group" does not trigger it.)
            New-PodeWebForm -Name 'GroupDoneForm' -SubmitText 'Done' -Content @(
                New-PodeWebHidden -Name 'GroupDone' -Value '1'
            ) -ScriptBlock {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                Hide-PodeWebModal
                if ($Selected -and (Get-PodeState -Name 'AD_View') -eq 'details') { Move-PodeWebUrl -Url "?value=$($Selected.Sam)" } else { Move-PodeWebUrl -Url '?restore=1' }
            }
        )

        # ---------------- Title Change ----------------
        # Update-UserTitleWithNote: Title and Description = new title, note appended. Both required.
        New-PodeWebModal -Name 'Change Title' -SubmitText 'Save Title' -AsForm -Content @(
            New-PodeWebText -Id 'TitleWhoText' -Value 'The selected user'
            New-PodeWebTextbox -Name 'TitleNew' -DisplayName 'New Title'
            New-PodeWebTextbox -Name 'TitleNote' -DisplayName 'Note' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Title Change'; return }

            $Title = "$($WebEvent.Data.TitleNew)".Trim()
            $Note = "$($WebEvent.Data.TitleNote)".Trim()
            if (-not $Title -or -not $Note) {
                Show-PortalToast -Message 'Title and Note are both required.' -Action 'Title Change' -Target $Selected.Sam
                return
            }

            try {
                Update-UserTitleWithNote -SamAccountName $Selected.Sam -Title $Title -Note $Note -Force | Out-Null
                Hide-PodeWebModal
                Show-PortalToast -Message "Title for $($Selected.Sam) changed to '$Title'" -Action 'Title Change' -Target $Selected.Sam -Result Success
                Move-PortalBack -Sam $Selected.Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Title change failed' -Message $_.Exception.Message -Action 'Title Change' -Target $Selected.Sam -Result Failed
            }
        }

        # ---------------- Manager Change ----------------
        # Find (name or username), pick from the list, Set Manager (Update-UserManager).
        New-PodeWebModal -Name 'Change Manager' -Content @(
            New-PodeWebText -Id 'ManagerWhoText' -Value 'The selected user'

            New-PodeWebForm -Name 'ManagerFindForm' -SubmitText 'Find' -Content @(
                New-PodeWebTextbox -Name 'ManagerSearch' -DisplayName 'Manager name or username'
            ) -ScriptBlock {
                $Term = "$($WebEvent.Data.ManagerSearch)".Trim()
                if (-not $Term) { Show-PortalToast -Message 'Enter a name or username.' -Action 'Manager Change'; return }

                try {
                    $Found = @(Find-ADManagerCandidate -SearchTerm $Term | ForEach-Object { "$($_.DisplayName) | $($_.Title) | OU: $($_.OU) ($($_.SamAccountName))" })
                    if ($Found.Count -eq 0) {
                        Update-PodeWebSelect -Id 'ManagerList' -Options @('(no matches)')
                        Show-PortalToast -Message "No users matched '$Term'." -Action 'Manager Change' -Target $Term
                        return
                    }
                    Update-PodeWebSelect -Id 'ManagerList' -Options $Found
                }
                catch {
                    Show-PortalToast -Title 'Manager search failed' -Message $_.Exception.Message -Action 'Manager Change' -Target $Term -Result Failed
                }
            }

            New-PodeWebForm -Name 'ManagerSetForm' -SubmitText 'Set Manager' -Content @(
                New-PodeWebSelect -Name 'ManagerList' -Id 'ManagerList' -DisplayName 'Matches' -Options @('(find a manager first)')
            ) -ScriptBlock {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Manager Change'; return }

                # The username is the last "(...)" in the picked line
                $Pick = "$($WebEvent.Data.ManagerList)"
                if ($Pick -notmatch '\(([^()]+)\)$' -or $Pick.StartsWith('(')) {
                    Show-PortalToast -Message 'Find and pick a manager first.' -Action 'Manager Change' -Target $Selected.Sam
                    return
                }
                $ManagerSam = $Matches[1]

                try {
                    Update-UserManager -SamAccountName $Selected.Sam -ManagerSamAccountName $ManagerSam -Force | Out-Null
                    Hide-PodeWebModal
                    Show-PortalToast -Message "Manager for $($Selected.Sam) set to $ManagerSam" -Action 'Manager Change' -Target $Selected.Sam -Result Success
                    Move-PortalBack -Sam $Selected.Sam
                }
                catch {
                    Hide-PodeWebModal
                    Show-PortalToast -Title 'Manager change failed' -Message $_.Exception.Message -Action 'Manager Change' -Target $Selected.Sam -Result Failed
                }
            }
        )

        # ---------------- Update Phone Number ----------------
        # Update-UserPhone with the trimmed number. Filled with the current Office Phone when it opens.
        New-PodeWebModal -Name 'Update Office Phone' -SubmitText 'Save Phone' -AsForm -Content @(
            New-PodeWebText -Id 'PhoneWhoText' -Value 'The selected user'
            New-PodeWebTextbox -Name 'PhoneNumber' -Id 'PhoneNumber' -DisplayName 'Office Phone'
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Update Phone Number'; return }

            $Phone = "$($WebEvent.Data.PhoneNumber)".Trim()
            if (-not $Phone) {
                Show-PortalToast -Message 'Enter a phone number.' -Action 'Update Phone Number' -Target $Selected.Sam
                return
            }

            try {
                Update-UserPhone -SamAccountName $Selected.Sam -PhoneNumber $Phone -Force | Out-Null
                Hide-PodeWebModal
                Show-PortalToast -Message "Phone for $($Selected.Sam) set to $Phone" -Action 'Update Phone Number' -Target $Selected.Sam -Result Success
                Move-PortalBack -Sam $Selected.Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Phone update failed' -Message $_.Exception.Message -Action 'Update Phone Number' -Target $Selected.Sam -Result Failed
            }
        }

        # ---------------- Move User ----------------
        # Lists all OUs (sorted by CanonicalName) when it opens; Filter narrows by OU name.
        # The list shows the CanonicalName; the move uses that OU's DistinguishedName.
        New-PodeWebModal -Name 'Move User to OU' -Content @(
            New-PodeWebText -Id 'MoveWhoText' -Value 'The selected user'

            New-PodeWebForm -Name 'OUFilterForm' -SubmitText 'Filter' -Content @(
                New-PodeWebTextbox -Name 'OUFilterText' -DisplayName 'OU name contains'
            ) -ScriptBlock {
                $Filter = "$($WebEvent.Data.OUFilterText)".Trim()

                try {
                    $OUs = @(Get-ADOUList -NameFilter $Filter)
                    $Map = @{}
                    foreach ($ou in $OUs) { $Map[$ou.CanonicalName] = $ou.DistinguishedName }
                    Set-PodeState -Name 'AD_OUList' -Value $Map | Out-Null

                    if ($OUs.Count -eq 0) {
                        Update-PodeWebSelect -Id 'OUList' -Options @('(no matches)')
                        Show-PortalToast -Message "No OUs matched '$Filter'." -Action 'Move User' -Target $Filter
                        return
                    }
                    Update-PodeWebSelect -Id 'OUList' -Options @($OUs.CanonicalName)
                }
                catch {
                    Show-PortalToast -Title 'OU list failed' -Message $_.Exception.Message -Action 'Move User' -Target $Filter -Result Failed
                }
            }

            New-PodeWebForm -Name 'OUMoveForm' -SubmitText 'Move to the Selected OU' -Content @(
                New-PodeWebSelect -Name 'OUList' -Id 'OUList' -DisplayName 'Organizational Units' -Options @('(loading)')
            ) -ScriptBlock {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Move User'; return }

                $Pick = "$($WebEvent.Data.OUList)"
                $Map = Get-PodeState -Name 'AD_OUList'
                if (-not $Map -or -not $Map.ContainsKey($Pick)) {
                    Show-PortalToast -Message 'Pick an OU from the list.' -Action 'Move User' -Target $Selected.Sam
                    return
                }

                try {
                    Move-UserToOU -SamAccountName $Selected.Sam -TargetOUDistinguishedName $Map[$Pick] -Force | Out-Null
                    Hide-PodeWebModal
                    Show-PortalToast -Message "$($Selected.Sam) moved to $Pick" -Action 'Move User' -Target $Selected.Sam -Result Success
                    Move-PortalBack -Sam $Selected.Sam
                }
                catch {
                    Hide-PodeWebModal
                    Show-PortalToast -Title 'Move user failed' -Message $_.Exception.Message -Action 'Move User' -Target $Selected.Sam -Result Failed
                }
            }
        )

        # ---------------- Update Notes ----------------
        # Add-UserNote: appends the note as typed on a new line in Telephone Notes.
        New-PodeWebModal -Name 'Append Telephone Notes' -SubmitText 'Save Note' -AsForm -Content @(
            New-PodeWebText -Id 'NotesWhoText' -Value 'The selected user'
            New-PodeWebTextbox -Name 'NotesText' -DisplayName 'Note to append' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'Update Notes'; return }

            $Note = "$($WebEvent.Data.NotesText)".Trim()
            if (-not $Note) {
                Show-PortalToast -Message 'Enter a note.' -Action 'Update Notes' -Target $Selected.Sam
                return
            }

            try {
                Add-UserNote -SamAccountName $Selected.Sam -Note $Note -Force | Out-Null
                Hide-PodeWebModal
                Show-PortalToast -Message "Note added for $($Selected.Sam)" -Action 'Update Notes' -Target $Selected.Sam -Result Success
                Move-PortalBack -Sam $Selected.Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Update notes failed' -Message $_.Exception.Message -Action 'Update Notes' -Target $Selected.Sam -Result Failed
            }
        }

        # ---------------- LOA Start ----------------
        # Start-UserLOA: account expires the day after the date, cannot change password, note appended.
        New-PodeWebModal -Name 'Start LOA' -SubmitText 'Confirm LOA' -AsForm -Content @(
            New-PodeWebText -Id 'LOAStartWhoText' -Value 'The selected user'
            New-PodeWebTextbox -Name 'LOADate' -DisplayName 'Last working day' -Type Date -Value (Get-Date -Format 'yyyy-MM-dd')
            New-PodeWebTextbox -Name 'LOANote' -DisplayName 'Note' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'LOA Start'; return }

            $Date = "$($WebEvent.Data.LOADate)".Trim()
            if (-not $Date) {
                Show-PortalToast -Message 'Pick a date.' -Action 'LOA Start' -Target $Selected.Sam
                return
            }

            try {
                $Result = Start-UserLOA -SamAccountName $Selected.Sam -ExpirationDate $Date -Note "$($WebEvent.Data.LOANote)" -Force
                Hide-PodeWebModal
                Show-PortalToast -Message "LOA set for $($Selected.Sam). Account expires $($Result.AccountExpires.ToString('MM/dd/yyyy'))" -Action 'LOA Start' -Target $Selected.Sam -Result Success
                Move-PortalBack -Sam $Selected.Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'LOA Start failed' -Message $_.Exception.Message -Action 'LOA Start' -Target $Selected.Sam -Result Failed
            }
        }

        # ---------------- LOA Return ----------------
        # Stop-UserLOA: clears the expiration, allows password changes, note (required) appended.
        New-PodeWebModal -Name 'Return from LOA' -SubmitText 'Enter LOA Return' -AsForm -Content @(
            New-PodeWebText -Id 'LOAEndWhoText' -Value 'The selected user'
            New-PodeWebTextbox -Name 'LOAReturnNote' -DisplayName 'Note (required)' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'LOA Return'; return }

            $Note = "$($WebEvent.Data.LOAReturnNote)".Trim()
            if (-not $Note) {
                Show-PortalToast -Message 'A note is required.' -Action 'LOA Return' -Target $Selected.Sam
                return
            }

            try {
                Stop-UserLOA -SamAccountName $Selected.Sam -Note $Note -Force | Out-Null
                Hide-PodeWebModal
                Show-PortalToast -Message "LOA Return Entered for $($Selected.Sam)" -Action 'LOA Return' -Target $Selected.Sam -Result Success
                Move-PortalBack -Sam $Selected.Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'LOA Return failed' -Message $_.Exception.Message -Action 'LOA Return' -Target $Selected.Sam -Result Failed
            }
        }

        # ---------------- DISABLE User ----------------
        New-PodeWebModal -Name 'Confirm Disable' -SubmitText 'Yes, DISABLE' -AsForm -Content @(
            New-PodeWebText -Id 'DisableConfirmText' -Value 'DISABLE the selected user?'
            New-PodeWebTextbox -Name 'DisableNote' -DisplayName 'Note (required)' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'DISABLE User'; return }
            $Sam = $Selected.Sam

            $Note = "$($WebEvent.Data.DisableNote)".Trim()
            if (-not $Note) {
                Show-PortalToast -Message 'A note is required.' -Action 'DISABLE User' -Target $Sam
                return
            }

            try {
                Disable-User -SamAccountName $Sam -Note $Note -Force | Out-Null
                Hide-PodeWebModal
                Show-PortalToast -Message "$Sam has been Disabled." -Action 'DISABLE User' -Target $Sam -Result Success
                Move-PortalBack -Sam $Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'Disable failed' -Message $_.Exception.Message -Action 'DISABLE User' -Target $Sam -Result Failed
            }
        }

        # ---------------- DISABLE and AIRLOCK ----------------
        # Invoke-UserAirlock: disable, remove groups (except Domain Users), append note, clear
        # Title/Department/Company/Office/Manager, move to "Airlock". Note required.
        New-PodeWebModal -Name 'Confirm DISABLE and AIRLOCK' -SubmitText 'Yes, DISABLE and AIRLOCK' -AsForm -Content @(
            New-PodeWebText -Id 'AirlockConfirmText' -Value "Disable the selected user and move them to '___' OU?"
            New-PodeWebTextbox -Name 'AirlockNote' -DisplayName 'Note (required)' -Multiline
        ) -ScriptBlock {
            $Selected = Get-PodeState -Name 'AD_SelectedUser'
            if (-not $Selected) { Hide-PodeWebModal; Show-PortalToast -Message 'No user is selected.' -Action 'DISABLE and AIRLOCK'; return }
            $Sam = $Selected.Sam

            $Note = "$($WebEvent.Data.AirlockNote)".Trim()
            if (-not $Note) {
                Show-PortalToast -Message 'Notes are required to proceed. Action cancelled.' -Action 'DISABLE and AIRLOCK' -Target $Sam
                return
            }

            try {
                $Result = Invoke-UserAirlock -SamAccountName $Sam -Note $Note -Force
                Hide-PodeWebModal

                if ($Result.Warnings.Count -gt 0) {
                    Show-PortalToast -Title 'Airlock finished with warnings' -Message "$Sam moved to ___. Warnings: $($Result.Warnings -join ' | ')" -Action 'DISABLE and AIRLOCK' -Target $Sam -Result Failed
                }
                else {
                    Show-PortalToast -Message "$Sam disabled and moved to ___." -Action 'DISABLE and AIRLOCK' -Target $Sam -Result Success
                }

                Move-PortalBack -Sam $Sam
            }
            catch {
                Hide-PodeWebModal
                Show-PortalToast -Title 'DISABLE and AIRLOCK failed' -Message $_.Exception.Message -Action 'DISABLE and AIRLOCK' -Target $Sam -Result Failed
            }
        }
    }

    # =====================================================================
    # ACTION BUTTONS: what each sidebar item does when clicked.
    # This list drives the hidden sidebar triggers.
    # Each one checks a user is selected, fills in the pop-up, and opens it.
    # =====================================================================
    $Actions = @(
        @{ Name = 'Unlock Account'; Id = 'ADSidebarUnlock'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Unlock Account'; return }
                Update-PodeWebText -Id 'UnlockConfirmText' -Value "Unlock $($Selected.Name) ($($Selected.Sam))?"
                Show-PodeWebModal -Name 'Confirm Unlock'
            }
        }

        @{ Name = 'Reset Password'; Id = 'ADSidebarReset'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Reset Password'; return }
                Update-PodeWebText -Id 'ResetConfirmText' -Value "Reset the password for $($Selected.Name) ($($Selected.Sam))?"
                Show-PodeWebModal -Name 'Confirm Reset Password'
            }
        }

        # ENABLE runs straight away (no Yes/No prompt)
        @{ Name = 'ENABLE Account'; Id = 'ADSidebarEnable'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'ENABLE Account'; return }
                $Sam = $Selected.Sam

                try {
                    Enable-User -SamAccountName $Sam -Force | Out-Null
                    Show-PortalToast -Message "$Sam has been Enabled." -Action 'ENABLE Account' -Target $Sam -Result Success
                    Move-PortalBack -Sam $Sam
                }
                catch {
                    Show-PortalToast -Title 'Enable failed' -Message $_.Exception.Message -Action 'ENABLE Account' -Target $Sam -Result Failed
                }
            }
        }

        @{ Name = 'COPY User'; Id = 'ADSidebarCopy'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'COPY User'; return }
                Update-PodeWebText -Id 'CopyWhoText' -Value "Template: $($Selected.Name) ($($Selected.Sam))"
                Show-PodeWebModal -Name 'Copy User from Template'
            }
        }

        @{ Name = 'Edit Name / Email'; Id = 'ADSidebarEditName'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Edit Name / Email'; return }

                try {
                    $U = Get-ADUserDetails -SamAccountName $Selected.Sam
                    Update-PodeWebText -Id 'EditWhoText' -Value "Editing $($U.DisplayName) ($($U.SamAccountName))"
                    Update-PodeWebTextbox -Id 'EditFirst' -Value "$($U.GivenName)"
                    Update-PodeWebTextbox -Id 'EditLast' -Value "$($U.Surname)"
                    Update-PodeWebTextbox -Id 'EditDisplay' -Value "$($U.DisplayName)"
                    Update-PodeWebTextbox -Id 'EditEmail' -Value "$($U.Mail)"
                    Update-PodeWebTextbox -Id 'EditSam' -Value "$($U.SamAccountName)"
                    Show-PodeWebModal -Name 'Edit Name and Email'
                }
                catch {
                    Show-PortalToast -Title 'Could not load user' -Message $_.Exception.Message -Action 'Edit Name / Email' -Target $Selected.Sam -Result Failed
                }
            }
        }

        @{ Name = 'Edit Groups'; Id = 'ADSidebarGroups'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Edit Groups'; return }

                try {
                    $Current = @(Get-UserGroupNames -SamAccountName $Selected.Sam | Sort-Object)
                    if ($Current.Count -eq 0) { $Current = @('(no groups)') }
                    Update-PodeWebText -Id 'GroupsWhoText' -Value "Groups for $($Selected.Name) ($($Selected.Sam))"
                    Update-PodeWebSelect -Id 'GroupRemoveList' -Options $Current
                    Show-PodeWebModal -Name 'Edit Group Membership'
                }
                catch {
                    Show-PortalToast -Title 'Could not load groups' -Message $_.Exception.Message -Action 'Edit Groups' -Target $Selected.Sam -Result Failed
                }
            }
        }

        @{ Name = 'Title Change'; Id = 'ADSidebarTitle'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Title Change'; return }
                Update-PodeWebText -Id 'TitleWhoText' -Value "New title for $($Selected.Name) ($($Selected.Sam))"
                Show-PodeWebModal -Name 'Change Title'
            }
        }

        @{ Name = 'Manager Change'; Id = 'ADSidebarManager'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Manager Change'; return }
                Update-PodeWebText -Id 'ManagerWhoText' -Value "New manager for $($Selected.Name) ($($Selected.Sam))"
                Show-PodeWebModal -Name 'Change Manager'
            }
        }

        @{ Name = 'Update Phone Number'; Id = 'ADSidebarPhone'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Update Phone Number'; return }

                try {
                    $U = Get-ADUserDetails -SamAccountName $Selected.Sam
                    Update-PodeWebText -Id 'PhoneWhoText' -Value "Office phone for $($Selected.Name) ($($Selected.Sam))"
                    Update-PodeWebTextbox -Id 'PhoneNumber' -Value "$($U.OfficePhone)"
                    Show-PodeWebModal -Name 'Update Office Phone'
                }
                catch {
                    Show-PortalToast -Title 'Could not load user' -Message $_.Exception.Message -Action 'Update Phone Number' -Target $Selected.Sam -Result Failed
                }
            }
        }

        @{ Name = 'Move User'; Id = 'ADSidebarMove'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Move User'; return }

                try {
                    $OUs = @(Get-ADOUList)
                    $Map = @{}
                    foreach ($ou in $OUs) { $Map[$ou.CanonicalName] = $ou.DistinguishedName }
                    Set-PodeState -Name 'AD_OUList' -Value $Map | Out-Null

                    Update-PodeWebText -Id 'MoveWhoText' -Value "Move $($Selected.Name) ($($Selected.Sam)) to:"
                    Update-PodeWebSelect -Id 'OUList' -Options @($OUs.CanonicalName)
                    Show-PodeWebModal -Name 'Move User to OU'
                }
                catch {
                    Show-PortalToast -Title 'Could not load OUs' -Message $_.Exception.Message -Action 'Move User' -Target $Selected.Sam -Result Failed
                }
            }
        }

        @{ Name = 'Update Notes'; Id = 'ADSidebarNotes'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'Update Notes'; return }
                Update-PodeWebText -Id 'NotesWhoText' -Value "Append to Telephone Notes for $($Selected.Name) ($($Selected.Sam))"
                Show-PodeWebModal -Name 'Append Telephone Notes'
            }
        }

        @{ Name = 'LOA Start'; Id = 'ADSidebarLOAStart'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'LOA Start'; return }
                Update-PodeWebText -Id 'LOAStartWhoText' -Value "Start LOA for $($Selected.Name) ($($Selected.Sam)). The account expires the day after the date picked."
                Show-PodeWebModal -Name 'Start LOA'
            }
        }

        @{ Name = 'LOA Return'; Id = 'ADSidebarLOAEnd'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'LOA Return'; return }
                Update-PodeWebText -Id 'LOAEndWhoText' -Value "LOA return for $($Selected.Name) ($($Selected.Sam))"
                Show-PodeWebModal -Name 'Return from LOA'
            }
        }

        @{ Name = 'DISABLE User'; Id = 'ADSidebarDisable'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'DISABLE User'; return }
                Update-PodeWebText -Id 'DisableConfirmText' -Value "DISABLE $($Selected.Name) ($($Selected.Sam))?"
                Show-PodeWebModal -Name 'Confirm Disable'
            }
        }

        @{ Name = 'DISABLE and AIRLOCK'; Id = 'ADSidebarAirlock'; Run = {
                $Selected = Get-PodeState -Name 'AD_SelectedUser'
                if (-not $Selected) { Show-PortalToast -Message 'Select a user first: click a row in the search or report results.' -Action 'DISABLE and AIRLOCK'; return }
                Update-PodeWebText -Id 'AirlockConfirmText' -Value "Are you sure you want to disable $($Selected.Name) ($($Selected.Sam)) and move them to '___' OU?"
                Show-PodeWebModal -Name 'Confirm DISABLE and AIRLOCK'
            }
        }
    )

    # Hidden buttons the sidebar items click (table-filters.js hides every id starting "ADSidebar")
    $RenderSidebarTriggers = {
        foreach ($A in $Actions) {
            New-PodeWebButton -Name "Sidebar $($A.Name)" -Id $A.Id -ScriptBlock $A.Run
        }
    }

    # =====================================================================
    # SEARCH VIEW (no user opened)
    # =====================================================================
    if ([string]::IsNullOrWhiteSpace($SelectedUser)) {

        Set-PodeState -Name 'AD_View' -Value 'search' | Out-Null

        # A normal page load (browser refresh, sidebar click) starts clean.
        # Only "Back to Search", "New Report" and actions reload with ?restore=1 to keep results.
        if ($WebEvent.Query['restore'] -ne '1') {
            'AD_LastSearch', 'AD_LastReport', 'AD_ReportResults', 'AD_SelectedUser' | ForEach-Object { Remove-PodeState -Name $_ | Out-Null }
        }

        # Last search term, remembered by the server (cleared by "New Search")
        $LastSearch = Get-PodeState -Name 'AD_LastSearch'

        # New Search: clears the remembered search, report and selection, then reloads this page empty
        New-PodeWebButton -Name 'New Search' -Icon 'refresh' -ScriptBlock {
            'AD_LastSearch', 'AD_LastReport', 'AD_ReportResults', 'AD_SelectedUser' | ForEach-Object { Remove-PodeState -Name $_ | Out-Null }
            Move-PodeWebUrl -Url '?'
        }

        & $RenderActionModals
        & $RenderSidebarTriggers

        New-PodeWebForm -Name 'Search User' -SubmitText 'Search' -AsCard -Content @(
            New-PodeWebTextbox -Name 'SearchTerm' -DisplayName 'Username, Name, or Email' -Value "$LastSearch"
        ) -ScriptBlock {

            $SearchTerm = $WebEvent.Data.SearchTerm

            if ([string]::IsNullOrWhiteSpace($SearchTerm)) {
                Show-PortalToast -Message 'Enter a search value' -Action 'Search'
                return
            }

            try {
                $results = @(Search-ADUser -SearchTerm $SearchTerm)

                # Remember this search so "Back to Search" can bring the results back
                Set-PodeState -Name 'AD_LastSearch' -Value $SearchTerm | Out-Null

                if ($results.Count -eq 0) {
                    Clear-PodeWebTable -Name 'SearchResults'
                    Show-PortalToast -Message "No users matched '$SearchTerm'" -Action 'Search' -Target $SearchTerm
                    return
                }

                $results | Update-PodeWebTable -Name 'SearchResults'
                Show-PortalToast -Message "$($results.Count) match(es) found for '$SearchTerm'" -Action 'Search' -Target $SearchTerm -Result Success
            }
            catch {
                Show-PortalToast -Title 'Search failed' -Message $_.Exception.Message -Action 'Search' -Target $SearchTerm -Result Failed
            }
        }

        # Single-click a row = select the user; double-click = open the user (see table-filters.js).
        # When the page loads, this re-runs the last search (if there is one) so results come back.
        New-PodeWebTable -Name 'SearchResults' -DisplayName 'Matches' -DataColumn 'SamAccountName' -Click -Compact -SimpleFilter -NoRefresh -NoExport -ScriptBlock {
            $LastSearch = Get-PodeState -Name 'AD_LastSearch'

            if (-not [string]::IsNullOrWhiteSpace($LastSearch)) {
                try {
                    Search-ADUser -SearchTerm $LastSearch
                }
                catch {
                    Show-PortalToast -Title 'Search failed' -Message $_.Exception.Message -Action 'Search' -Target $LastSearch -Result Failed
                }
            }
        }

        # -----------------------------------------------------------------
        # REPORT SEARCH: one attribute, with * wildcards
        # -----------------------------------------------------------------
        $LastReport = Get-PodeState -Name 'AD_LastReport'

        # New Report: clears only the report and its results (the user search above stays)
        New-PodeWebButton -Name 'New Report' -Icon 'refresh' -ScriptBlock {
            Remove-PodeState -Name 'AD_LastReport' | Out-Null
            Remove-PodeState -Name 'AD_ReportResults' | Out-Null
            Move-PodeWebUrl -Url '?restore=1'
        }

        $AttributeSelect = @{
            Name        = 'ReportAttribute'
            DisplayName = 'Attribute'
            Options     = @('Title', 'Department', 'Office', 'Company', 'Description', 'Phone', 'Mobile')
        }
        if ($LastReport) {
            $AttributeSelect.SelectedValue = $LastReport.Attribute
        }

        New-PodeWebForm -Name 'Report Search' -SubmitText 'Run Report' -AsCard -Content @(
            New-PodeWebSelect @AttributeSelect
            New-PodeWebTextbox -Name 'ReportValue' -DisplayName 'Value (* = wildcard)' -Value "$($LastReport.Value)"
        ) -ScriptBlock {

            $Report = @{
                Attribute = $WebEvent.Data.ReportAttribute
                Value     = $WebEvent.Data.ReportValue
            }

            try {
                $results = @(Search-ADUserByAttribute @Report)

                # Remember this report so "Back to Search" can bring the results back
                Set-PodeState -Name 'AD_LastReport' -Value $Report | Out-Null

                if ($results.Count -eq 0) {
                    Remove-PodeState -Name 'AD_ReportResults' | Out-Null
                    Clear-PodeWebTable -Name 'ReportResults'
                    Show-PortalToast -Message 'No users matched that report.' -Action 'Report' -Target "$($Report.Attribute) = $($Report.Value)"
                    return
                }

                Set-PodeState -Name 'AD_ReportResults' -Value $results | Out-Null
                $results | Update-PodeWebTable -Name 'ReportResults'

                $msg = "$($results.Count) user(s) found"
                if ($results.Count -ge 2000) { $msg = 'Showing the first 2000 users. Narrow the value if needed.' }
                Show-PortalToast -Message $msg -Action 'Report' -Target "$($Report.Attribute) = $($Report.Value)" -Result Success
            }
            catch {
                Show-PortalToast -Title 'Report failed' -Message $_.Exception.Message -Action 'Report' -Target "$($Report.Attribute) = $($Report.Value)" -Result Failed
            }
        }

        # Single-click selects, double-click opens. Column sort/filter dropdowns and
        # "Download filtered (CSV)" come from Public\table-filters.js.
        New-PodeWebTable -Name 'ReportResults' -DisplayName 'Report Results' -DataColumn 'SamAccountName' -Click -Compact -SimpleFilter -NoRefresh -NoExport -ScriptBlock {
            $Stored = Get-PodeState -Name 'AD_ReportResults'
            if ($Stored) { $Stored }
        }

        return
    }

    # =====================================================================
    # USER DETAILS VIEW (a row was double-clicked)
    # =====================================================================
    Set-PodeState -Name 'AD_View' -Value 'details' | Out-Null

    # Back to Search: returns to the search page with ?restore=1 so the last search and report come back
    $BackButton = New-PodeWebButton -Name 'Back to Search' -Icon 'arrow-left' -ScriptBlock {
        Move-PodeWebUrl -Url '?restore=1'
    }

    # New Search: forgets the last search, report and selection, then returns to an empty search page
    $NewSearchButton = New-PodeWebButton -Name 'New Search' -Icon 'magnify' -ScriptBlock {
        'AD_LastSearch', 'AD_LastReport', 'AD_ReportResults', 'AD_SelectedUser' | ForEach-Object { Remove-PodeState -Name $_ | Out-Null }
        Move-PodeWebUrl -Url '?'
    }

    try {
        $User = Get-ADUserDetails -SamAccountName $SelectedUser
        $Manager = Get-UserManager -SamAccountName $User.SamAccountName
        $Groups = @(Get-UserGroups -SamAccountName $User.SamAccountName)
    }
    catch {
        $BackButton
        $NewSearchButton
        New-PodeWebCard -Name 'User not found' -Content @(
            New-PodeWebText -Value "Could not load '$SelectedUser': $($_.Exception.Message)"
        )
        return
    }

    # The opened user is also the selected user, so sidebar actions act on them
    Set-PodeState -Name 'AD_SelectedUser' -Value @{ Sam = $User.SamAccountName; Name = $User.DisplayName } | Out-Null

    $nl = [Environment]::NewLine
    $Status = if ($User.Enabled) { 'Active' } else { 'Disabled' }
    $ManagerName = if ($Manager) { $Manager.DisplayName } else { '(none)' }

    $Details = @(
        "DISPLAY NAME: $($User.DisplayName)"
        "USERNAME: $($User.SamAccountName)"
        "EMAIL: $($User.Mail)"
        "PHONE: $($User.OfficePhone)"
        "TITLE: $($User.Title)"
        "DEPT: $($User.Department)"
        "MANAGER: $ManagerName"
        "STATUS: $Status"
        "LOCKED: $($User.LockedOut)"
        "LAST LOGON: $($User.LastLogonDate)"
        "PWD LAST SET: $($User.PasswordLastSet)"
        "CREATED: $($User.whenCreated)"
        '-----------------------------------------------'
        'TELEPHONE NOTES:'
        "$($User.Info)"
    ) -join $nl

    # Same Security Group vs Distribution split
    $SecGroups = $Groups | Where-Object { "$($_.GroupCategory)" -eq 'Security' } | ForEach-Object { "[SEC] $($_.Name)" }
    $DistLists = $Groups | Where-Object { "$($_.GroupCategory)" -eq 'Distribution' } | ForEach-Object { "[DL] $($_.Name)" }

    $GroupText = @(
        '--- SECURITY GROUPS ---'
        $SecGroups
        ''
        '--- DISTRIBUTION LISTS ---'
        $DistLists
    ) -join $nl

    $BackButton
    $NewSearchButton

    & $RenderActionModals
    & $RenderSidebarTriggers

    # Actions are in the left sidebar only (no Actions card on this view)

    New-PodeWebCard -Name "$($User.DisplayName) ($($User.SamAccountName))" -Content @(
        New-PodeWebCodeBlock -Value $Details -NoHighlight
    )

    New-PodeWebCard -Name 'Groups (Security vs Distribution)' -Content @(
        New-PodeWebCodeBlock -Value $GroupText -NoHighlight
    )
}