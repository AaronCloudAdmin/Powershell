#Requires -Modules ActiveDirectory

<#
    AD_Users
    Daily AD user tasks. Works the same from a pwsh prompt or from the Pode.Web dashboard.

    Design rules for every function in this module:
      - Never fail silently: AD calls use -ErrorAction Stop so errors surface at the prompt
        and as an error toast in the web app.
      - Functions that change an account ask "(y/n)" first when run at the prompt.
        The web pages do their own confirmation in the browser and then call the function
        with -Force, which skips the y/n prompt (a web runspace has no console to answer it).
      - Return objects, never formatted text. The caller decides how to display them.
#>

$script:DefaultDC = '_____'

# Used by Copy-ADUserFromTemplate
$script:LicenseGroups = @('__', '__')  # M365 license group names held back until the remote mailbox exists
$script:RemoteRoutingDomain = '___'   # <tenant>.mail.onmicrosoft.com (shown in the Enable-RemoteMailbox command)
$script:PrimarySmtpDomain = '___'     # email domain: new users' UPN, and the Enable-RemoteMailbox command

#region Private helpers

function ConvertTo-LdapSafeString {
    # Escapes LDAP filter special characters (RFC 4515) so typed input can't break or widen the filter.
    param([Parameter(Mandatory)][string]$Value)

    $map = @{
        '\'             = '\5c'
        '*'             = '\2a'
        '('             = '\28'
        ')'             = '\29'
        [string][char]0 = '\00'
    }

    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Value.ToCharArray()) {
        $key = [string]$ch
        if ($map.ContainsKey($key)) { [void]$sb.Append($map[$key]) }
        else { [void]$sb.Append($ch) }
    }
    $sb.ToString()
}

function Confirm-ADAction {
    # Returns $true if the caller answered y / yes. Anything else cancels.
    param([Parameter(Mandatory)][string]$Message)

    $answer = Read-Host "$Message (y/n)"
    if ($answer -match '^(y|yes)$') { return $true }

    Write-Warning 'Cancelled. No changes made.'
    return $false
}

function Join-Info {
    # Telephone Notes (info) with one more line appended. [Environment]::NewLine is CRLF on Windows,
    # which is what ADUC expects in the Notes field.
    param($Info, $Line)
    "$Info$([Environment]::NewLine)$Line".Trim()
}

function ConvertTo-NameLetters {
    # Letters A-Z only, for usernames and addresses: accents become plain letters (an accented e -> e),
    # spaces, hyphens, apostrophes and anything else are dropped (Van Dyke-O'Brien -> VanDykeOBrien).
    param([string]$Value)
    ($Value.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '') -replace '[^A-Za-z]', ''
}

# Search result column: name of the user's parent container (OU)
$script:OUColumn = @{ Name = 'OU'; Expression = {
        $parent = $_.DistinguishedName -replace '^CN=.*?,(?=OU=|CN=)', ''
        ($parent -split ',')[0] -replace '^(OU|CN)=', ''
    }
}

#endregion

#region Public functions

function Search-ADUser {
    <#
        Accepts any of these and returns every match so you can confirm the right person:
          jsmith          sAMAccountName (partial OK)
          Smith, John     display name in "Last, First" form (partials OK: "Smi, Jo")
          Smith,          last name only
          John            first name, last name, username, display name or email (partial OK)
          John Smith      first and last name in either order
        The DC does the filtering, so this stays fast in a large directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SearchTerm,

        [string]$Server = $script:DefaultDC,

        [int]$ResultSize = 100
    )

    $term = $SearchTerm.Trim()

    if ($term -like '*,*') {
        # "Last, First"
        $parts = $term -split ',', 2
        $last = ConvertTo-LdapSafeString -Value $parts[0].Trim()
        $first = ConvertTo-LdapSafeString -Value $parts[1].Trim()

        if ($first) { $inner = "(&(sn=$last*)(givenName=$first*))" }
        else { $inner = "(sn=$last*)" }
    }
    elseif ($term -like '* *') {
        # "First Last" or "Last First" - anr resolves both orders against givenName/sn.
        $safe = ConvertTo-LdapSafeString -Value $term
        $inner = "(|(anr=$safe)(displayName=*$safe*))"
    }
    else {
        # Single word: match it anywhere it could reasonably be.
        $safe = ConvertTo-LdapSafeString -Value $term
        $inner = "(|(sAMAccountName=*$safe*)(givenName=$safe*)(sn=$safe*)(displayName=*$safe*)(mail=$safe*))"
    }

    $params = @{
        LDAPFilter    = "(&(objectCategory=person)(objectClass=user)$inner)"
        Properties    = 'DisplayName', 'Mail', 'Title', 'Department', 'Enabled', 'LockedOut'
        Server        = $Server
        ResultSetSize = $ResultSize
        ErrorAction   = 'Stop'
    }

    Get-ADUser @params |
    Sort-Object DisplayName |
    Select-Object DisplayName, SamAccountName, Title, Department,
    $script:OUColumn,
    Enabled, LockedOut, Mail
}

function Search-ADUserByAttribute {
    <#
        Report-style search on one attribute, with * wildcards.
          Search-ADUserByAttribute -Attribute Title -Value '*___*'
          Search-ADUserByAttribute -Attribute Department -Value 'Information Technology'
          Search-ADUserByAttribute -Attribute Office -Value 'Office*' -Status Enabled
          Search-ADUserByAttribute -Attribute Title -Value '*'      (everyone who has any title)
        A value typed without any * is treated as "contains" (___ = *___*).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Title', 'Department', 'Office', 'Company', 'Description', 'Phone', 'Mobile')]
        [string]$Attribute,

        [string]$Value = '*',

        [ValidateSet('All', 'Enabled', 'Disabled')]
        [string]$Status = 'All',

        [string]$Server = $script:DefaultDC,

        [int]$ResultSize = 2000
    )

    # Friendly name -> LDAP attribute name
    $AttributeMap = @{
        Title       = 'title'
        Department  = 'department'
        Office      = 'physicalDeliveryOfficeName'
        Company     = 'company'
        Description = 'description'
        Phone       = 'telephoneNumber'
        Mobile      = 'mobile'
    }
    $LdapAttribute = $AttributeMap[$Attribute]

    $Pattern = "$Value".Trim()
    if (-not $Pattern) { $Pattern = '*' }
    if (-not $Pattern.Contains('*')) { $Pattern = "*$Pattern*" }

    # Escape everything except the * wildcards the user typed
    $SafePattern = ($Pattern -split '\*' | ForEach-Object {
            if ($_) { ConvertTo-LdapSafeString -Value $_ } else { '' }
        }) -join '*'

    $StatusFilter = switch ($Status) {
        'Enabled' { '(!(userAccountControl:1.2.840.113556.1.4.803:=2))' }
        'Disabled' { '(userAccountControl:1.2.840.113556.1.4.803:=2)' }
        default { '' }
    }

    $params = @{
        LDAPFilter    = "(&(objectCategory=person)(objectClass=user)($LdapAttribute=$SafePattern)$StatusFilter)"
        Properties    = 'DisplayName', 'Title', 'Department', 'physicalDeliveryOfficeName', 'Company',
        'Manager', 'Mail', 'Enabled', 'LockedOut'
        Server        = $Server
        ResultSetSize = $ResultSize
        ErrorAction   = 'Stop'
    }

    Get-ADUser @params |
    Sort-Object DisplayName |
    Select-Object DisplayName, SamAccountName, Title, Department,
    @{ Name = 'Office'; Expression = { $_.physicalDeliveryOfficeName } },
    Company,
    @{ Name = 'Manager'; Expression = {
            # Manager's name from the DN, e.g. "CN=Smith\, John,OU=..." -> "Smith, John"
            if ($_.Manager) { (($_.Manager -split '(?<!\\),')[0] -replace '^CN=', '') -replace '\\,', ',' }
        }
    },
    $script:OUColumn,
    Enabled, LockedOut, Mail
}

function Get-ADUserDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$SamAccountName,

        [string]$Server = $script:DefaultDC
    )

    process {
        $params = @{
            Identity    = $SamAccountName
            Properties  = 'DisplayName', 'Mail', 'Title', 'Department', 'OfficePhone', 'Manager',
            'Enabled', 'LockedOut', 'Info', 'MemberOf', 'LastLogonDate',
            'PasswordLastSet', 'whenCreated'
            Server      = $Server
            ErrorAction = 'Stop'
        }
        Get-ADUser @params
    }
}

function Unlock-User {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Unlock $SamAccountName?")) { return }

    Unlock-ADAccount -Identity $SamAccountName -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties LockedOut -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, LockedOut
}

function Reset-UserPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [securestring]$NewPassword,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Reset password for $SamAccountName?")) { return }

    # No password passed in: use the default
    if (-not $NewPassword) {
        $NewPassword = ConvertTo-SecureString "_____" -AsPlainText -Force
    }

    Set-ADAccountPassword -Identity $SamAccountName -Reset -NewPassword $NewPassword -Server $Server -ErrorAction Stop

    Set-ADUser -Identity $SamAccountName -ChangePasswordAtLogon $true -Server $Server -ErrorAction Stop

    Unlock-ADAccount -Identity $SamAccountName -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties LockedOut, PasswordLastSet -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, LockedOut, PasswordLastSet
}

function Enable-User {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "ENABLE $SamAccountName?")) { return }

    Enable-ADAccount -Identity $SamAccountName -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, Enabled
}

function Disable-User {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        # Optional: appended to Telephone Notes (info) after the account is disabled
        [string]$Note,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "DISABLE $SamAccountName?")) { return }

    Disable-ADAccount -Identity $SamAccountName -Server $Server -ErrorAction Stop

    if ($Note) {
        $cur = Get-ADUser -Identity $SamAccountName -Properties info -Server $Server -ErrorAction Stop
        Set-ADUser -Identity $SamAccountName -Replace @{ info = Join-Info $cur.info $Note } -Server $Server -ErrorAction Stop
    }

    Get-ADUser -Identity $SamAccountName -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, Enabled
}

function Update-UserPhone {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [string]$PhoneNumber,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Set office phone for $SamAccountName to $PhoneNumber?")) { return }

    Set-ADUser -Identity $SamAccountName -OfficePhone $PhoneNumber -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties OfficePhone -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, OfficePhone
}

function Update-UserNotes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [string]$Note,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Append note to $SamAccountName?")) { return }

    $current = Get-ADUser -Identity $SamAccountName -Properties Info -Server $Server -ErrorAction Stop

    Set-ADUser -Identity $SamAccountName -Replace @{ info = Join-Info $current.Info $Note } -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties Info -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, Info
}

function Update-UserManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [string]$ManagerSamAccountName,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    $manager = Get-ADUser -Identity $ManagerSamAccountName -Properties DisplayName -Server $Server -ErrorAction Stop

    if (-not $Force -and -not (Confirm-ADAction "Set manager for $SamAccountName to $($manager.DisplayName)?")) { return }

    Set-ADUser -Identity $SamAccountName -Manager $manager.DistinguishedName -Server $Server -ErrorAction Stop

    Get-UserManager -SamAccountName $SamAccountName -Server $Server
}

function Update-UserTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Server = $script:DefaultDC,

        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Set title/description for $SamAccountName to '$Title'?")) { return }

    Set-ADUser -Identity $SamAccountName -Replace @{ title = $Title; description = $Title } -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties Title, Description -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, Title, Description
}

function Get-UserGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$SamAccountName,

        [string]$Server = $script:DefaultDC
    )

    process {
        # One query: ask the DC for every group whose member list contains this user.
        $User = Get-ADUser -Identity $SamAccountName -Server $Server -ErrorAction Stop
        $UserDN = ConvertTo-LdapSafeString -Value $User.DistinguishedName

        $Groups = Get-ADGroup -LDAPFilter "(member=$UserDN)" -Properties GroupCategory, GroupScope -Server $Server -ErrorAction Stop

        $Groups |
        Sort-Object Name |
        Select-Object Name, GroupCategory, GroupScope
    }
}

function Get-UserManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$SamAccountName,

        [string]$Server = $script:DefaultDC
    )

    process {
        $user = Get-ADUser -Identity $SamAccountName -Properties Manager -Server $Server -ErrorAction Stop
        if (-not $user.Manager) { return }

        Get-ADUser -Identity $user.Manager -Properties DisplayName -Server $Server -ErrorAction Stop |
        Select-Object DisplayName, SamAccountName
    }
}

function Get-ADDomainDnsRoot {
    # The AD domain's DNS name
    param([string]$Server = $script:DefaultDC)
    (Get-ADDomain -Server $Server -ErrorAction Stop).DNSRoot
}

function Copy-ADUserFromTemplate {
    <#
        COPY User button, step 1.
        New user from a template: SAM = first initial + Lastname, letters only (made unique with 1, 2, ...),
        UPN = SAM@$script:PrimarySmtpDomain (matches the email), same OU, password set to default, must change at logon, enabled,
        copies Description/Office/Title/Department/Company/Manager and every group EXCEPT the
        M365 license groups in $script:LicenseGroups. Those are returned in HeldGroups and added
        by Add-UserLicenseGroups once Enable-RemoteMailbox has been run on the Exchange Tools Server
        (so the license cannot create a cloud-only mailbox first).
        Returns SamAccountName, UserPrincipalName, OU, HeldGroups, TemplatePhone, MailboxCommand.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplateSamAccountName,
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Create a copy of $TemplateSamAccountName for $FirstName $LastName?")) { return }

    $fName = $FirstName.Trim()
    $lName = $LastName.Trim()

    $template = Get-ADUser -Identity $TemplateSamAccountName -Properties DistinguishedName, MemberOf, Description, PhysicalDeliveryOfficeName, Title, Department, Company, Manager, OfficePhone -Server $Server -ErrorAction Stop

    # Username: letters only. Display name, first name and surname keep what was typed (hyphens too).
    $fLetters = ConvertTo-NameLetters $fName
    $lLetters = ConvertTo-NameLetters $lName
    if (-not $fLetters -or -not $lLetters) { throw 'First Name and Last Name must contain letters.' }
    $fInit = $fLetters.Substring(0, 1).ToUpper()
    $capSur = $lLetters.Substring(0, 1).ToUpper() + $lLetters.Substring(1).ToLower()
    $baseSam = $fInit + $capSur
    $finalSam = $baseSam
    $count = 1
    # Unique across SAM, UPN, mail and proxyAddresses (smtp: matches SMTP: too): JSmith, JSmith1, JSmith2, ...
    while ($true) {
        $sam = ConvertTo-LdapSafeString -Value $finalSam
        $addr = ConvertTo-LdapSafeString -Value "$finalSam@$script:PrimarySmtpDomain"
        $taken = Get-ADObject -LDAPFilter "(|(sAMAccountName=$sam)(userPrincipalName=$addr)(mail=$addr)(proxyAddresses=smtp:$addr))" -Server $Server -ErrorAction Stop
        if (-not $taken) { break }
        $finalSam = $baseSam + $count
        $count++
    }

    $finalUPN = "$finalSam@$script:PrimarySmtpDomain"   # UPN matches the email
    $targetOU = $template.DistinguishedName -replace '^CN=.*?,(?=OU=|CN=)', ''
    $pass = ConvertTo-SecureString "______:" -AsPlainText -Force

    $newUser = @{
        Name                  = "$lName, $fName"
        SamAccountName        = $finalSam
        UserPrincipalName     = $finalUPN
        DisplayName           = "$lName, $fName"
        GivenName             = $fName
        Surname               = $lName
        Path                  = $targetOU
        AccountPassword       = $pass
        ChangePasswordAtLogon = $true
        Enabled               = $true
        Description           = $template.Description
        Office                = $template.PhysicalDeliveryOfficeName
        Title                 = $template.Title
        Department            = $template.Department
        Company               = $template.Company
        Manager               = $template.Manager
        Server                = $Server
        ErrorAction           = 'Stop'
    }
    New-ADUser @newUser

    # Copy every group except the M365 license groups, which are held back
    $held = [System.Collections.Generic.List[string]]::new()
    foreach ($groupDN in $template.MemberOf) {
        $groupObj = Get-ADGroup -Identity $groupDN -Server $Server -ErrorAction Stop
        if ($script:LicenseGroups -contains $groupObj.Name) {
            $held.Add($groupObj.DistinguishedName)
        }
        else {
            Add-ADGroupMember -Identity $groupObj -Members $finalSam -Server $Server -ErrorAction Stop
        }
    }

    [PSCustomObject]@{
        SamAccountName    = $finalSam
        UserPrincipalName = $finalUPN
        OU                = $targetOU
        HeldGroups        = @($held)
        TemplatePhone     = "$($template.OfficePhone)"
        MailboxCommand    = "Enable-RemoteMailbox `"$finalSam`" -RemoteRoutingAddress `"$finalSam@$script:RemoteRoutingDomain`" -PrimarySmtpAddress `"$finalSam@$script:PrimarySmtpDomain`""
    }
}

function Add-UserLicenseGroups {
    <#
        COPY User button, step 2 (after Enable-RemoteMailbox has been run on the Exchange Tools Server).
        Adds the M365 license groups that Copy-ADUserFromTemplate held back.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [string[]]$GroupDistinguishedName = @(),
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Has Enable-RemoteMailbox been run for $SamAccountName? Add the M365 license group(s) now?")) { return }

    $groups = @($GroupDistinguishedName | Where-Object { $_ })
    foreach ($groupDN in $groups) {
        Add-ADGroupMember -Identity $groupDN -Members $SamAccountName -Server $Server -ErrorAction Stop
    }

    [PSCustomObject]@{ SamAccountName = $SamAccountName; GroupsAdded = $groups.Count }
}

function Update-UserIdentity {
    <#
        Edit Name / Email button ("Save & Sync All Attributes").
        Sets First, Last, Display Name and SAM. When an Email is given it becomes both mail and the
        UPN; a blank Email leaves mail and UPN unchanged. Appends the note (as typed, only if one is
        given) to Telephone Notes, then renames the AD object to the Display Name (cn, name and
        DistinguishedName).
        Mail-enabled users (mailNickname already set) also get, when an Email is given:
          proxyAddresses  new email becomes SMTP: (primary), the old primary is kept as smtp:
          mailNickname    new SAM
          targetAddress   SMTP:<new SAM>@$script:RemoteRoutingDomain (only if already set; the
                          new routing address is also added as smtp:)
        Other proxy addresses (x500:, sip:, older smtp:) are kept.
        Returns the (possibly new) SamAccountName.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName,
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$Email,
        [Parameter(Mandatory)][string]$NewSamAccountName,
        [string]$Note,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Rename and Sync $SamAccountName?")) { return }

    $u = Get-ADUser -Identity $SamAccountName -Properties GivenName, Surname, DisplayName, mail, SamAccountName, DistinguishedName, info, proxyAddresses, mailNickname, targetAddress -Server $Server -ErrorAction Stop

    $newSam = $NewSamAccountName.Trim()
    $newMail = "$Email".Trim()

    # No spaces or hyphens in a new username or in the part of a new email before the @
    if ($newSam -ne $u.SamAccountName -and $newSam -match '[\s-]') { throw "Username '$newSam' can't contain spaces or hyphens." }
    if ($newMail -and $newMail -ne $u.mail -and ($newMail -split '@')[0] -match '[\s-]') { throw "Email '$newMail' can't contain spaces or hyphens before the @." }
    $newUPN = if ($newMail) { $newMail } else { $u.UserPrincipalName }

    $set = @{
        Identity       = $u.DistinguishedName
        GivenName      = $FirstName.Trim()
        Surname        = $LastName.Trim()
        DisplayName    = $DisplayName.Trim()
        SamAccountName = $newSam
        Server         = $Server
        ErrorAction    = 'Stop'
    }
    if ($newMail) {
        $set.EmailAddress = $newMail
        $set.UserPrincipalName = $newMail
    }

    $replace = @{}
    if ("$Note".Trim()) { $replace.info = Join-Info $u.info ("$Note".Trim()) }

    if ($newMail -and $u.mailNickname) {
        # Old primary SMTP: becomes secondary smtp:, new email becomes the only SMTP:
        $proxies = @($u.proxyAddresses | ForEach-Object { if ($_ -clike 'SMTP:*') { 'smtp:' + $_.Substring(5) } else { $_ } } |
            Where-Object { $_ -ne "smtp:$newMail" })
        $proxies = @("SMTP:$newMail") + $proxies

        if ($u.targetAddress) {
            $route = "$newSam@$script:RemoteRoutingDomain"
            $replace.targetAddress = "SMTP:$route"
            if ($proxies -notcontains "smtp:$route") { $proxies += "smtp:$route" }
        }

        $replace.proxyAddresses = [string[]]$proxies
        $replace.mailNickname = $newSam
    }

    if ($replace.Count) { $set.Replace = $replace }
    Set-ADUser @set

    Rename-ADObject -Identity $u.DistinguishedName -NewName $DisplayName.Trim() -Server $Server -ErrorAction Stop

    [PSCustomObject]@{ SamAccountName = $newSam; UserPrincipalName = $newUPN; DisplayName = $DisplayName.Trim() }
}

function Update-UserTitleWithNote {
    <#
        Title Change button.
        Sets Title and Description to the new title and appends the note (as typed, no timestamp)
        to Telephone Notes. Both are required.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Note,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Change title for $SamAccountName to '$Title'?")) { return }

    $cur = Get-ADUser -Identity $SamAccountName -Properties info -Server $Server -ErrorAction Stop
    $newNotes = Join-Info $cur.info $Note

    Set-ADUser -Identity $SamAccountName -Replace @{ title = $Title; description = $Title; info = $newNotes } -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties Title, Description -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, Title, Description
}

function Add-UserNote {
    <#
        Update Notes button.
        Appends the note, as typed (no timestamp), on a new line in Telephone Notes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Note,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Append note to $SamAccountName?")) { return }

    $cur = Get-ADUser -Identity $SamAccountName -Properties info -Server $Server -ErrorAction Stop
    $newNotes = Join-Info $cur.info $Note

    Set-ADUser -Identity $SamAccountName -Replace @{ info = $newNotes } -Server $Server -ErrorAction Stop

    Get-ADUser -Identity $SamAccountName -Properties Info -Server $Server -ErrorAction Stop |
    Select-Object SamAccountName, Info
}

function Find-ADManagerCandidate {
    <#
        Manager Change button, search step: anr search by name or username.
        Returns DisplayName, Title, SamAccountName and OU for each match.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SearchTerm,
        [string]$Server = $script:DefaultDC
    )

    $term = $SearchTerm.Trim().Replace("'", "''")

    Get-ADUser -Filter "anr -eq '$term'" -Properties Title, DistinguishedName, DisplayName -Server $Server -ErrorAction Stop |
    Select-Object DisplayName, Title, SamAccountName,
    @{ Name = 'OU'; Expression = {
            $ou = ($_.DistinguishedName -split ',OU=')[1] -split ',' | Select-Object -First 1
            if (-not $ou) { 'Users' } else { $ou }
        }
    }
}

function Start-UserLOA {
    <#
        LOA Start button.
        Account expires the day AFTER the date given, user cannot change password, and the note
        (as typed) is appended to Telephone Notes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$ExpirationDate,
        [string]$Note,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    $expiration = (Get-Date $ExpirationDate -ErrorAction Stop).AddDays(1)

    if (-not $Force -and -not (Confirm-ADAction "Confirm LOA for $SamAccountName?")) { return }

    $u = Get-ADUser -Identity $SamAccountName -Properties info -Server $Server -ErrorAction Stop
    $updNotes = Join-Info $u.info ("$Note".Trim())

    Set-ADAccountExpiration -Identity $SamAccountName -DateTime $expiration -Server $Server -ErrorAction Stop
    Set-ADUser -Identity $SamAccountName -CannotChangePassword $true -Replace @{ info = $updNotes } -Server $Server -ErrorAction Stop

    [PSCustomObject]@{ SamAccountName = $SamAccountName; AccountExpires = $expiration }
}

function Stop-UserLOA {
    <#
        LOA Return button.
        Clears the account expiration, allows password changes again, and appends the note
        (required, as typed) to Telephone Notes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Note,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Enter LOA return for $SamAccountName?")) { return }

    Clear-ADAccountExpiration -Identity $SamAccountName -Server $Server -ErrorAction Stop
    Set-ADUser -Identity $SamAccountName -CannotChangePassword $false -Server $Server -ErrorAction Stop

    $cur = Get-ADUser -Identity $SamAccountName -Properties info -Server $Server -ErrorAction Stop
    Set-ADUser -Identity $SamAccountName -Replace @{ info = Join-Info $cur.info $Note } -Server $Server -ErrorAction Stop

    [PSCustomObject]@{ SamAccountName = $SamAccountName; LOA = 'Returned' }
}

function Get-ADOUList {
    <#
        Move User button, list step: all OUs (optionally filtered by name), sorted
        by CanonicalName.
    #>
    [CmdletBinding()]
    param(
        [string]$NameFilter = '',
        [string]$Server = $script:DefaultDC
    )

    Get-ADOrganizationalUnit -Filter * -Properties CanonicalName -Server $Server -ErrorAction Stop |
    Where-Object { $_.Name -like "*$NameFilter*" } |
    Sort-Object CanonicalName |
    Select-Object Name, CanonicalName, DistinguishedName
}

function Move-UserToOU {
    <# Move User button, move step: moves the user object to the chosen OU. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$TargetOUDistinguishedName,
        [string]$Server = $script:DefaultDC,
        [switch]$Force
    )

    if (-not $Force -and -not (Confirm-ADAction "Move $SamAccountName to $TargetOUDistinguishedName?")) { return }

    $u = Get-ADObject -Filter "SamAccountName -eq '$SamAccountName'" -Properties DistinguishedName -Server $Server -ErrorAction Stop
    Move-ADObject -Identity $u.DistinguishedName -TargetPath $TargetOUDistinguishedName -Server $Server -ErrorAction Stop

    [PSCustomObject]@{ SamAccountName = $SamAccountName; MovedTo = $TargetOUDistinguishedName }
}

#endregion

# The manifest (FunctionsToExport) is the source of truth for exports. This line keeps the
# helpers private if someone imports the .psm1 directly instead of the .psd1.
Export-ModuleMember -Function @(
    'Search-ADUser', 'Search-ADUserByAttribute', 'Get-ADUserDetails', 'Unlock-User', 'Reset-UserPassword',
    'Enable-User', 'Disable-User', 'Update-UserPhone', 'Update-UserNotes',
    'Update-UserManager', 'Update-UserTitle', 'Get-UserGroups', 'Get-UserManager',
    'Get-ADDomainDnsRoot', 'Copy-ADUserFromTemplate', 'Add-UserLicenseGroups', 'Update-UserIdentity', 'Update-UserTitleWithNote', 'Add-UserNote', 'Find-ADManagerCandidate', 'Start-UserLOA', 'Stop-UserLOA', 'Get-ADOUList', 'Move-UserToOU'
)
