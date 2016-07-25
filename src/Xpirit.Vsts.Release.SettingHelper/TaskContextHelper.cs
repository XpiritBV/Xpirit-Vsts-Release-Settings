using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.TeamFoundation.DistributedTask.Agent.Common;
using Microsoft.TeamFoundation.DistributedTask.Agent.Interfaces;
using System;

namespace Xpirit.Vsts.Release.SettingHelper
{
    public static class TaskContextHelper
    {
        public static IDictionary<string, string> GetAllVariables(ITaskContext context, bool isSafe = false)
        {
            IVariableService ivariableService = (IVariableService)((IServiceManager)context).GetService<IVariableService>();
            IDictionary<string, string> dictionary = new Dictionary<string, string>();
            if (ivariableService != null)
            {
                if (!isSafe)
                    ivariableService.MergeVariables(dictionary);
                else
                {
                    ivariableService.MergeSafeVariables(dictionary);
                }
            }

            
            return dictionary;
        }
    }
}
