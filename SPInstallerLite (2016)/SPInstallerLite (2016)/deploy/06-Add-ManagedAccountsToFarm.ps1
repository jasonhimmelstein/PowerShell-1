 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform,
	[Parameter(Mandatory=$True, HelpMessage="You must specify where the xml config file is. Recommend copying to the root of a local or mapped drive.")]
    [string]$xmlfilelocation
    )

# This script adds the managed accounts required in the farm. simples.

# let's clean the error variable as we are not starting a fresh session
$Error.Clear()

# setup the parameter file
$parameterfile = "$xmlfilelocation\spconfig-"+$Platform+".xml"

# below we are using regions to show the technique. makes the script foldable in an ISE and easier to read
#REGION load snapins and assemblies
# check for the sharepoint snap-in. this is from Ed Wilson.
$snapinsToCheck = @("Microsoft.SharePoint.PowerShell") #you can add more snapins to this array to load more
$currentSnapins = Get-PSSnapin
$snapinsToCheck | ForEach-Object `
    {$snapin = $_;
        if(($CurrentSnapins | Where-Object {$_.Name -eq "$snapin"}) -eq $null)
        {
            Write-Host "$snapin snapin not found, loading it"
            Add-PSSnapin $snapin
            Write-Host "$snapin snapin loaded"
        }
    }
#ENDREGION

#REGION variables
# get the variables from the parameter file
Try {
	# here we are turning a non-terminating error into a terminating error if the file does not exist, this is so we can catch it
	[xml]$managedaccountstoadd = Get-Content $parameterfile -ErrorAction Stop
}
Catch {
	Write-Warning "There is no parameter file called $parameterfile!"
	Break
}
#ENDREGION

# Get the members of the local Administrators group
$AdminGroup = ([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group")
$LocalAdmins = $AdminGroup.psbase.invoke("Members") | ForEach-Object {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)}
foreach ($managedaccounttoadd in $managedaccountstoadd.farm.mgdaccounts.account) {
	$username = $managedaccounttoadd.Name
	$password = $managedaccounttoadd.Password
	$password = ConvertTo-SecureString "$password" -AsPlaintext -Force 
	Write-Host
	Write-Host "INFO: Adding managed account $username..." -ForegroundColor Yellow
	Try {
		Write-Host "INFO: Creating local profile for $username..." -NoNewline -ForegroundColor Yellow
		$credAccount = New-Object System.Management.Automation.PsCredential $username,$password
		$ManagedAccountDomain,$ManagedAccountUser = $username -Split "\\"
		# Add managed account to local admins (very) temporarily so it can log in and create its profile
		If (!($LocalAdmins -contains $ManagedAccountUser)) {
			([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Add("WinNT://$ManagedAccountDomain/$ManagedAccountUser")
			Write-Host "Done!" -BackgroundColor DarkGreen
		}
		Else {
			Write-Host ""
			Write-Host "INFO: $username is already a local admin, no action taken!" -ForegroundColor Yellow
			$AlreadyAdmin = $true
		}
		# Spawn a command window using the managed account's credentials, create the profile, and exit immediately
		Start-Process -WorkingDirectory "$env:SYSTEMROOT\System32\" -FilePath "cmd.exe" -ArgumentList "/C" -LoadUserProfile -NoNewWindow -Credential $credAccount
		# Remove managed account from local admins unless it was already there
		If (-not $AlreadyAdmin) {([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Remove("WinNT://$ManagedAccountDomain/$ManagedAccountUser")}
	}
	Catch {
		$_
		Write-Host "."
		Write-Warning "Could not create local user profile for $username!"
		break
	}
	$ManagedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $username}
	If ($ManagedAccount -eq $NULL) { 
		Write-Host "INFO: Registering managed account $username..." -NoNewline -ForegroundColor Yellow
        $credAccount = New-Object System.Management.Automation.PsCredential $username,$password
		New-SPManagedAccount -Credential $credAccount | Out-Null
		If (-not $?) { Throw "ERROR: Failed to create managed account $username!" }
		Write-Host "Done!" -BackgroundColor DarkGreen
	}
	Else {
	    Write-Host "INFO: Managed account $username already exists, no action taken!" -ForegroundColor Yellow
	}
}
if (!$Error) {
	Write-Host
	Write-Host "COMPLETE: Done Adding Managed Accounts!" -BackgroundColor DarkGreen
	}
else {
	Write-Host
	Write-Host "ERROR: Error Adding Managed Accounts!" -BackgroundColor red
	Write-Host "The error is: " -NoNewline
	Write-Host $Error
	}

# here we dump a file to the desktop to let us know if the process completed or threw an error
if (!$Error) {
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' completed'.txt
}
else {
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' failed'.txt
}

#    The PowerShell Tutorial for SharePoint 2016
#    Copyright (C) 2015 Seb Matthews
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.