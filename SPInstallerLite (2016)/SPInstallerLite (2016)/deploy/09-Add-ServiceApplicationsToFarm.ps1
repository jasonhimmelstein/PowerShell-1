 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform,
	[Parameter(Mandatory=$True, HelpMessage="You must specify where the xml config file is. Recommend copying to the root of a local or mapped drive.")]
    [string]$xmlfilelocation
    )
# this script enables the remaining required service applications. simples.
# as we are doing things for learning purposes, this script is slightly unusual!
# follow the comments to make sense of things :)

# let's clean the error variable as we are not starting a fresh session
$Error.Clear()

# setup the parameter file
$parameterfile = "$xmlfilelocation\spconfig-"+$Platform+".xml"

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
	[xml]$configdata = Get-Content $parameterfile -ErrorAction Stop
}
Catch {
	Write-Warning "There is no parameter file called $parameterfile!"
	Break
}

# setup the variables root from the parameter file
$DatabaseServerName = $configdata.farm.serviceapplications.coreconfig.databaseserver
$AppPoolName = $configdata.farm.serviceapplications.coreconfig.apppool

# grab the service application variables
# mms
$metadatasaname = $configdata.farm.serviceapplications.mmsserviceapp.name
$databasename = $configdata.farm.serviceapplications.mmsserviceapp.database

# bcs
$bcsSAName = $configdata.farm.serviceapplications.bcsserviceapp.name
$bcsDBName = $configdata.farm.serviceapplications.bcsserviceapp.database

# secure store
$secureStoreSAName = $configdata.farm.serviceapplications.secserviceapp.name
$securestoreDBName = $configdata.farm.serviceapplications.secserviceapp.database

# usage
$usageSAName = $configdata.farm.serviceapplications.useserviceapp.name
$usageDBName = $configdata.farm.serviceapplications.useserviceapp.database

# user profile
$userProfileSAName = $configdata.farm.serviceapplications.upsserviceapp.name
$upsProfileDBName = $configdata.farm.serviceapplications.upsserviceapp.profiledatabase
$upsSocialDBName = $configdata.farm.serviceapplications.upsserviceapp.socialdatabase
$upsSyncDBName = $configdata.farm.serviceapplications.upsserviceapp.syncdatabase

# web analytics
$WebAnalyticsSAName = $configdata.farm.serviceapplications.anaserviceapp.name
$webanalyticsStagingDBName = $configdata.farm.serviceapplications.anaserviceapp.stagedatabase
$webanalyticsReportDBName = $configdata.farm.serviceapplications.anaserviceapp.reportdatabase

#state
$stateSAName = $configdata.farm.serviceapplications.staserviceapp.name
$stateserviceDBName = $configdata.farm.serviceapplications.staserviceapp.database

#ENDREGION

#REGION Function Declaration
# in this region we are showing the declaration of functions that will be called later in the script.
# these examples are very simple as it is not necessary to pass parameters to the functions due to how they are called, 
# most functions would accept parameterised input of some type under normal cirumstances.
# In these examples we are showing how to correctly construct the beginning of a function to include information
# about the funtion that is useful to the reader and that can be invoked from the command line such as a description, examples or notes.
# Nice.

# bcs
Function Start-SPBCSServiceApplication {
	<#
	   .Synopsis
	    This function calls the creation of the BCS Service Application
	   .Description
	    This function calls the creation of the BCS Service Application within a SharePoint 2010
		farm.  
		This function has only been tested with SharePoint 2010.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Start-SPBCSServiceApplication
	   .Notes
	    NAME:  Start-SPBCSServiceApplication
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	Write-Host "INFO: Creating BCS Service and Proxy..." -NoNewline -ForegroundColor Yellow
	# Here we are introducing the errorvariable variable.
	# A friendly error string is placed into this variable ONLY if an error occurs.  
	# we can then test for this as a way of handling errors.
	# Clunky but effective!
	New-SPBusinessDataCatalogServiceApplication -Name $bcsSAName -ApplicationPool $AppPoolName -DatabaseServer $databaseServerName -DatabaseName $bcsDBName -ErrorVariable bcssa  -ErrorAction SilentlyContinue | Out-Null
	if ($bcssa) {
		Write-Host
		Write-Warning "An error occurred during BCS SA creation! The error was: $bcssa"
		Write-Warning "SA NOT created!"
	}
	if (!$bcssa) {
		Write-Host "Done!" -BackgroundColor DarkGreen
	}
	Write-Host
}

# mms
Function Start-SPMMSServiceApplication {
	<#
	   .Synopsis
	    This function calls the creation of the MMS Service Application
	   .Description
	    This function calls the creation of the MMS Service Application within a SharePoint 2010
		farm.  
		This function has only been tested with SharePoint 2010.
		This function will only run from an elevated PowerShell session and requires the running user to
		have permission to the SharePoint configuration database.
	   .Example
	   	Start-SPMMSServiceApplication
	   .Notes
	    NAME:  Start-SPMMSServiceApplication
	    AUTHOR: Seb Matthews @sebmatthews #bigseb
	    DATE: September 2015
	   .Link
	    http://sebmatthews.net
	#>
	Write-Host "INFO: Creating Metadata Service and Proxy..." -NoNewline -ForegroundColor Yellow
	# Here we are introducing the errorvariable variable.
	# A friendly error string is placed into this variable ONLY if an error occurs.  
	# we can then test for this as a way of handling errors.
	# Clunky but effective!
	New-SPMetadataServiceApplication -Name $metadatasaname -ApplicationPool $apppoolname -DatabaseServer $databaseservername -DatabaseName $databasename -errorvariable mmssa -ErrorAction SilentlyContinue | Out-Null
	New-SPMetadataServiceApplicationProxy -Name "$metadatasaname Proxy" -DefaultProxyGroup -ServiceApplication $metadatasaname -ErrorVariable mmssap -ErrorAction SilentlyContinue | Out-Null
	if ($mmssa) {
		Write-Host
		Write-Warning "An error occurred during MMS SA creation! The error was: $mmssa"
		Write-Warning "SA NOT created!"
	}
	elseif ($mmssap) {
		Write-Host
		Write-Warning "An error occurred during MMS SA Proxy creation! The error was: $mmssap"
		Write-Warning "SA Proxy NOT created!"
	}
	if ((!$mmssa) -and (!$mmssap)) {
		Write-Host "Done!" -BackgroundColor DarkGreen
	}
	Write-Host
}

#ENDREGION

# create the service applications
Write-Host
# bcs
Start-SPBCSServiceApplication
# mms
Start-SPMMSServiceApplication

# now then happy reader - i've left the rest of these for you to functionalise yourself 
# isn't that nice of me?  i'm thinking of your education!

# secure store
Write-Host "INFO: Creating Secure Store Service and Proxy..." -NoNewline -ForegroundColor Yellow
New-SPSecureStoreServiceapplication -Name $secureStoreSAName -Sharing:$false -DatabaseServer $databaseServerName -DatabaseName $securestoreDBName -ApplicationPool $AppPoolName -auditingEnabled:$true -auditlogmaxsize 30 | New-SPSecureStoreServiceApplicationProxy -name "$secureStoreSAName Proxy" -DefaultProxygroup | Out-Null
Write-Host "Done!" -BackgroundColor DarkGreen
Write-Host ""
# usage
Write-Host "INFO: Creating Usage Service and Proxy..." -NoNewline -ForegroundColor Yellow
$serviceInstance = Get-SPUsageService
New-SPUsageApplication -Name $usageSAName -DatabaseServer $databaseServerName -DatabaseName $usageDBName -UsageService $serviceInstance | Out-Null
Write-Host "Done!" -BackgroundColor DarkGreen
Write-Host ""
## user profile
Write-Host "INFO: Creating User Profile Service and Proxy..." -NoNewline -ForegroundColor Yellow
$userProfileService = New-SPProfileServiceApplication -Name $userProfileSAName -ApplicationPool $AppPoolName -ProfileDBServer $databaseServerName -ProfileDBName $upsProfileDBName -SocialDBServer $databaseServerName -SocialDBName $upsSocialDBName -ProfileSyncDBServer $databaseServerName -ProfileSyncDBName $upsSyncDBName
New-SPProfileServiceApplicationProxy -Name "$userProfileSAName Proxy" -ServiceApplication $userProfileService -DefaultProxyGroup | Out-Null
Write-Host "Done!" -BackgroundColor DarkGreen
Write-Host ""
# state
Write-Host "INFO: Creating State Service and Proxy..." -NoNewline -ForegroundColor Yellow
$stateserviceappname = New-SPStateServiceApplication -Name $stateSAName
New-SPStateServiceDatabase -databaseserver $DatabaseServerName -Name $stateserviceDBName -ServiceApplication $stateSAName | Out-Null
New-SPStateServiceApplicationProxy -Name ”$stateSAName Proxy” -ServiceApplication $stateSAName -DefaultProxyGroup | Out-Null
Write-Host "Done!" -BackgroundColor DarkGreen
Write-Host ""

# just to be different, we are reporting success/failure and dumping the output file in a slightly different way
if (!$error) {
	Write-Host "SUCCESS: Service applications now created!" -BackgroundColor DarkGreen
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' completed'.txt
}
if ($Error) {
	Write-Warning 'Some service applications may not have provisioned correctly, please review!'
	start-process "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\BIN\psconfigui.exe" -argumentlist "-cmd showcentraladmin"
	Out-File $env:USERPROFILE\desktop\$(($MyInvocation).mycommand.name)' failed'.txt
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