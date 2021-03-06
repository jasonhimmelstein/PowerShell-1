 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform,
	[Parameter(Mandatory=$True, HelpMessage="You must specify where the xml config file is. Recommend copying to the root of a local or mapped drive.")]
    [string]$xmlfilelocation,
	[Parameter(Mandatory=$False)]
	[switch]$InitDatabase,
	[Parameter(Mandatory=$false)]
	[switch]$rebuild
	)

# this script will setup the initial sharepoint configuration or add a server to the farm. simples.

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

# load sql assembly
# although we have added the SQL tools to the SP install thus making the SQL powershell snapins available
# this method shows the other way that we can load an assembly (binary module or snapin) 
if ($InitDatabase -eq $true) {
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
	}
#ENDREGION

#REGION variables
# get the variables from the parameter file
Try {
	# here we are turning a non-terminating error into a terminating error if the file does not exist, this is so we can catch it
	[xml]$configdata = Get-Content $parameterfile -ErrorAction Stop
}
Catch {
	Write-Warning "There is no parameter file called $parameterfile!"
	Break
}

# passing an environment variable into another variable is not stricly needed, its just to make the script more readable!
$ServerName = $env:COMPUTERNAME
$serverconfig = $configdata.farm.servers.$ServerName.serverconfig
$dbserver = $serverconfig.dbserver
$configdb = $serverconfig.configdb
$admincontentdb = $serverconfig.contentdb
$farmaccount = $serverconfig.farmaccount
$farmpassword = $serverconfig.farmpassword
$farmpassphrase = $serverconfig.farmpassphrase
$caport = $serverconfig.caport
$caauthprovider = $serverconfig.authprov
$securefarmpassword = ConvertTo-SecureString $farmpassword -AsPlainText -Force
$farmcredentials = New-Object system.Management.Automation.PSCredential ($farmaccount,$securefarmpassword)
#ENDREGION

#REGION initialise SQL database

# delete the existing databases but first run some tests
if ($InitDatabase) {
	Try {
		Get-SPFarm | Out-Null
	}
	Catch {
		$nofarm = $true
	}
	If ($nofarm) {	
		Write-Host ''
		Write-Warning "Initialise database switch is set, script will remove existing config database of the same name..."
		Write-Host ''
		# here we are instantiating the SMO object for the database instance
		$dbserverobject = New-Object Microsoft.SqlServer.Management.Smo.Server ($dbserver)
		# the following is a very dirty way using SMO to remove a database!
		write-host "INFO: Deleting database $configdb..." -ForegroundColor Yellow -NoNewline
		# no prizes for guessing what happens below!
		$dbserverobject.KillAllProcesses($configdb)
		$dbserverobject.Databases[$configdb].Drop()
		Write-Host "Done!" -BackgroundColor DarkGreen
		write-host "INFO: Deleting database $admincontentdb..." -ForegroundColor Yellow -NoNewline
		$dbserverobject.KillAllProcesses($admincontentdb)
		$dbserverobject.Databases[$admincontentdb].Drop()
		Write-Host "Done!" -BackgroundColor DarkGreen
		$dbserverobject = $false # crappy way to dispose of the object
		}
	else {
		Write-Host ''
		Write-Warning "This server is attached to a farm and should be detached using Disconnect-SPConfigurationDatabase prior to running script. Exiting!"
		break
	}
}
else {
	Write-Host ''
	Write-Host "INFO: Initialise database switch not set, script will fail if the database exists and contains data!" -ForegroundColor Yellow
}
#ENDREGION



# decide what to do based on input from parameter file
if ($serverconfig.createorconnect -eq "CREATE")	{
	# this block will create a new farm
	Write-Host ""
	Write-Host "INFO: Parameter file indicates a new farm is to be created." -ForegroundColor Yellow
	Write-Host ""
	if ($rebuild) {
		Write-Host "INFO: Skipping farm checks as this is a re-build." -ForegroundColor Yellow
		Write-Host ''
	}
	else {
		write-host "INFO: Checking for existence of local farm..." -NoNewline -ForegroundColor Yellow
		# note that the test used below will FAIL the machine was previously in a farm and removed in a non-graceful way!
		if ([Microsoft.SharePoint.Administration.SPFarm]::Local -eq $null) {
			Write-Host "No local farm exists!" -BackgroundColor DarkGreen
			Write-Host ""
			# $nolocalfarm = $True # used for testing!
			$Error.Clear()
		}
		else {
			# here we are using Throw simply to demonstrate it's use
			throw "Local farm exists, exiting!"
		}
	}
	# create the databases
	Write-Host "INFO: Creating farm config DB..." -ForegroundColor Yellow
	Write-Host ''
	Try {
		New-SPConfigurationDatabase -DatabaseName $configdb -DatabaseServer $dbserver -AdministrationContentDatabaseName $admincontentdb -Passphrase (ConvertTo-SecureString $farmpassphrase -AsPlainText -Force) -FarmCredentials $farmcredentials -LocalServerRole ($serverconfig.sp2016role) -erroraction STOP
	}
	Catch {
		Write-Host "ERROR: The creation of the configuration database failed!" -ForegroundColor Red
		Write-Warning "Script will be terminated, the cause was: $error"
		Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' failed'.txt
		Break
	}
	Finally {
		if (!$Error) {
			Write-Host "SUCCESS: Database created, continuing initial configuration..." -BackgroundColor DarkGreen
			Write-Host ""
		}
	}	
	Initialize-SPResourceSecurity
	Install-SPService
	Write-Host "INFO: Installing all features..." -ForegroundColor Yellow
	Write-Host ""
	Install-SPFeature -AllExistingFeatures
	
	# create the central admin app
	if ($serverconfig.addca -eq "YES") {
		Write-Host ''
		Write-Host "INFO: Adding Central Admin at url $servername and port $caport..." -ForegroundColor Yellow
		Write-Host ""
		$Error.Clear()
		# this whole try...catch malarkey is here because sometimes during a rebuild the provisioning of the CA webapp fails. this frequently
		# occurs if the server was not previously gracefully detached from a farm
		Try {
			New-SPCentralAdministration -Port $caport -WindowsAuthProvider $caauthprovider -ErrorAction Stop
		}
		Catch {
			$retry = $true
			Write-Warning "New Central Admin failed, retrying!"
			New-SPCentralAdministration -Port $caport -WindowsAuthProvider $caauthprovider -ErrorAction Stop
		}
		Finally {
			if ((!$Error) -and (!$retry)) {
				Write-Host "SUCCESS: Central Admin Created!" -BackgroundColor DarkGreen
			}
			else {
				Write-Warning "Despite retry, CA create failed, exiting script!"
				# the break below has to be removed in PSv3 as return from finally is no longer allowed
				# break
				$gremlins = $true
			}
		}
		If ($gremlins) {
			break
		}
	}
	else {
		Write-Host "INFO: Not adding Central Admin, continuing..." -ForegroundColor Yellow
		Write-Host ""
	}
	Write-Host ''
	Write-Host "INFO: Continuing with help collections and CA content..." -ForegroundColor Yellow
	Write-Host ""
	Install-SPHelpCollection -All
	Install-SPApplicationContent
	$checkfarm = Get-SPFarm -ErrorAction silentlycontinue -errorvariable err
		if ($checkfarm -eq $null -or $err) {
			throw "ERROR: Farm creation may have failed!"
		}
		else {
			Write-Host "SUCCESS: Farm Configured!" -BackgroundColor DarkGreen
			Write-Host ""
		}
	Write-Host "Opening window for you to review status in Central Admin..."
	
	# this is one of the many ways we could open the central admin webpage...
	# the below was updated for 2016
	start-process "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\BIN\psconfigui.exe" -argumentlist "-cmd showcentraladmin"	
}
elseif ($serverconfig.createorconnect -eq "CONNECT") {
	# this block will connect to a farm
	Write-Host ""
	write-host "INFO: Checking for existence of local farm..." -NoNewline -ForegroundColor Yellow
		if ([Microsoft.SharePoint.Administration.SPFarm]::Local -eq $null) {
			Write-Host "Success, server not connected to local farm!" -BackgroundColor DarkGreen
			Write-Host ""
			# $nolocalfarm = $True # used for testing!
			$Error.Clear()
		}
		else {
			Write-Host ""
			Write-Host "ERROR: This server is already connected to a farm!" -BackgroundColor Red
			break
		}
	# connect to the databases
	Write-Host "INFO: Connecting to the $configdb farm..." -ForegroundColor Yellow
	Connect-SPConfigurationDatabase -DatabaseServer $dbserver -DatabaseName $configdb -Passphrase (ConvertTo-SecureString "$farmpassphrase" -AsPlainText -Force) -LocalServerRole ($serverconfig.sp2016role)
	# below shows another method to test whether the connection (or creation) has completed without error without using Try...Catch
	if (!$Error) {
		Write-Host ''
		Write-Host "INFO: Connected to database, continuing initial configuration" -ForegroundColor Yellow
		Initialize-SPResourceSecurity
		Install-SPService
		Write-Host ''
		Write-Host "INFO: Installing all features" -ForegroundColor Yellow
		Write-Host ""
		Install-SPFeature -AllExistingFeatures
	}
	else {
		Write-Host "ERROR: An error occurred connecting to the farm $configdb!" -ForegroundColor Red
		break
	}
	# create the central admin app if required
	
		if ($serverconfig.addca -eq "YES") {
			Write-Host "INFO: Adding Central Admin..." -ForegroundColor Yellow
			New-SPCentralAdministration -Port $caport -WindowsAuthProvider $caauthprovider
			Install-SPHelpCollection -All
			Install-SPApplicationContent
		}
		else {
			Write-Host "INFO: Not adding Central Admin..." -ForegroundColor Yellow
		}
	$checkfarm = Get-SPFarm -ErrorAction silentlycontinue -errorvariable err
		if ($checkfarm -eq $null -or $err) {
			throw "Farm update may have failed!"
		}
		else {
			Write-Host "Farm Updated!"
		}
	Write-Host ''
	# as we have added to the farm, we need to handle the buggy timer service issue caused but adding a server to the farm in powershell
	# this is simply a case of starting the timer server in all the servers in the farm where it is stopped
	Write-Host "INFO: Starting Timer Service on all farm servers where service is stopped..." -ForegroundColor Yellow
	Write-Host ''
	foreach ($farmserver in $configdata.farm.servers.childnodes) {
		If ((Get-Service -ComputerName $farmserver.Name -Name "SPTimerV4" -ErrorAction SilentlyContinue).Status -eq "Stopped") {
			Write-Host "INFO: Starting $((Get-Service SPTimerV4).DisplayName) Service on $($farmserver.Name)..." -NoNewline -ForegroundColor Yellow
			Start-Service -inputobject $(Get-Service -ComputerName $farmserver.Name -Name "SPTimerV4")
			# below we are using the variable $? to test the successful execution of the previous cmdlet, it's a blunt tool but works here
			If (!$?) {
				Throw "Could not start Timer service!"
			}
			Write-Host "Done!" -BackgroundColor DarkGreen
			Write-Host ""
		} 
		else {
			Write-Host
			Write-Host "INFO: Timer Service already started on $($farmserver.Name)..." -ForegroundColor Yellow
		}
	}

	Write-Host "INFO: Farm now configured with the following servers:" -ForegroundColor Yellow
	Get-SPFarm | select Servers
	Write-Host ''
	Write-Host "SUCCESS: Opening window to enable review of SharePoint status in Central Admin." -BackgroundColor DarkGreen
	# the below was updated for 2016
	start-process "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\BIN\psconfigui.exe" -argumentlist "-cmd showcentraladmin"	
}
else {
	Write-Host "ERROR: Nothing to do due to missing configuration parameters in XML file!" -ForegroundColor Red
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