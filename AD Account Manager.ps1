# Description  : Automates user management such as
#                reset, unlock, change pw at next log on
# ======================================================
# to get a list of avaiable properties Get-ADUser -Filter {SamAccountName -eq "username here"} -Properties *

# Import Active Directory module (if not already loaded)
Import-Module ActiveDirectory


# declare ahead of time for later use
$UserName = $null

Write-Host ""

while($true){

    #if we need to ask for a username
    if($UserName -eq $null){
        
        # Prompt for username
        $UserName = Read-Host "`n`nEnter the username"

        # Check if the username is empty
        if (-not $UserName) {
            Write-Host "Error: No username entered. Please try again." -ForegroundColor Red
            continue # restarts the loop
        }

        # Check if exit command
        if ($UserName -eq "exit") {
            Write-Host "Exiting script and closing PowerShell..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            exit  # Completely closes the PowerShell window
        }
    }

    # Retrieve user details from Active Directory
    $User = Get-ADUser -Filter {SamAccountName -eq $UserName} -Server $dc -Property *

    #if user is found
    if ($User) {
        
        # Display user details
        Write-Host "`nUser Found: $($User.DisplayName)" -ForegroundColor Magenta
        Write-Host "Job Title: $($User.Title)" -ForegroundColor Magenta
        Write-Host "Office: $($User.Office)" -ForegroundColor Magenta
        Write-Host "Department: $($User.Department)" -ForegroundColor Magenta
        # Check if the Manager property exists
        if ($User.Manager) {
            # Get the manager's AD object
            $manager = Get-ADUser -Identity $user.Manager -Server $dc
            Write-Host "Manager: $($manager.Name)" -ForegroundColor Magenta
        }
        else {Write-Host "Manager: " -ForegroundColor Magenta}
        Write-Host "Account Active: $($User.Enabled)" -ForegroundColor Magenta
        Write-Host "Password Expired: $($User.PasswordExpired)" -ForegroundColor Magenta
        Write-Host "Password Last Set: $($User.PasswordLastSet)" -ForegroundColor Magenta
        Write-Host "Account lockedOut: $($User.LockedOut)" -ForegroundColor Magenta
              
        # Display action options
        Write-Host "what would you like to do"
        Write-Host "1. Reset User Password"
        Write-Host "2. Unlock User Account"
        Write-Host "3. User must change pw at next logon"
        Write-Host "4. Refresh Info"
        Write-Host "5. Cancel, choose another user"
        Write-Host "0. Exit and close"

        # Get user input
        $choice = Read-Host "Enter your choice number (1-5)"

        switch ($choice) {
            "1" {
                # Confirm before resetting password
                $Confirm = Read-Host "Do you want to reset the password for $($User.DisplayName)? (Y/N)"

                if ($Confirm -match "^[Yy]$") {
            
                    # Define new password
                    $NewPassword = ConvertTo-SecureString "Inthistogether1" -AsPlainText -Force

                    # Reset the password
                    Set-ADAccountPassword -Identity $UserName -Server $dc -NewPassword $NewPassword -Reset

                    # Force the user to change the password at next login
                    Set-ADUser -Identity $UserName -Server $dc -ChangePasswordAtLogon $true

                    # unlock account
                    Unlock-ADAccount -Identity $UserName -Server $dc

                    # Confirm action
                    Write-Host "Password for $($User.DisplayName) has been reset successfully." -ForegroundColor Green

                } else {
                    # pw reset cancelled
                    Write-Host "Password reset cancelled." -ForegroundColor Red
                }
            }
            "2" {
                # confirm before unlocking account
                Write-Host "You selected: Unlock User Account"
                $Confirm = Read-Host "Do you want to UNLOCK the account for $($User.DisplayName)? (Y/N)"
                
                if ($Confirm -match "^[Yy]$") {
                    
                    # unlock account
                    Unlock-ADAccount -Identity $UserName -Server $dc

                    # Confirm action
                    Write-Host "Account for $($User.DisplayName) has been unlocked successfully." -ForegroundColor Green
                    Start-Sleep -Seconds 2

                } else {
                    # pw reset cancelled
                    Write-Host "Account unlock cancelled." -ForegroundColor Red
                }
            }
            "3" {
                #confirm before setting pw change at next login
                $Confirm = Read-Host "Do you want to require password change at next login for account $($User.DisplayName)? (Y/N)"

                if ($Confirm -match "^[Yy]$") {
                    
                    # set account to change pw at next logon
                    Set-ADUser -Identity $UserName -Server $dc -ChangePasswordAtLogon $true

                    # Confirm action
                    Write-Host "User $($User.DisplayName) must change password at next logon." -ForegroundColor Green

                } else {
                    # pw reset cancelled
                    Write-Host "Password change at next login cancelled." -ForegroundColor Red
                }
                
            }
            "4" {
                Write-Host "Refreshing Account info" -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
            "5" {
                Write-Host "Action canceled, choose another user" -ForegroundColor Yellow
                $UserName = $null
            }
            "0" {
                Write-Host "Exiting script and closing PowerShell..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                exit  # Completely closes the PowerShell window
            }
            default {
                Write-Host "Invalid selection, please try again." -ForegroundColor Red
            }
        }

    # user not found
    } else {
        Write-Host "Error: User user selection invalid or not found in Active Directory." -ForegroundColor Red
        $UserName = $null
    }
}