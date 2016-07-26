[cmdletbinding()]
param(
[String] [Parameter(Mandatory = $true)]
    $ConnectedServiceName,

    [String] [Parameter(Mandatory = $true)]
    $WebAppName,

    [String] [Parameter(Mandatory = $true)]
    $DeployToSlotFlag,

    [String] [Parameter(Mandatory = $false)]
    $ResourceGroupName,

    [String] [Parameter(Mandatory = $false)]
    $SlotName,
	
	[String] [Parameter(Mandatory = $true)]
    $ValidateFlag,

	[String] [Parameter(Mandatory = $true)]
    $WebConfigFile,
	[string] $validationResultAction,
	[string] $Cleanup = "true"
)

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

$settingHelperPath = "./Modules\Xpirit.Vsts.Release.SettingHelper.dll"
import-module $settingHelperPath

#Convert string parameters to bools
$Clean = (Convert-String $Cleanup Boolean)
$Validate = (Convert-String $ValidateFlag Boolean)

function Output-ValidationResults()
{
	Write-Verbose "Output-ValidationResults. Should Validate: $Validate"
	if ($Validate)
	{
		switch($validationResultAction)
		{
		
			'warn' { 
				foreach ($validationError in $validationErrors) 
				{
					Write-Warning $validationError 
				}
			}
			'fail' { 
				foreach ($validationError in $validationErrors) 
				{
					Write-Error $validationError 
				}
			}
			default { Write-Verbose "No result action selected." } 
		}
	}
}

function Write-Settings-To-WebApp()
{
	Write-Verbose "Write-Settings-To-WebApp"	

	# The appsettings and connectionstrings has to be updated separately because when one of the collections is empty, an exception will be raised.
	if($SlotName){

		if ($settings.Count -gt 0){
			Write-Verbose "Write appsettings to website with deploymentslot"	
			$site = Set-AzureRMWebAppSlot -Name $WebAppName -ResourceGroupName $ResourceGroupName -AppSettings $settings -Slot $SlotName			
		}
		if ($connectionStringsHashTable.Count -gt 0){
			Write-Verbose "Write connectionstrings to website with deploymentslot"	
			$site = Set-AzureRMWebAppSlot -Name $WebAppName -ResourceGroupName $ResourceGroupName -ConnectionStrings $connectionStringsHashTable -Slot $SlotName			
		}
	}
	else
	{
		if ($settings.Count -gt 0){
			Write-Verbose "Write appsettings to website"	
			$site = Set-AzureRMWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -AppSettings $settings 
		}
		if ($connectionStringsHashTable.Count -gt 0){
			Write-Verbose "Write connectionstrings to website"			

			$site = Set-AzureRMWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -ConnectionStrings $connectionStringsHashTable	
		}
	}
}

function Write-Sticky-Settings()
{
	Write-Verbose "Write-Sticky-Settings"
	$resourceName = $WebAppName + "/slotConfigNames"

	$stickySlot.properties.appSettingNames = $stickyAppSettingNames.ToArray()
	$stickySlot.properties.connectionStringNames = $stickyConnectionStringNames.ToArray()

	Set-AzureRmResource -ResourceName $resourceName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/Sites/config" -PropertyObject $stickySlot.properties -ApiVersion "2015-08-01" -Force
}

function Read-WebConfigToPrepareValidation()
{
	Write-Verbose "Read-WebConfigToPrepareValidation. Validate: $Validate"
	if ($Validate)
	{
		#Read web.config
		$xml = [xml] (Get-Content $WebConfigFile)

		Write-Verbose "Start reading appsettings"
		foreach($appSetting in $xml.configuration.appSettings.add)
		{
			$script:appSettingKeys[$appSetting.key] = $appSetting.key
		}
				
		Write-Verbose "Start reading connectionstrings"
		foreach($connectionString in $xml.configuration.connectionStrings.add)
		{
			$script:connectionStringNames[$connectionString.name] = $connectionString.name
		}
	
		
		Write-Verbose "Finished reading config file"		
	}
}

function Read-Settings-From-WebApp()
{
	Write-Verbose "Read-Settings-From-WebApp"

	if($SlotName)
	{
		Write-Verbose "Reading configuration from website $WebAppName and deploymentslot $SlotName" 
		$script:WebSite = Get-AzureRmWebAppSlot -Name $WebAppName -Slot $SlotName -ResourceGroupName $ResourceGroupName
	}
	else
	{
		Write-Verbose "Reading configuration from website $WebAppName" 
		$script:WebSite = Get-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName
	}
	if(!$WebSite) 
	{
		$error = ("Failed to find WebSite {0}" -f $WebAppName)
		Write-Error $error
		throw $error
	}

	Write-Verbose "Fetch appsettings"
	# Get all appsettings and put in Hashtable (because Set-AzureRMWebApp needs that)
	if (!$Clean)
	{
		ForEach ($kvp in $WebSite.SiteConfig.AppSettings) {
			$settings[$kvp.Name] = $kvp.Value
		}
	}
	Write-Verbose "appsettings: $settings"
	Write-Verbose "Fetch connectionstrings"

	# Get all connectionstrings and put it in a Hashtable (because Set-AzureRMWebApp needs that)	
	if (!$Clean)
	{
		ForEach ($kvp in $WebSite.SiteConfig.ConnectionStrings) {
			$connectionStringsHashTable[$kvp.Name] = @{"Value" = $kvp.ConnectionString.ToString(); "Type" = $kvp.Type.ToString()} #Make sure that Type is a string    
		}
	}
	Write-Verbose "connectionstrings: $connectionStringsHashTable"
}

function Read-Sticky-Settings()
{
	Write-Verbose "Read-Sticky-Settings"
	
	$resourceName = $WebAppName + "/slotConfigNames"
	$script:stickySlot = Get-AzureRmResource -ResourceName $resourceName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/sites/config" -ApiVersion "2015-08-01"
	
	if (!$Clean)
	{
		# Fill with all existing settings
		$stickyAppSettingNames.AddRange($script:stickySlot.properties.appSettingNames)
		$stickyConnectionStringNames.AddRange($script:stickySlot.properties.connectionStringNames)
	}
	Write-Verbose "Finished Read-Sticky-Settings"
}

function Read-Variables-From-VSTS()
{
	Write-Verbose "Read-Variables-From-VSTS"
	# Get all variables. Loop through each and apply if needed.
	$script:vstsVariables = Get-TaskVariables -Context $distributedTaskContext 
	Write-Verbose "Variable Values"
	$vstsVariables.Keys | %{ Write-Verbose "$_ = $($vstsVariables[$_])" }
}

function Validate-WebConfigVariablesAreInVSTSVariables()
{
	Write-Verbose "Validate-WebConfigVariablesAreInVSTSVariables. Validate: $Validate"
	if ($Validate)
	{
		if ($appSettingKeys)
		{
			foreach ($configAppSetting in $appSettingKeys.GetEnumerator()) {
				$configAppSettingName = $configAppSetting.key
				Write-Verbose "Trying to validate appsetting [$configAppSettingName]"
				$found = $settings.Contains($configAppSettingName);
				if (!$found)
				{
					$validationErrors.Add("Cannot find VSTS variable with name [appsetting.$configAppSettingName]. But the key does exist in the web.config")
				}  
			}
		}
		if ($connectionStringNames)
		{
			Write-Verbose "validate connectionstrings"			

			foreach ($configConnectionString in $connectionStringNames.GetEnumerator()) {
				$configConnectionStringName = $configConnectionString.key
				Write-Verbose "Trying to validate connectionstring [$configConnectionStringName]"
				$found = $connectionStringsHashTable.Contains($configConnectionStringName);
				if (!$found)
				{
					$validationErrors.Add("Cannot find VSTS variable with name [connectionstring.$configConnectionStringName]. But the key does exist in the web.config")
				}  
			}
		}
	}
}

function AddSettingToStickyVariables()
{
	param(
		[string] $originalKey,
		[string] $cleanKey,
		[string] $value
	)

	if ($originalKey.Contains(".sticky"))
	{
		if ($originalKey.StartsWith("appsetting."))
		{	
			$stickyAppSettingNames.Add($cleanKey)
		}
		elseif ($originalKey.StartsWith("connectionstring."))
		{
			$stickyConnectionStringNames.Add($cleanKey)  
		}
	}
}

function AddSettingAsAppSetting()
{
	param(		
		[string] $cleanKey,
		[string] $value
	)

	Write-Host "Store appsetting $cleanKey with value $Value"

	$settings[$cleanKey.ToString()] = $Value.ToString();		
		
	if ($Validate -and $appSettingKeys)
	{
		Write-Verbose "Going to validate $cleankey to:"

		$found = $appSettingKeys.Contains($cleanKey);
		if (!$found)
		{
			$validationErrors.Add("Cannot find appSetting [$cleanKey] in web.config. But the key does exist in VSTS as a variable")
		}
		Write-Verbose "Validated"
	}
}

function AddSettingAsConnectionString()
{
	param(		
		[string] $cleanKey,
		[string] $value
	)

	Write-Verbose "Start applying connectionstring $cleanKey with value $Value"		
		
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
		Write-Error $error
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

	Write-Host "Store connectionstring $cleanKey with value $Value of type $type"
	$connectionStringsHashTable[$cleanKey] = @{"Value" = $Value.ToString(); "Type" = $type.ToString()}
}

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

Read-WebConfigToPrepareValidation
Read-Settings-From-WebApp
Read-Sticky-Settings
Read-Variables-From-VSTS

foreach ($h in $vstsVariables.GetEnumerator()) {
	Write-Verbose "Processing vstsvariable: $($h.Key): $($h.Value)"

	$originalKey = $h.Key
	$cleanKey = $originalKey.Replace(".sticky", "").Replace("appsetting.", "").Replace("connectionstring.", "")
	$Value = Get-TaskVariable $distributedTaskContext $originalKey

	AddSettingToStickyVariables -originalKey $originalKey -cleanKey $cleanKey -value $Value
		
	if ($originalKey.StartsWith("appsetting."))
	{	
		AddSettingAsAppSetting -cleanKey $cleanKey -value $Value
	}
	elseif ($originalKey.StartsWith("connectionstring."))
	{		
		AddSettingAsConnectionString -cleanKey $cleanKey -value $value
	}
}


Validate-WebConfigVariablesAreInVSTSVariables

Output-ValidationResults
if ($Validate -and $validationErrors.Count -gt 0 -and $validationResultAction -eq "fail")
{
	Write-Host "Not writing the settings to the webapp because there are validation errors and the validation action result is fail"		
}
else
{
	Write-Settings-To-WebApp
	Write-Sticky-Settings
}
Write-Verbose "##vso[task.complete result=Succeeded;]DONE"


