# StartStopVMbyTag
[MSFT] This powershell workflow script connects to Azure and start/stops parallely any VM (V1/V2) tagged with the corresponding status tag in the specified Azure subscription.   Tags are using the following format [autoShutdownSchedule:5pm -> 8am, Saturday, Sunday] and should correspond to the closing hours.

 # SYNOPSIS

  Connects to Azure and start/stops any VM (V1/V2) tagged with the corresponding status tag in the specified Azure subscription.
  Tags are using the following format [autoShutdownSchedule:5pm -> 8am, Saturday, Sunday]

 # DESCRIPTION

  Connects to Azure and start/stops any VM (V1/V2) tagged with the correct tag in the specified Azure subscription.  
  You can attach an hourly schedule to this runbook so it runs every hour, checks if all the tagged VMs in the subscription are supposed to be started or stopped, and starts or stops them accordingly.

 # REQUIRED TAGGING CONFIGURATION

  Since the scripts relies on tags to start to stop the VMs, be sure that you correctly tagged the VMs you want to be managed or they will be ignored.
  
  Tagging format should be the following :

    - Tag name : autoShutdownSchedule
    - Tag value (example): 5pm -> 8am, Saturday, Sunday
  
  The tag value corresponds to the time frame when the VM should be STOPPED. You can either set a full day (Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday), or if the day is not set, the time frame when the VM should not be running.
  In this example, the VM will be stopped every day at 5pm and restarted the day after at 8am, and will be stopped all day on Saturdays and Sundays.
  
  IMPORTANT : Any untagged VM will be ignored by the script

 # REQUIRED SCHEDULING CONFIGURATION

  The script has been designed to run every hour (or more, depending on the granularity you want to have). At each execution, it checks if the VMs should be in running or stopped state in the tag, and enforce it in Azure.

 # REQUIRED AUTOMATION ASSETS

  1. **An ARM connection to the subscription**

    You can use the default one created by the Azure Automation account or create a new one

  2. **AN ASM connection to the subscription**

    You can use the default one created by the Azure Automation account or create a new one

  3. **4 optional but recommended automation variables**, that points to default execution parameters if not set.Those variable are used for flexibility only since if the parameters are specified, they are not used/called at all:  
        a.**"Default ARM Credential"**, a string storing the name of the Azure Automation Connection asset used to connect to the sub using ARM (cf.[1])  
        b.**"Default ASM Credential"**, a string storing the name of the Azure Automation Connection asset used to connect to the sub using ASM (cf.[2])  
        c.**"Default Subscription ID"**, a string storing the default subscription ID used if not subscription ID is specified at execution.  
        d.**"Default Subscription Name"**, a string storing the default subscription name used if not subscription name is specified at execution (it must corresponds to the subscription ID above)  

 ## PARAMETER azureARMConnectionName
   *STRING, Optional with default of "Use *Default ARM Connection* Asset".*  If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of an Automation variable asset storing the name of the Azure Automation Service Principal Connection asset used to connect to the sub using ARM. 
   To use a different Service Principal Connection asset, directly pass the name of the specific Service Principal Connection as a runbook input parameter or change the default value for the input parameter.

 ## PARAMETER azureASMConnectionName
   *STRING, Optional with default of "Use *Default ASM Connection* Asset".*  If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of an Automation variable asset storing the name of the Azure Automation Classic Certificate Connection asset used to connect to the sub using ASM. 
   To use a different Classic Certificate Connection asset, directly pass the name of the specific Classic Certificate Connection as a runbook input parameter or change the default value for the input parameter.

 ## PARAMETER AzureSubscriptionName
   *STRING, Optional with default of "Use *Default Subscription Name* Variable Value".*  If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of An Automation variable asset storing the default subscription name used if not subscription name is specified at execution (it must corresponds to the subscription ID below).
   To use a subscription with a different name, you can pass the sub name (which will be the name of the subscription you want to target) as a runbook input parameter or change the default value for the input parameter.

 ## PARAMETER AzureSubscriptionID
  *STRING, Optional with default of "Use *Default Subscription ID* Variable Value"*.  If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of An Automation variable asset storing the default subscription ID used if not subscription ID is specified at execution (it must corresponds to the subscription Name above).
   To use a subscriptio with a different ID you can pass the sub ID (which will be the ID of the subscription you want to target) as a runbook input parameter or change the default value for the input parameter.

 ## PARAMETER Simulate
  *BOOLEAN, Optional with default of "False"*.  Sets if the VM are effectively started and stopped, or if we only check if the should be started or stopped (test mode).

 # NOTES
   AUTHOR: Baptiste Ohanes, Microsoft Field Engineer 
   LASTEDIT: July 7, 2017
   VERSION: 0.9.9 - Beta

 # DISCLAIMER

    THE SAMPLE CODE BELOW IS GIVEN “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICROSOFT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) SUSTAINED BY YOU OR A THIRD PARTY, HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT ARISING IN ANY WAY OUT OF THE USE OF THIS SAMPLE CODE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#>