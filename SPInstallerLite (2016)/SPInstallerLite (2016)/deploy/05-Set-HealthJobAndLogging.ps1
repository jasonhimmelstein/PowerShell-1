 Param
	(
	[Parameter(Mandatory=$True, HelpMessage="You must provide a platform suffix so the script can find the paramter file!")]
	[string]$Platform,
	[Parameter(Mandatory=$True, HelpMessage="You must specify where the xml config file is. Recommend copying to the root of a local or mapped drive.")]
    [string]$xmlfilelocation
    )

# this script disables the health jobs that are not needed in a demo environment and setsup logging. simples.

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
	[xml]$jobstodisable = Get-Content $parameterfile -ErrorAction Stop
}
Catch {
	Write-Warning "There is no parameter file called $parameterfile!"
	Break
}

<#
here we are using a comment block to show the technique. fun, fun, fun!
everything between the <# and #`> (ignore the backtick its there as an escape character) will be commented as a block
set logging variables based on the parameter file
passing an environment variable into another variable is not stricly needed, its just to make the script more readable!
#>
# below we are showing how using dot notation PowerShell can follow the structure of the XML object
# it is not necessary but a nice example
# setup the root
[xml]$configdata = Get-Content $parameterfile
$genconfig = $configdata.farm.generalconfig
# grab the attributes and assign them to variables
$daystokeeplogs = $genconfig.logsettings.daystokeeplogs
$loglocation = $genconfig.logsettings.loglocation
$logspaceondisk = $genconfig.logsettings.logspaceondisk
$limitlogdisksize = $genconfig.logsettings.limitlogsize
#ENDREGION

# from here we actually do the work of the script
Write-Host ''
foreach ($jobtodisable in $jobstodisable.farm.healthjobs.jobname) {
	Write-Host "INFO: Disabling $jobtodisable rule..." -NoNewline -ForegroundColor Yellow
	Disable-SPHealthAnalysisRule -Identity $jobtodisable -Confirm:$false
	Write-Host "Done!" -BackgroundColor DarkGreen
	# we have done a lot of error handling for you - why don't you add your own?
}
Write-Host ''
Write-Host "SUCCESS: All specified jobs disabled!" -BackgroundColor DarkGreen

# udate diagnostic logging
Write-Host ''
Write-Host "INFO: Setting ULS logging parameters..." -NoNewline -ForegroundColor Yellow

# update diagnostic logging
<#
here we use a technique to get the object and then set the properties of the object using 
standard = (equals) notation.
once the properties are set, they are persisted by passing them back to the Set cmdlet
this is possible with many Set cmdlets and is a neat way of using the native functionality 
rather than having to use methods such as deploy.
#>
$ulsconfig = Get-SPDiagnosticConfig
$ulsconfig.daystokeeplogs = $daystokeeplogs
$ulsconfig.loglocation = $loglocation
$ulsconfig.logdiskspaceusagegb = $logspaceondisk
$ulsconfig.logmaxdiskspaceusageenabled = $true
$ulsconfig | Set-SPDiagnosticConfig
Write-Host "Done!" -BackgroundColor DarkGreen
Write-Host ''

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