Trace-VstsEnteringInvocation $MyInvocation

$WebAppName = Get-VstsInput -Name "WebAppName" 
$DeployToSlotFlag= Get-VstsInput -Name "DeployToSlotFlag" 
$ResourceGroupName= Get-VstsInput -Name "ResourceGroupName" 
$SlotName= Get-VstsInput -Name "SlotName" 
$WebConfigFile= Get-VstsInput -Name "WebConfigFile" 
$validationResultAction= Get-VstsInput -Name "validationResultAction" 
$Validate = Get-VstsInput -Name "ValidateFlag" -AsBool
$Clean = Get-VstsInput -Name "CleanUp" -AsBool

################# Temporary check till uploading a task which supports buildagent 2 and higher #################
$agentHomeDir = Get-VstsTaskVariable -Name "AGENT_HOMEDIRECTORY"
Write-VstsTaskVerbose "Homedirectory: $agentHomeDir"
[System.IO.DirectoryInfo] $directoryInfo = New-Object IO.DirectoryInfo($agentHomeDir)
Write-VstsTaskVerbose "Current build agent version is: $directoryInfo.Name"
if ($directoryInfo.Name.StartsWith("1"))
{
	$error = ("The version of this BuildAgent is not supported. Current Version: {0}. This task needs at least build agent version 2.105.0" -f $directoryInfo.Name)
	Write-VstsTaskError $error
	throw $error
}
################# End temporary check #################

$validationErrors = New-Object 'System.Collections.Generic.List[string]'

$stickySlot = $null
$stickyAppSettingNames = New-Object 'System.Collections.Generic.List[object]'
$stickyConnectionStringNames = New-Object 'System.Collections.Generic.List[object]'

$WebSite = $null
$settings = @{}
$connectionStringsHashTable = @{}
$vstsVariables = @{}

$appSettingKeys = @{}
$connectionStringNames = @{}

################# Read-WebConfigToPrepareValidation #################
Write-VstsTaskVerbose "Read-WebConfigToPrepareValidation. Validate: $Validate"
if ($Validate)
{
	#Read web.config
	$xml = [xml] (Get-Content $WebConfigFile)
	Write-VstsTaskVerbose $xml.OuterXml

	Write-VstsTaskVerbose "Start reading appsettings"
	foreach($appSetting in $xml.configuration.appSettings.add)
	{
		$appsettingkey = $appSetting.key
		Write-VstsTaskVerbose "Add appsetting $appsettingkey"
		$appSettingKeys[$appSetting.key] = $appSetting.key
	}
				
	Write-VstsTaskVerbose "Start reading connectionstrings"
	foreach($connectionString in $xml.configuration.connectionStrings.add)
	{
		$connectionStringName = $connectionString.Name
		Write-VstsTaskVerbose "Add connectionstring $connectionStringName"
		$connectionStringNames[$connectionString.name] = $connectionString.name
	}
	
		
	Write-VstsTaskVerbose "Finished reading config file"		
}

################# Read-Variables-From-VSTS #################
Write-VstsTaskVerbose "Read-Variables-From-VSTS"
# Get all variables. Loop through each and apply if needed.
$vstsVariables = Get-VstsTaskVariableInfo 
$numbervars = $vstsVariables.Count
Write-VstsTaskVerbose "Found $numbervars variables. Variable Values"

################# Initialize Azure. #################
Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
Initialize-Azure

################# Read-Settings-From-WebApp #################
Write-VstsTaskVerbose "Read-Settings-From-WebApp"

if($SlotName)
{
	Write-VstsTaskVerbose "Reading configuration from website $WebAppName and deploymentslot $SlotName" 
	$WebSite = Get-AzureRmWebAppSlot -Name $WebAppName -Slot $SlotName -ResourceGroupName $ResourceGroupName
}
else
{
	Write-VstsTaskVerbose "Reading configuration from website $WebAppName in resourcegroup $ResourceGroupName" 
	$WebSite = Get-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -ErrorVariable azureServiceError
}
if($azureServiceError){
    $azureServiceError | ForEach-Object { Write-Verbose $_.Exception.ToString() }
}   
if(!$WebSite) 
{
	$error = ("Failed to find WebSite {0}" -f $WebAppName)
	Write-VstsTaskError $error
	throw $error
}

Write-VstsTaskVerbose "Fetch appsettings"
# Get all appsettings and put in Hashtable (because Set-AzureRMWebApp needs that)
if (!$Clean)
{
	ForEach ($kvp in $WebSite.SiteConfig.AppSettings) {
		$settings[$kvp.Name] = $kvp.Value
	}
}
$numberOfSettings = $settings.Count
Write-VstsTaskVerbose "appsettings: $numberOfSettings"
Write-VstsTaskVerbose "Fetch connectionstrings"

# Get all connectionstrings and put it in a Hashtable (because Set-AzureRMWebApp needs that)	
if (!$Clean)
{
	ForEach ($kvp in $WebSite.SiteConfig.ConnectionStrings) {
		$connectionStringsHashTable[$kvp.Name] = @{"Value" = $kvp.ConnectionString.ToString(); "Type" = $kvp.Type.ToString()} #Make sure that Type is a string    
	}
}
$numberOfConnectionStrings = $connectionStringsHashTable.Count
Write-VstsTaskVerbose "connectionstrings: $numberOfConnectionStrings"

################# Read-Sticky-Settings #################
Write-VstsTaskVerbose "Read-Sticky-Settings"
	
$resourceName = $WebAppName + "/slotConfigNames"
$stickySlot = Get-AzureRmResource -ResourceName $resourceName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/sites/config" -ApiVersion "2015-08-01"
	
if (!$Clean)
{
	# Fill with all existing settings
	$stickyAppSettingNames.AddRange($stickySlot.properties.appSettingNames)
	$stickyConnectionStringNames.AddRange($stickySlot.properties.connectionStringNames)
}
Write-VstsTaskVerbose "Finished Read-Sticky-Settings"

$numbervars = $vstsVariables.Count
Write-VstsTaskVerbose "Found $numbervars variables. Variable Values"

if ($vstsVariables -ne $null){
	foreach ($h in @($vstsVariables)) {
		Write-VstsTaskVerbose "Processing vstsvariable: $($h.Name): $($h.Value)"
		
		$originalKey = $h.Name
		$cleanKey = $originalKey.Replace(".sticky", "").Replace("appsetting.", "").Replace("connectionstring.", "")
		$Value = Get-VstsTaskVariable -Name $originalKey
		
		if ($originalKey.StartsWith("appsetting."))
		{	
			############# AddSettingAsAppSetting -originalKey $originalKey -cleanKey $cleanKey -value $Value #################

			if ($originalKey.Contains(".sticky"))
			{
				Write-VstsTaskVerbose "AppSetting $cleanKey added to sticky"
				$stickyAppSettingNames.Add($cleanKey)
			}

			Write-Host "Store appsetting $cleanKey with value $Value"

			$settings[$cleanKey.ToString()] = $Value.ToString();		
		
			if ($Validate -and $appSettingKeys)
			{
				Write-VstsTaskVerbose "Going to validate $cleankey to:"

				$found = $appSettingKeys.Contains($cleanKey);
				if (!$found)
				{
					$validationErrors.Add("Cannot find appSetting [$cleanKey] in web.config. But the key does exist in VSTS as a variable")
				}
				Write-VstsTaskVerbose "Validated"
			}
		}
		elseif ($originalKey.StartsWith("connectionstring."))
		{		
			################# AddSettingAsConnectionString -originalKey $originalKey -cleanKey $cleanKey -value $value #################

			Write-VstsTaskVerbose "Start applying connectionstring $cleanKey with value $Value"		
		
			if ($cleanKey.Contains(".sqlazure"))
			{
				$cleanKey = $cleanKey.Replace(".sqlazure", "")
				$type = "SQLAzure"            
			}
			elseif ($cleanKey.Contains(".custom"))
			{
				$cleanKey = $cleanKey.Replace(".custom", "")			
				$type = "Custom"
			}
			elseif ($cleanKey.Contains(".sqlserver"))
			{
				$cleanKey = $cleanKey.Replace(".sqlserver", "")			
				$type = "SQLServer"
			}
			elseif ($cleanKey.Contains(".mysql"))
			{
				$cleanKey = $cleanKey.Replace(".mysql", "")			
				$type = "MySql"
			}
			else
			{
				$error = ("No database type given for connectionstring name {0} for website {1}. use naming convention: connectionstring.yourconnectionstring.sqlserver.sticky" -f $cleanKey, $WebAppName)
				Write-VstsTaskError $error
				throw $error
			}   			
		
			if ($Validate -and $connectionStringNames)
			{
				$found = $connectionStringNames.Contains($cleanKey);
				if (!$found)
				{
					$validationErrors.Add("Cannot find connectionString [$cleanKey] in web.config. But the key does exist in VSTS as a variable")
				}       
			}

			if ($originalKey.Contains(".sticky"))
			{
				Write-VstsTaskVerbose "Connectionstring $cleanKey added to sticky"
				$stickyConnectionStringNames.Add($cleanKey)  
			}

			Write-Host "Store connectionstring $cleanKey with value $Value of type $type"
			$connectionStringsHashTable[$cleanKey] = @{"Value" = $Value.ToString(); "Type" = $type.ToString()}


		}
	}
}

################# Validate-WebConfigVariablesAreInVSTSVariables #################
Write-VstsTaskVerbose "Validate-WebConfigVariablesAreInVSTSVariables. Validate: $Validate"
if ($Validate)
{
	
	if ($appSettingKeys)
	{
		$nrOfAppSettingKeys = $appSettingKeys.Count
		Write-VstsTaskVerbose "Nr of appsettingkeys [$nrOfAppSettingKeys]"

		foreach ($configAppSetting in $appSettingKeys.GetEnumerator()) {
			$configAppSettingName = $configAppSetting.key
			Write-VstsTaskVerbose "Trying to validate appsetting [$configAppSettingName]"
			$found = $settings.Contains($configAppSettingName);
			if (!$found)
			{
				$validationErrors.Add("Cannot find VSTS variable with name [appsetting.$configAppSettingName]. But the key does exist in the web.config")
			}  
		}
	}
	if ($connectionStringNames)
	{
		Write-VstsTaskVerbose "validate connectionstrings"			

		$nrOfConnectionstringNames = $connectionStringNames.Count
		Write-VstsTaskVerbose "Nr of connectionstringnames [$nrOfConnectionstringNames]"

		foreach ($configConnectionString in $connectionStringNames.GetEnumerator()) {
			$configConnectionStringName = $configConnectionString.key
			Write-VstsTaskVerbose "Trying to validate connectionstring [$configConnectionStringName]"
			$found = $connectionStringsHashTable.Contains($configConnectionStringName);
			if (!$found)
			{
				$validationErrors.Add("Cannot find VSTS variable with name [connectionstring.$configConnectionStringName]. But the key does exist in the web.config")
			}  
		}
	}
}

################# Output-ValidationResults #################
Write-VstsTaskVerbose "Output-ValidationResults. Should Validate: $Validate"
if ($Validate)
{
	switch($validationResultAction)
	{
		
		'warn' { 
			foreach ($validationError in $validationErrors) 
			{
				Write-VstsTaskWarning $validationError 
			}
		}
		'fail' { 
			foreach ($validationError in $validationErrors) 
			{
				Write-VstsTaskError $validationError				 
			}
		}
		default { Write-VstsTaskVerbose "No result action selected." } 
	}
}	

if ($Validate -and $validationErrors.Count -gt 0 -and $validationResultAction -eq "fail")
{
	Write-Host "Not writing the settings to the webapp because there are validation errors and the validation action result is fail"
	throw "Validation errors"		
}
else
{
	############## Write-Settings-To-WebApp #################
	Write-VstsTaskVerbose "Write-Settings-To-WebApp"	

	# The appsettings and connectionstrings has to be updated separately because when one of the collections is empty, an exception will be raised.
	if($SlotName){

		if ($settings.Count -gt 0){
			Write-VstsTaskVerbose "Write appsettings to website with deploymentslot"	
			$site = Set-AzureRMWebAppSlot -Name $WebAppName -ResourceGroupName $ResourceGroupName -AppSettings $settings -Slot $SlotName			
		}
		if ($connectionStringsHashTable.Count -gt 0){
			Write-VstsTaskVerbose "Write connectionstrings to website with deploymentslot"	
			$site = Set-AzureRMWebAppSlot -Name $WebAppName -ResourceGroupName $ResourceGroupName -ConnectionStrings $connectionStringsHashTable -Slot $SlotName			
		}
	}
	else
	{
		if ($settings.Count -gt 0){
			Write-VstsTaskVerbose "Write appsettings to website"	
			$site = Set-AzureRMWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -AppSettings $settings 
		}
		if ($connectionStringsHashTable.Count -gt 0){
			Write-VstsTaskVerbose "Write connectionstrings to website"			

			$site = Set-AzureRMWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -ConnectionStrings $connectionStringsHashTable	
		}
	}


	################# Write-Sticky-Settings #################
	Write-VstsTaskVerbose "Write-Sticky-Settings"
	$resourceName = $WebAppName + "/slotConfigNames"

	$stickySlot.properties.appSettingNames = $stickyAppSettingNames.ToArray()
	$stickySlot.properties.connectionStringNames = $stickyConnectionStringNames.ToArray()

	Set-AzureRmResource -ResourceName $resourceName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/Sites/config" -PropertyObject $stickySlot.properties -ApiVersion "2015-08-01" -Force
}

Trace-VstsLeavingInvocation $MyInvocation


