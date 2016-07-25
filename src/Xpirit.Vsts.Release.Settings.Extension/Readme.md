# Xpirit.Vsts.Release.Settings

A Release task for TFS 2015 and Visual Studio Team Services (VSTS) that 
enables you to deploy variables specified in VSTS, to deploy to AppSettings and ConnectionStrings 
of an Azure WebApp.

# Documentation

##Step 1: Select and Configure the task

##Step 2: Create variables with naming convention

The tasks uses naming conventions in the VSTS variables to deploy appsettings and connectionstrings to an Azure WebApp.
The value of the variable is used for the value for the appsetting or in case of a connectionstring, the connectionstring.

The following conventions are supported:

| What                           | VSTS variable name           |Azure output | 
| ------------------------------ | -----------------------| ----- |
| appsetting                     | appsetting.mysetting    | AppSetting with the name mysetting      |
| sticky appsetting              | appsetting.sticky.mysetting | AppSetting with the name mysetting. Slot setting checkbox is checked.  |
| connectionstring to SQL Server | connectionstring.sqlserver.myconnectionstring                | Connectionstring with the name myconnectionstring. The type is SQLServer. |
| connectionstring to SQL Azure  | connectionstring.sqlazure.myconnectionstring               | Connectionstring with the name myconnectionstring. The type is SQLAzure.    |
| connectionstring to custom   | connectionstring.custom.myconnectionstring                | Connectionstring with the name myconnectionstring. The type is Custom.    |
| connectionstring to MySQL      | connectionstring.mysql.myconnectionstring                | Connectionstring with the name myconnectionstring. The type is MySQL.   |
| sticky connectionstring        | connectionstring.sqlserver.sticky.myconnectionstring                | Connectionstring with the name myconnectionstring. The type is SQLServer. Slot setting checkbox is checked.|


Notes:

appsetting must be specified at the begin of the name

connectionstring must be specified at the begin of the name

.sticky can be placed anywhere in the name

##Preqrequisite A: Create Azure Service Principal

Create a Service principal in the Portal or in PowerShell:

[Create Azure Service Principal in the portal](https://azure.microsoft.com/nl-nl/documentation/articles/resource-group-create-service-principal-portal/)

[Create Azure Service Principal with PowerShell](https://raw.githubusercontent.com/Microsoft/vso-agent-tasks/master/Tasks/DeployAzureResourceGroup/SPNCreation.ps1)

##Preqrequisite B: Create ARM Endpoint in VSTS




# Wiki

Please check the [Wiki](https://github.com/XpiritBV/Xpirit-Vsts-Release-Twitter/wiki).