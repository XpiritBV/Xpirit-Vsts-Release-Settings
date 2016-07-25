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
	
	[string] $Cleanup = "true"
)

$Clean = (Convert-String $Cleanup Boolean)

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Host "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

$settingHelperPath = "./Modules\Xpirit.Vsts.Release.SettingHelper.dll"
import-module $settingHelperPath

if($SlotName)
{
	Write-Verbose "applying configuration to website $WebAppName and deploymentslot $SlotName" 
	$WebSite = Get-AzureRmWebAppSlot -Name $WebAppName -Slot $SlotName -ResourceGroupName $ResourceGroupName
}
else
{
	Write-Verbose "applying configuration to website $WebAppName" 
	$WebSite = Get-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName
}
if(!$WebSite) 
{
	$error = ("Failed to find WebSite {0}" -f $WebAppName)
	Write-Error $error
	throw $error
}

Write-Verbose "Fetch current sticky settings"
# Get Sticky info
$resourceName = $WebAppName + "/slotConfigNames"
$stickySlot = Get-AzureRmResource -ResourceName $resourceName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/sites/config" -ApiVersion "2015-08-01"

# Fill with all existing settings
$stickyAppSettingNames = New-Object 'System.Collections.Generic.List[object]'
$stickyConnectionStringNames = New-Object 'System.Collections.Generic.List[object]'
if (!$Clean)
{
	$stickyAppSettingNames.AddRange($stickySlot.properties.appSettingNames)
	$stickyConnectionStringNames.AddRange($stickySlot.properties.connectionStringNames)
}

Write-Verbose "Fetch appsettings"
# Get all appsettings and put in Hashtable (because Set-AzureRMWebApp needs that)
$settings = @{}
if (!$Clean)
{
	ForEach ($kvp in $WebSite.SiteConfig.AppSettings) {
		$settings[$kvp.Name] = $kvp.Value
	}
}
Write-Verbose "appsettings: $settings"
Write-Verbose "Fetch connectionstrings"
# Get all connectionstrings and put it in a Hashtable (because Set-AzureRMWebApp needs that)
$connectionStringsHashTable = @{}
if (!$Clean)
{
	ForEach ($kvp in $WebSite.SiteConfig.ConnectionStrings) {
		$connectionStringsHashTable[$kvp.Name] = @{"Value" = $kvp.ConnectionString.ToString(); "Type" = $kvp.Type.ToString()} #Make sure that Type is a string    
	}
}
Write-Verbose "connectionstrings: $connectionStringsHashTable"

# Get all variables. Loop through each and apply if needed.
$value = Get-TaskVariables -Context $distributedTaskContext 
Write-Verbose "Variable Values"
$value.Keys | %{ Write-Host "$_ = $($value[$_])" }
foreach ($h in $value.GetEnumerator()) {
	Write-Verbose "Found key: $($h.Key): $($h.Value)"
	$originalKey = $h.Key
	$cleanKey = $originalKey.Replace(".sticky", "").Replace("appsetting.", "").Replace("connectionstring.", "")
	$Value = Get-TaskVariable $distributedTaskContext $originalKey

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
	
	if ($originalKey.StartsWith("appsetting."))
	{	
		Write-Host "Store appsetting $cleanKey with value $Value"

		$settings[$cleanKey.ToString()] = $Value.ToString();		
	}
	elseif ($originalKey.StartsWith("connectionstring."))
	{		
		Write-Host "Start applying connectionstring $cleanKey with value $Value"		
		
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
			
		Write-Verbose "Store connectionstring $cleanKey with value $Value of type $type"
		        
		$connectionStringsHashTable[$cleanKey] = @{"Value" = $Value.ToString(); "Type" = $type.ToString()}        
	}
}

# Apply appsettings and connectionstrings to the webapp
Write-Verbose "Write appsettings and/or connectionstrings if needed"

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
		Write-Host "Write appsettings to website"	
		$site = Set-AzureRMWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -AppSettings $settings 
	}
	if ($connectionStringsHashTable.Count -gt 0){
		Write-Host "Write connectionstrings to website"			

		$site = Set-AzureRMWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -ConnectionStrings $connectionStringsHashTable	
	}
}

Write-Host "Write sticky configuration"
# Write Sticky info back to Website
$stickySlot.properties.appSettingNames = $stickyAppSettingNames.ToArray()
$stickySlot.properties.connectionStringNames = $stickyConnectionStringNames.ToArray()

Set-AzureRmResource -ResourceName $resourceName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/Sites/config" -PropertyObject $stickySlot.properties -ApiVersion "2015-08-01" -Force



Write-Verbose "##vso[task.complete result=Succeeded;]DONE"


