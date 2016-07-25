using Microsoft.TeamFoundation.DistributedTask.Agent.Common;
using Microsoft.TeamFoundation.DistributedTask.Agent.Interfaces;
using System.Management.Automation;

namespace Xpirit.Vsts.Release.SettingHelper
{
    [Cmdlet("Get", "TaskVariables")]
    public sealed class GetTaskVariablesCmdlet : PSCmdlet
    {
        [Parameter(Mandatory = true, Position = 1)]
        public ITaskContext Context { get; set; }

        [Parameter(Mandatory = false, Position = 3)]
        public bool IsSafe { get; set; }

        protected override void ProcessRecord()
        {
            base.ProcessRecord();
            TraceLogger.Default.Verbose("Invoke - Get-TaskVariables cmdlet");
            
            this.WriteObject(TaskContextHelper.GetAllVariables(this.Context, this.IsSafe));
        }
    }
}
