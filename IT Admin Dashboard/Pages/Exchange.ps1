New-UDPage `
    -Name "Exchange" `
    -Content {

    New-UDTypography `
        -Text "Exchange Distribution Group Manager" `
        -Variant h4

    New-UDDivider

    #
    # USER SEARCH
    #

    New-UDCard `
        -Title "User Search" `
        -Content {

        New-UDTextbox `
            -Id "EXOUserSearch" `
            -Label "Username / Name / Email"

        New-UDButton `
            -Text "Search User" `
            -OnClick {

                $Session:UserSearch =
                    (Get-UDElement -Id "EXOUserSearch").Value

                Sync-UDElement -Id "EXOUserResults"
            }

        New-UDDynamic `
            -Id "EXOUserResults" `
            -Content {

            if (-not $Session:UserSearch) {
                return
            }

            try {

                $Users =
                    Search-MailboxUser `
                        -SearchTerm $Session:UserSearch

                New-UDTable `
                    -Data $Users `
                    -ShowSearch `
                    -ShowPagination
            }
            catch {

                New-UDAlert `
                    -Text $_.Exception.Message `
                    -Severity Error
            }
        }
    }

    New-UDDivider

    #
    # DISTRIBUTION GROUP SEARCH
    #

    New-UDCard `
        -Title "Distribution Group Search" `
        -Content {

        New-UDTextbox `
            -Id "DLSearch" `
            -Label "Distribution Group Name"

        New-UDButton `
            -Text "Search Groups" `
            -OnClick {

                $Session:DLSearch =
                    (Get-UDElement -Id "DLSearch").Value

                Sync-UDElement -Id "DLResults"
            }

        New-UDDynamic `
            -Id "DLResults" `
            -Content {

            if (-not $Session:DLSearch) {
                return
            }

            try {

                $DLs =
                    Search-DistributionGroup `
                        -SearchTerm $Session:DLSearch

                New-UDTable `
                    -Data $DLs `
                    -ShowSearch `
                    -ShowPagination
            }
            catch {

                New-UDAlert `
                    -Text $_.Exception.Message `
                    -Severity Error
            }
        }
    }

    New-UDDivider

    #
    # QUICK ADD
    #

    New-UDCard `
        -Title "Quick Add User To Distribution Group" `
        -Content {

        New-UDTextbox `
            -Id "AddUserUPN" `
            -Label "User Email / UPN"

        New-UDTextbox `
            -Id "AddDLName" `
            -Label "Distribution Group"

        New-UDButton `
            -Text "Add User" `
            -OnClick {

                try {

                    $User =
                        (Get-UDElement -Id "AddUserUPN").Value

                    $DL =
                        (Get-UDElement -Id "AddDLName").Value

                    Add-DLMember `
                        -Group $DL `
                        -Member $User

                    Show-UDToast `
                        -Message "User added successfully." `
                        -Duration 5000
                }
                catch {

                    Show-UDToast `
                        -Message $_.Exception.Message `
                        -Duration 5000
                }
            }
    }

    New-UDDivider

    #
    # QUICK REMOVE
    #

    New-UDCard `
        -Title "Quick Remove User From Distribution Group" `
        -Content {

        New-UDTextbox `
            -Id "RemoveUserUPN" `
            -Label "User Email / UPN"

        New-UDTextbox `
            -Id "RemoveDLName" `
            -Label "Distribution Group"

        New-UDButton `
            -Text "Remove User" `
            -OnClick {

                try {

                    $User =
                        (Get-UDElement -Id "RemoveUserUPN").Value

                    $DL =
                        (Get-UDElement -Id "RemoveDLName").Value

                    Remove-DLMember `
                        -Group $DL `
                        -Member $User

                    Show-UDToast `
                        -Message "User removed successfully." `
                        -Duration 5000
                }
                catch {

                    Show-UDToast `
                        -Message $_.Exception.Message `
                        -Duration 5000
                }
            }
    }

    New-UDDivider

    #
    # VIEW MEMBERS
    #

    New-UDCard `
        -Title "View Distribution Group Members" `
        -Content {

        New-UDTextbox `
            -Id "ViewMembersDL" `
            -Label "Distribution Group"

        New-UDButton `
            -Text "View Members" `
            -OnClick {

                $Session:ViewDL =
                    (Get-UDElement -Id "ViewMembersDL").Value

                Sync-UDElement -Id "DLMembers"
            }

        New-UDDynamic `
            -Id "DLMembers" `
            -Content {

            if (-not $Session:ViewDL) {
                return
            }

            try {

                $Members =
                    Get-DLMembers `
                        -Group $Session:ViewDL

                New-UDTable `
                    -Data $Members `
                    -ShowSearch `
                    -ShowPagination `
                    -Dense
            }
            catch {

                New-UDAlert `
                    -Text $_.Exception.Message `
                    -Severity Error
            }
        }
    }
}