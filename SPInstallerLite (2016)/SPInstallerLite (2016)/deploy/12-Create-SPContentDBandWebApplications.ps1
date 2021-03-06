 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform,
	[Parameter(Mandatory=$True, HelpMessage="You must specify where the xml config file is. Recommend copying to the root of a local or mapped drive.")]
    [string]$xmlfilelocation
    )

#REGION Kick Ass Functions

Function Write-Line {
	# an easier way to write a blank line to the console to help format script output
	Write-Host ''
	}
 
Function Test-SnapIns {
	<#
	   .Synopsis
	    This function tests for and loads (if needed) specified Snap Ins
	   .Description
	    This function tests for and loads (if needed) specified Snap Ins.  Simply add snap in names to the $snapinstocheck array
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Test-SnapIns
	   .Notes
	    NAME: Test-SnapIns
	    AUTHOR: Seb Matthews @sebmatthews #bigseb - This script is based on a script by Ed Wilson
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	$snapinsToCheck = @("Microsoft.SharePoint.PowerShell") # list more as required
	$currentSnapins = Get-PSSnapin
	$snapinsToCheck | ForEach-Object {
		$snapin = $_
        if(($CurrentSnapins | Where-Object {$_.Name -eq "$snapin"}) -eq $null) {
	            Write-Line
				Write-Host "$snapin snapin not found, loading it"
	            Add-PSSnapin $snapin
	            Write-Host "$snapin snapin loaded"
	        }
	    }
	}

Function Write-PowerShellScriptReportingEvent {
	<#
	   .Synopsis
	    This function esta
	   .Description
	    This function esta within a SharePoint 2016 farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	name
	   .Notes
	    NAME: name
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	Param (
		[Parameter(Mandatory=$False)]
		[string]$eventmessage = "$error",
		[string]$eventsource = "SP PS Script $scriptid",
		[string]$eventtype = 'Information',
		[string]$eventid = '3333'
    )
	If (!(Test-Path HKLM:\SYSTEM\CurrentControlSet\Services\Eventlog\Application\$eventsource)) {
	[System.Diagnostics.EventLog]::CreateEventSource($eventsource,”Application”)
    }
    Write-EventLog -logname 'Application' -source $eventsource -eventID $eventid -entrytype $eventtype -message $eventmessage
}

Function Remove-DatabaseWithoutDBA {
	<#
	   .Synopsis
	    This function esta
	   .Description
	    This function esta within a SharePoint 2016 farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	name
	   .Notes
	    NAME: name
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	# this function will remove a sharepoint content db and its sql server database according to the parameter file passed. simples.
	
	# let's set variables we need
	$databasedeletelist = @()
	Write-Host
	# loop through all the required databases in the parameter file to locate them all
	# this is is necessary because if we delete without compiling a list first we get an enumeration error due to the array object being changed
	foreach ($databasename in $configdata.farm.contentdatabaseconfig.contentdatabases.contentdb) {
		foreach ($database in $dbserver.Databases) {
			if ($database.name -eq $databasename.name) {
				$databasedeletelist += New-Object PSObject -Property @{DbName = $databasename.name}
			}
		}
	}
	if ($databasedeletelist) {
		foreach ($databasetodelete in $databasedeletelist)	{		
			# it is actually easier to issue a "Remove-SpContentDatabase -Confirm:$false -Force" but this script is showing SQL operations!
			Write-Host "INFO: Removing database $($databasetodelete.DbName)..." -NoNewline 
			Get-SPContentDatabase $databasetodelete.DbName | Dismount-SPContentDatabase -Confirm:$false
			$deletedatabase = New-Object Microsoft.SqlServer.Management.Smo.Database ($dbServer, $databasetodelete.DbName)
			$dbServer.Killallprocesses($deletedatabase.Name)
			$dbServer.KillDatabase($deletedatabase.Name)
			Write-Host 'Done!' -BackgroundColor DarkGreen -ForegroundColor White
		}
		Write-Line
		Write-Host 'SUCCESS: All existing content databases removed!' -BackgroundColor DarkGreen -ForegroundColor White
	}
	Else {
		Write-Line
		Write-Host 'INFO: No databases to remove!' 
	}
}

Function New-DatabaseWithoutDBA {
	<#
	   .Synopsis
	    This function esta
	   .Description
	    This function esta within a SharePoint 2016 farm.  
		This function has only been tested with SharePoint 2016.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	name
	   .Notes
	    NAME: name
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	# this function will create a sql server database according to the parameter file passed. simples.

	# let's set variables we need
	$farmaccount = $configdata.farm.contentdatabaseconfig.farmaccount

	# loop through all the required databases in the parameter file to create them all
	foreach ($databasename in $configdata.farm.contentdatabaseconfig.contentdatabases.contentdb) {
			# reset the loop escape as we are nesting loops
			$databaseexists = $false
			
			# let's check if the database already exists
			foreach ($database in $dbserver.Databases) {
					if ($database.name -eq $databasename.name) {
						$databaseexists = $true
						Write-Host "WARNING: Database $($databasename.name) already exists!" -ForegroundColor white -BackgroundColor Red
						Write-PowershellScriptReportingEvent -eventmessage "Database $($databasename.name) already exists!"
						Write-Host "WARNING: Database already exists, operation stopped!" -ForegroundColor white -BackgroundColor Red
						Write-Line
						Write-PowershellScriptReportingEvent -eventmessage "Script $scriptid Stopped."
						Break;
					}
				}
			
			# if database(s) don't already exist, then carry on
			if ($databaseexists -ne $true) {
				# let's create the database
				Write-Host "INFO: Creating database $($databasename.name)..." -NoNewline 
				$createdatabase = New-Object Microsoft.SqlServer.Management.Smo.Database ($dbServer, $databasename.name)
				$createdatabase.Create()
				$createdatabase.Set_Collation("Latin1_General_CI_AS_KS_WS")
				$createdatabase.Alter()
				Write-Host 'Done!' -BackgroundColor DarkGreen -ForegroundColor White

				# let's alter the database files to meet our size and growth needs
				$filegroup = $createdatabase.FileGroups
				foreach ($group in $filegroup) 	{ 
					foreach ($dbfile in $group.Files) {
						Write-Line
						write-host 'INFO: Current file name = ' $dbfile.name 
						write-host 'INFO: Current file size = ' $dbfile.Size 
						write-host 'INFO: Current file growth rate = ' $dbfile.Growth 
						write-host 'INFO: Current file growth type = ' $dbfile.GrowthType 
						Write-Host 'INFO: Updating files settings...' -NoNewline 
						$dbfile.Size = $databasename.filesize
						$dbfile.Growth = $databasename.filegrowth
						$dbfile.GrowthType = $databasename.filegrowthtype
						# For GrowthType valid values are KB, Percent, None
						# For MaxSize Set to unlimited growth with -1 or value in KB
						$dbfile.Alter()
						Write-Host 'Done!' -BackgroundColor DarkGreen -ForegroundColor White
					}
				}
				foreach ($logfile in $createdatabase.LogFiles) 	{
					Write-Line
					write-host 'INFO: Current logfile name = ' $logfile.name 
					write-host 'INFO: Current logfile size = ' $logfile.Size 
					write-host 'INFO: Current logfile growth rate = ' $logfile.Growth 
					write-host 'INFO: Current logfile growth type = ' $logfile.GrowthType 
					Write-Host 'INFO: Updating logfile settings...' -NoNewline 
					$logfile.Size = $databasename.logsize
					$logfile.Growth = $databasename.loggrowth
					$logfile.GrowthType = $databasename.loggrowthtype
					$logfile.Alter()
					Write-Host 'Done!' -BackgroundColor DarkGreen -ForegroundColor White
				}
				
				# now we need to add the farm user to the database so sharepoint can use the content db
				
				# let's check the login is valid on the instance
				$checklogin = $dbServer.Logins[$farmaccount]
				
				# if the login does not exist, add it to the SQL instance and grant dbcreator and securityadmin permissions
				if ($checklogin -eq $null) 	{
						Write-Line
						Write-Host "WARNING: No SQL login on instance $dbservername for user $farmaccount!" -ForegroundColor Red
						Write-Line
						Write-Host "INFO: Creating SQL login for $farmaccount on $dbservername..." -NoNewline 
						$newloginname = $farmaccount
						$newlogin = New-Object microsoft.SqlServer.Management.Smo.Login ($dbServer, $newloginname)
						$newlogin.LoginType = 'WindowsUser'
						$newlogin.UserData = $newloginname
						$newlogin.Create()
						$newlogin.AddToRole('dbcreator')
						$newlogin.AddToRole('securityadmin')
						$newlogin.Alter()
						Write-Host 'Done!' -BackgroundColor Darkgreen -ForegroundColor White
					}
				
				# let's check the user does not already exist
				Write-Line
				Write-Host "INFO: Adding SharePoint farm account $farmaccount to database logins with db_owner permissions..." -NoNewline 
				$validuser = $createdatabase.Users[$farmaccount]
				
				# if the user does not exist, add it and grant db_owner permissions
				if ($validuser -eq $null) {
						$newuser = New-Object Microsoft.SqlServer.Management.Smo.User ($createdatabase, $farmaccount)
						$newuser.Login = $farmaccount
						$newuser.Create()
						$createdatabase.Roles['db_owner'].AddMember($farmaccount)
					}
				Write-Host 'Done!' -BackgroundColor DarkGreen -ForegroundColor White
				Write-Line
			}
		}
	if ($databaseexists -eq $true) {
		Write-Line
		Write-Host 'INFO: Script stopped!' 
		Break;
		}
	Write-Host 'SUCCESS: All SQL operations complete!' -BackgroundColor DarkGreen -ForegroundColor White
}

#ENDREGION

# Do the work...

# make a note that we have started
$scriptid = ($MyInvocation).mycommand.name # this is needed as it is used by reporting event function
Write-PowershellScriptReportingEvent -eventmessage "Script $scriptid Started."

# let's clean the error variable as we are not starting a fresh session
$Error.Clear()

# setup the parameter file
$parameterfile = "$xmlfilelocation\spconfig-"+$Platform+".xml"

[xml]$configdata = Get-Content $parameterfile

Write-Line
Write-Host 'INFO: Starting database operations...' 

# load assemblies and set variables
Test-SnapIns
Start-SPAssignment -Global
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") >$null
$dbservername = $configdata.farm.contentdatabaseconfig.instance
$dbServer = new-object Microsoft.SqlServer.Management.Smo.Server ($dbservername)

# remove existing databases
# we're only doing this because we're within a test/demo environment and we want to ensure that things are clean
# before we do new things.
Write-Line
Write-Host 'INFO: Removing existing databases...' 
Remove-DatabaseWithoutDBA

# create the databases from the config file
Write-Line
Write-Host 'INFO: Adding SQL databases...' 
Write-Line
New-DatabaseWithoutDBA

# create the web apps
# if you are testing and doing this repeatedly, you can remove the existing wep app with:
# 	$allwebapps = Get-SPWebApplication
# 	foreach ($webapplication in $allwebapps) {
# 		Remove-SPWebApplication -Identity $webapplication.Name -DeleteIISSite -RemoveContentDatabases -Confirm:$false
#	}
# here we are doing something i love with PowerShell - SPLATTING
# yep, you read it correctly, splatting.
# in essence we are loading values (key value pairs so 'name = value' for those non-dev types!)
# into a hash table that can then be passed lock stock into a cmdlet.  splatting lets us separate the
# function from the variables (parameters) which can be useful in many circumstances
# this is frikken handy and it has the word splat in it
# Mojo!
$Error.Clear()
Write-Line
Write-Host 'INFO: Adding Web Applications...' 
# loop through all of the web apps to create in the XML file
# toptip - we're testing for application pool existence as the New-SPWebApplication cmdlet takes different input based on 
# app pool status.
# perhaps you could function this up for practice?
# avanti!
ForEach ($webapplication in $configdata.farm.webapplications.webapp) {
	$testforapppool = [Microsoft.SharePoint.Administration.SPWebService]::ContentService.ApplicationPools | ?{$_.Name -eq $webapplication.apppool}
	If ($testforapppool -eq $null) {
		$splattedhash = @{name = $webapplication.name
					port = $webapplication.port
					url = $webapplication.url
					hostheader = $webapplication.hostheader
					applicationpool = $webapplication.apppool
					applicationpoolaccount = (get-spmanagedaccount $webapplication.apppoolaccount)
					authenticationmethod = $webapplication.authentication
					databasename = $webapplication.database
					databaseserver = $webapplication.databaseserver
					}
	}
	Else {
		$splattedhash = @{name = $webapplication.name
					port = $webapplication.port
					url = $webapplication.url
					hostheader = $webapplication.hostheader
					applicationpool = $webapplication.apppool
					authenticationmethod = $webapplication.authentication
					databasename = $webapplication.database
					databaseserver = $webapplication.databaseserver
					}
	}
	Write-Host
	Write-Host "INFO: Creating webapp $($webapplication.name)..." -NoNewline 
	$createwebapp = New-SPWebApplication @splattedhash
	if (!$error) {
		Write-Host "Done!" -BackgroundColor DarkGreen
		# this variable is set for us to use in the next block
		$setcache = $true
	}
	else {
		Write-Warning "Web application creation failed!"
	}
}

# lets loop thru the webapps and apply the cache superuser and reader update
# you really should function this bad boy up. how else will you learn?
# educate!
if ($setcache) {
	foreach ($webapp in $configdata.farm.webapplications.webapp) {
		$superuser = $configdata.farm.webappcache.superuser
		$superreader = $configdata.farm.webappcache.superreader
		Write-Host ''
		Write-Host "INFO: Updating $($webapp.name)..." -NoNewline 
		$webappidentity = get-spwebapplication -identity $($webapp.url)
		$fullPolicy = $webappidentity.Policies.Add($superUser, $superUser) 
	    $fullPolicy.PolicyRoleBindings.Add($webappidentity.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullControl)) 
	    $readPolicy = $webappidentity.Policies.Add($superReader, $superReader) 
	    $readPolicy.PolicyRoleBindings.Add($webappidentity.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullRead)) 
		$webappidentity.Properties["portalsuperuseraccount"] = $superuser
		$webappidentity.Properties["portalsuperreaderaccount"] = $superreader
		$webappidentity.Update()
		Write-Host "Done!" -BackgroundColor DarkGreen
		Write-Host ''
	}
	if (!$error) {
		Write-Host "Web application cache users have been set!" -BackgroundColor DarkGreen
	}
	else {
		Write-Warning "Web application cache user set failed!"
	}
}

if (!$Error) {
	Write-Host
	Write-Host "SUCCESS: Databases and Web Applications created!" -BackgroundColor DarkGreen
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)'completed'.txt
	}
else {
	Write-Host "ERROR: There was an issue with the database or web app creation, please review!" -BackgroundColor Red
	start-process "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\14\BIN\psconfigui.exe" -argumentlist "-cmd showcentraladmin"
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)'failed'.txt
	}
	Write-Host

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