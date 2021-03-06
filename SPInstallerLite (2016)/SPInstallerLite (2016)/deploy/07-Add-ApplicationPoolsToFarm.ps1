 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform,
	[Parameter(Mandatory=$True)]
    [string]$xmlfilelocation
    )

# this script creates the required application pools. simples.
# new thinking (2013/2016) suggests that Search should have two application pools (admin and query)
# this can be controlled from the XML config file if you choose to take this path

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
	[xml]$apppoolstocreate = Get-Content $parameterfile	-ErrorAction Stop
}
Catch {
	Write-Warning "There is no parameter file called $parameterfile!"
	Break
}
#ENDREGION

# let's loop through the required application pools in the XML config file. Whoop!
foreach ($apppool in $apppoolstocreate.farm.applicationpools.applicationpool) {
	$applicationpoolname = $apppool.apppoolname
	$applicationpoolserviceaccount = $apppool.apppoolusername
	# check managed account
	$ManagedAccountCheck = Get-SPManagedAccount | Where-Object {$_.UserName -eq $applicationpoolserviceaccount}
   	If ($ManagedAccountCheck -eq $NULL) { Throw "ERROR: Managed Account $applicationpoolserviceaccount not found" }
	# check application pool
   	$ApplicationPoolCheck = Get-SPServiceApplicationPool $applicationpoolname -ea SilentlyContinue
   	If ($ApplicationPoolCheck -eq $null) {
    	Write-Host ""
		Write-Host "INFO: Creating Application Pool named $applicationpoolname..." -NoNewline -ForegroundColor Yellow
		$CreateApplicationPool = New-SPServiceApplicationPool -Name $applicationpoolname -account $applicationpoolserviceaccount
       	If (-not $?) { 
			Throw "ERROR: Failed to create the application pool $applicationpoolname" 
		}
		Write-Host "Done!" -BackgroundColor DarkGreen
		$Error.Clear()
   	}
	else {
		Write-Host ""
		Write-Host "INFO: Application Pool $applicationpoolname already exists, no action taken!" -ForegroundColor Yellow
	}
}
if (!$Error) {
	# hey folks using these scripts to learn - can you think of a better way to do the following?
	# i know i can!
	Write-Host
	Write-Host "SUCCESS: Application Pools Created!" -BackgroundColor DarkGreen
	}
else {
	Write-Host "ERROR: Error with Application Pool creation!" -BackgroundColor Red
	Write-Host $Error
	# this next line is here for unified script purposes only!
	Break
	}
Write-Host

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