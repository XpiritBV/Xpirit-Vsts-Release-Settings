# Azure WebApp Configuration task

The Azure WebApp Configuration task reads VSTS variables and adds those as AppSettings and ConnectionStrings to an Azure WebApp. The task also supports Slot Settings. The task can be linked to a web.config to validate if all AppSettings and ConnectionStrings in the web.config exists as VSTS variable. 

The Task can be found in the [marketplace](https://marketplace.visualstudio.com/items?itemName=pascalnaber.PascalNaber-Xpirit-WebAppConfiguration) and added to your VSTS Account. The code is open source and can be found on [GitHub](https://github.com/XpiritBV/Xpirit-Vsts-Release-Settings). 



##Naming convention
The task uses naming conventions in the VSTS variables to deploy appsettings and connectionstrings to an Azure WebApp. If you like as a Slot Setting. The value of the VSTS variable is used for the value for the appsetting or in case of a connectionstring, the connectionstring. 

The following naming conventions rules are supported: 

- The name of a variable for an appsetting must start with appsetting. 
- The name of a variable for a connectionstring must start with connectionstring. 
- The type of database should be added in the namingconvention as stated in the following table. 
- For a slotsetting the convention .sticky must be used. 

The table below shows some examples:


| Type                           | Example VSTS variable name                          
| ------------------------------ | ----------------------------------------------------| ----- |
| appsetting                     | appsetting.mysetting                                
| sticky appsetting              | appsetting.sticky.mysetting                         
| connectionstring to SQL Server | connectionstring.myconnectionstring.sqlserver       
| connectionstring to SQL Azure  | connectionstring.myconnectionstring.sqlazure       
| connectionstring to custom     | connectionstring.myconnectionstring.custom         
| connectionstring to MySQL      | connectionstring.myconnectionstring.mysql           
| sticky connectionstring        | connectionstring.myconnectionstring.sqlserver.sticky


##Steps to use and configure the task
 1. Install the task in your VSTS account by navigating to the [marketplace](https://marketplace.visualstudio.com/items?itemName=pascalnaber.PascalNaber-Xpirit-WebAppConfiguration) and click install. Select the VSTS account where the task will be deployed to.
 
 2. Add the task to your release by clicking in your release on add a task and select the Utility category. Click the Add  button on the Apply variables to Azure webapp task.
 ![alt tag](https://github.com/XpiritBV/Xpirit-Vsts-Release-Settings/raw/master/src/Xpirit.Vsts.Release.Settings.Extension/Images/addtask.png)
 3. Configure the task. When the task is added the configuration will look like this:
![alt tag](https://github.com/XpiritBV/Xpirit-Vsts-Release-Settings/raw/master/src/Xpirit.Vsts.Release.Settings.Extension/Images/cleantask.png)
    All yellow fields are required.

  - Select an AzureRM subscription. If you don’t know how to configure this. [Read this blogpost](https://pascalnaber.wordpress.com/2016/07/27/create-an-azure-service-principal-and-a-vsts-arm-endpoint/).
  - Select the web app name.
  - Select the resourcegroup.
  - If you want to deploy to a Deployment slot, check the Deploy to Slot checkbox and select the Slot.
  - If you want to validate the VSTS variables against the appSettings and ConnectionStrings in the web.config of the application you deploy, then select the web.config. Otherwise uncheck the Validate variables checkbox.
  - When you want validation, you can choose how the task should behave when it finds incorrect variables. Default behavior is that the task will fail with an error. This results in a failed Release  and the variables will not be deployed.
The other validation result action is  to only get a warning. The variables will be deployed to Azure.
   - By default all existing AppSettings and ConnectionStrings in Azure are overwritten by the variables in the release. When you don’t want this, but you want to preserve your appsettings or connectionstrings in your WebApp, then uncheck the Overwrite existing configuration checkbox. 

 4. The web.config of your application is not being used to deploy variables to Azure. If you have configured validation, the keys of the appSettings and the names of the ConnectionStrings are used to validate if there are VSTS variables available for these settings. The web.config in this sample looks like this:
![alt tag](https://github.com/XpiritBV/Xpirit-Vsts-Release-Settings/raw/master/src/Xpirit.Vsts.Release.Settings.Extension/Images/webconfig.png) 

 5. Add variables that match the names of the variables in the AppSettings and ConnectionStrings. Also apply the namingconventions for the VSTS variables.
![alt tag](https://github.com/XpiritBV/Xpirit-Vsts-Release-Settings/raw/master/src/Xpirit.Vsts.Release.Settings.Extension/Images/vstsvariables.png) 
 6. When you run the release, the settings will be deployed to Azure. In this sample it looks like this: Note that the hidden value in VSTS is visible now in Azure.
 
 ![alt tag](https://github.com/XpiritBV/Xpirit-Vsts-Release-Settings/raw/master/src/Xpirit.Vsts.Release.Settings.Extension/Images/azure.png)
