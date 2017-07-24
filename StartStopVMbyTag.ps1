<#
.SYNOPSIS

  Connects to Azure and start/stops any VM (V1/V2) tagged with the corresponding status tag in the specified Azure subscription.
  Tags are using the following format [autoShutdownSchedule:5pm -> 8am, Saturday, Sunday]

.DESCRIPTION

  Connects to Azure and start/stops any VM (V1/V2) tagged with the correct tag in the specified Azure subscription.  
  You can attach an hourly schedule to this runbook so it runs every hour, checks if all the tagged VMs in the subscription are supposed to be started or stopped, and starts or stops them accordingly.

.REQUIRED TAGGING CONFIGURATION

  Since the scripts relies on tags to start to stop the VMs, be sure that you correctly tagged the VMs you want to be managed or they will be ignored.
  
  Tagging format should be the following :

    - Tag name : autoShutdownSchedule
    - Tag value (example): 5pm -> 8am, Saturday, Sunday
        The tag value corresponds to the time frame when the VM should be STOPPED. You can either set a full day (Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday), or if the day is not set, the time frame when the VM should not be running.
        In this example, the VM will be stopped every day at 5pm and restarted the day after at 8am, and will be stopped all day on Saturdays and Sundays.
  
  IMPORTANT : Any untagged VM will be ignored by the script

.REQUIRED SCHEDULING CONFIGURATION

  The script has been designed to run every hour (or more, depending on the granularity you want to have). At each execution, it checks if the VMs should be in running or stopped state in the tag, and enforce it in Azure.

.REQUIRED AUTOMATION ASSETS

  1. An ARM connection to the subscription

    You can use the default one created by the Azure Automation account or create a new one

  2. AN ASM connection to the subscription

    You can use the default one created by the Azure Automation account or create a new one

  3. 4 optional but recommended automation variables, that points to default execution parameters if not set.
     Those variable are used for flexibility only since if the parameters are specified, they are not used/called at all.
        a."Default ARM Connection", a string storing the name of the Azure Automation Connection asset used to connect to the sub using ARM (cf.[1])
        b."Default ASM Connection", a string storing the name of the Azure Automation Connection asset used to connect to the sub using ASM (cf.[2])
        c."Default Subscription ID", a string storing the default subscription ID used if not subscription ID is specified at execution
        d."Default Subscription Name", a string storing the default subscription name used if not subscription name is specified at execution (it must corresponds to the subscription ID above)

.PARAMETER azureARMConnectionName
   STRING, Optional with default of "Use *Default ARM Connection* Asset". If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of an Automation variable asset storing the name of the Azure Automation Service Principal Connection asset used to connect to the sub using ARM. 
   To use a different Service Principal Connection asset, directly pass the name of the specific Service Principal Connection as a runbook input parameter or change the default value for the input parameter.

.PARAMETER azureASMConnectionName
   STRING, Optional with default of "Use *Default ASM Connection* Asset".If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of an Automation variable asset storing the name of the Azure Automation Classic Certificate Connection asset used to connect to the sub using ASM. 
   To use a different Classic Certificate Connection asset, directly pass the name of the specific Classic Certificate Connection as a runbook input parameter or change the default value for the input parameter.

.PARAMETER AzureSubscriptionName
   STRING, Optional with default of "Use *Default Subscription Name* Variable Value". If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of An Automation variable asset storing the default subscription name used if not subscription name is specified at execution (it must corresponds to the subscription ID below).
   To use a subscription with a different name, you can pass the sub name (which will be the name of the subscription you want to target) as a runbook input parameter or change the default value for the input parameter.

.PARAMETER AzureSubscriptionID
   STRING, Optional with default of "Use *Default Subscription ID* Variable Value". If not specified at execution, ensure that you created and set the value of the corresponding variable.
   The name of An Automation variable asset storing the default subscription ID used if not subscription ID is specified at execution (it must corresponds to the subscription Name above).
   To use a subscriptio with a different ID you can pass the sub ID (which will be the ID of the subscription you want to target) as a runbook input parameter or change the default value for the input parameter.

.PARAMETER Simulate
   BOOLEAN, Optional with default of "False".
   Sets if the VM are effectively started and stopped, or if we only check if the should be started or stopped (test mode).

.NOTES
   AUTHOR: Baptiste Ohanes, Microsoft Field Engineer 
   LASTEDIT: July 24th, 2017
   VERSION: 1.0.0 - RTW

.DISCLAIMER

    THE SAMPLE CODE BELOW IS GIVEN “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICROSOFT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) SUSTAINED BY YOU OR A THIRD PARTY, HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT ARISING IN ANY WAY OUT OF THE USE OF THIS SAMPLE CODE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#>

workflow StartStopVMbyTag {
    param(
        [parameter(Mandatory = $false)]
        [String] $azureARMConnectionName = "Use *Default ARM Connection* Asset",
        [parameter(Mandatory = $false)]
        [String] $azureASMConnectionName = "Use *Default ASM Connection* Asset",
        [parameter(Mandatory = $false)]
        [String] $azureSubscriptionName = "Use *Default Subscription Name* Variable Value",
        [parameter(Mandatory = $false)]
        [String] $azureSubscriptionID = "Use *Default Subscription ID* Variable Value",
        [parameter(Mandatory = $false)]
        [bool]$Simulate = $false
    )

    $VERSION = "1.0.0 - RTW"

    Try {
        $currentTime = (Get-Date).ToUniversalTime()
        Write-Output "WARNING - THIS EXAMPLE SCRIPT SHOULD BE TESTED TO ENSURE IT FITS YOUR ENVIRONNEMENT - SEE DISCLAIMER"
        Write-Output "Runbook started. Version: $VERSION"
        if ($Simulate) {
            Write-Output "*** Running in SIMULATE mode. No power actions will be taken. ***"
        }
        else {
            Write-Output "*** Running in LIVE mode. Schedules will be enforced. ***"
        }
        Write-Output "Current UTC/GMT time [$($currentTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))] will be checked against schedules"
	
        # Retrieve subscription name from variable asset if not specified

        if ($azureSubscriptionName -eq "Use *Default Subscription Name* Variable Value") {
            $azureSubscriptionName = Get-AutomationVariable -Name "Default Subscription Name"
            $azureSubscriptionID = Get-AutomationVariable -Name "Default Subscription ID"
            if ($azureSubscriptionName.length -gt 0) {
                Write-Output "Specified subscription name/ID: [$azureSubscriptionName]/$azureSubscriptionID"
            }
            else {
                throw "No subscription name was specified, and no variable asset with name 'Default Subscription Name' was found. Either specify an Azure subscription name or define the default using a variable setting"
            }
        }

        # Retrieve Classic credential

        write-output "Specified classic connection asset name: [$azureASMConnectionName]"
        if ($azureASMConnectionName -eq "Use *Default ASM Connection* asset") {
            # By default, look for "Default Classic Credential" asset and if the associated certficate exists, otherwise, set it to $null

            $azureASMConnectionName = Get-AutomationVariable -Name "Default ASM Connection"
            $azureASMConnection = Get-AutomationConnection -Name $azureASMConnectionName
            if ($azureASMConnection -ne $null) {
                $azureClassicCertificate = Get-AutomationCertificate -Name $azureASMConnection.CertificateAssetName
                if ($azureClassicCertificate -ne $null) {
                    Write-Output "Attempting to authenticate against ASM as [$azureASMConnectionName], with certificate $($azureASMConnection.CertificateAssetName)"
                }
                else {
                    Write-Output "Could not retrieve certificate asset: $($azureASMConnection.CertificateAssetName). Assure that this asset exists in the Automation account."
                    $azureASMConnection = $null

                }
            }
            else {
                throw "No classic automation connection name was specified, and no variable asset with name 'Default ASM Connection' was found. Either specify a stored credential name or define the default using a credential asset"
            }
        }
        else {
            # A different credential name was specified, attempt to load it
            $azureASMConnection = Get-AutomationConnection -Name $azureASMConnectionName
            if ($azureASMConnection -eq $null) {
                throw "Failed to get ASM connection with name [$azureASMConnectionName]"
            }
        }

        # Retrieve ARM credential

        write-output "Specified ARM connection asset name: [$azureARMConnectionName]"
        if ($azureARMConnectionName -eq "Use *Default ARM Connection* asset") {
            # By default, look for "Default ARM Credential" asset

            $azureARMConnectionName = Get-AutomationVariable -Name "Default ARM Connection"
            $azureARMConnection = Get-AutomationConnection -Name $azureARMConnectionName
            if ($azureARMConnection -ne $null) {
                #AddCheckIfCertificateExists
                Write-Output "Attempting to authenticate against ARM as [$azureARMConnectionName], with AppID : $($azureARMConnection.ApplicationId)"
            }
            else {
                throw "No ARM automation credential name was specified, and no variable asset with name 'Default ARM Connection' was found. Either specify a stored credential name or define the default using a credential asset"
            }
        }
        else {
            # A different credential name was specified, attempt to load it
            $azureARMConnection = Get-AutomationConnection -Name $azureARMConnectionName
            if ($azureARMConnection -eq $null) {
                throw "Failed to get ARM connection with name [$azureARMConnectionName]"
            }
        }

        #Connect to environnements using ASM

        Write-Output "Establishing connection to the subscriptions..."

        $azureClassicCertificate = Get-AutomationCertificate -Name $azureASMConnection.CertificateAssetName
        $ClassicSucceededConnection = Set-AzureSubscription -SubscriptionName $azureSubscriptionName -subscriptionID $azureSubscriptionID -Certificate $azureClassicCertificate -PassThru
        Select-AzureSubscription -SubscriptionName $azureSubscriptionName
        if ($ClassicSucceededConnection -eq $true) {
            Write-Output "Connection with ASM failed for subscription $azureSubscriptionName. Check that name, Id and certificate are correct"
        }
        else {
            Write-Output "Connection with ASM for subscription $azureSubscriptionName successful."
        }
    
        #Connect to environnements using ARM

        Add-AzureRmAccount -ServicePrincipal -TenantId $azureARMConnection.TenantId -ApplicationId $azureARMConnection.ApplicationId -CertificateThumbprint $azureARMConnection.CertificateThumbprint
        $ARMSucceededConnection = Set-AzureRMContext -SubscriptionName $azureSubscriptionName
        if ($ARMSuccedeedConnection.Subscription -eq $azureSubscriptionID) {
            Write-Output "Connection with ARM failed for subscription $azureSubscriptionName. Check that name, id, service principal and certificates  are correct"
        }
        else {
            Write-Output "Connection with ARM for subscription $azureSubscriptionName successful."
        }

        # Get a list of all virtual machines in subscription
        $resourceManagerVMList = @(Get-AzureRmResource | where {$_.ResourceType -like "Microsoft.*/virtualMachines"} | sort Name)
        $classicVMList = Get-AzureVM

        # Get resource groups that are tagged for automatic shutdown of resources
        $taggedResourceGroups = @(Get-AzureRmResourceGroup | where {$_.Tags.Count -gt 0 -and $_.Tags.Name -contains "AutoShutdownSchedule"})
        $taggedResourceGroupNames = @($taggedResourceGroups | select -ExpandProperty ResourceGroupName)
        Write-Output "Found [$($taggedResourceGroups.Count)] schedule-tagged resource groups in subscription"

        # For each VM, determine
        #  - Is it directly tagged for shutdown or member of a tagged resource group
        #  - Is the current time within the tagged schedule 
        # Then assert its correct power state based on the assigned schedule (if present)
        Write-Output "Processing [$($resourceManagerVMList.Count)] virtual machines found in subscription"
        foreach -parallel ($vm in $resourceManagerVMList) {
            $schedule = $null
            if (($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags -and $vm.Tags.Name -contains "AutoShutdownSchedule") -or ($taggedResourceGroupNames -contains $vm.ResourceGroupName)) {
                # Check for direct tag or group-inherited tag
                if ($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags -and $vm.Tags.Name -contains "AutoShutdownSchedule") {
                    # VM has direct tag (possible for resource manager deployment model VMs). Prefer this tag schedule.
                    $schedule = ($vm.Tags | where Name -eq "AutoShutdownSchedule")["Value"]
                    Write-Output "[$($vm.Name)]: Found direct VM schedule tag with value: $schedule"
                }
                elseif ($taggedResourceGroupNames -contains $vm.ResourceGroupName) {
                    # VM belongs to a tagged resource group. Use the group tag
                    $parentGroup = $taggedResourceGroups | where ResourceGroupName -eq $vm.ResourceGroupName
                    $schedule = ($parentGroup.Tags | where Name -eq "AutoShutdownSchedule")["Value"]
                    Write-Output "[$($vm.Name)]: Found parent resource group schedule tag with value: $schedule"
                }
                # Check that tag value was succesfully obtained
                if ($schedule -eq $null) {
                    Write-Output "[$($vm.Name)]: Failed to get tagged schedule for virtual machine. Skipping this VM."
                }
                else {
                    # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
                    $timeRangeList = @($schedule -split "," | foreach {$_.Trim()})
	    
                    # Check each range against the current time to see if any schedule is matched
                    $scheduleMatched = $false
                    $matchedSchedule = $null
                    foreach ($entry in $timeRangeList) {
		            
                        #Start of check

                        # Initialize variables
                        $timerange = $entry
                        $rangeStart = $null
                        $rangeEnd = $null
                        $parsedDay = $null
                        $midnight = $currentTime.AddDays(1).Date
                        $timecheckresult = $null	        

                        try {
                            # Parse as range if contains '->'
                            if ($TimeRange -like "*->*") {
                                $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
                                if ($timeRangeComponents.Count -eq 2) {
                                    $rangeStart = Get-Date $timeRangeComponents[0]
                                    $rangeEnd = Get-Date $timeRangeComponents[1]
	
                                    # Check for crossing midnight
                                    if ($rangeStart -gt $rangeEnd) {
                                        # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                                        if ($currentTime -ge $rangeStart -and $currentTime -lt $midnight) {
                                            $rangeEnd = $rangeEnd.AddDays(1)
                                        }
                                        # Otherwise interpret start time as yesterday and end time as today   
                                        else {
                                            $rangeStart = $rangeStart.AddDays(-1)
                                        }
                                    }
                                }
                                else {
                                    Write-Output "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'" 
                                }
                            }
                            # Otherwise attempt to parse as a full day entry, e.g. 'Monday' or 'December 25' 
                            else {
                                # If specified as day of week, check if today
                                if ([System.DayOfWeek].GetEnumValues() -contains $TimeRange) {
                                    if ($TimeRange -eq (Get-Date).DayOfWeek) {
                                        $parsedDay = Get-Date "00:00"
                                    }
                                    else {
                                        # Skip detected day of week that isn't today
                                    }
                                }
                                # Otherwise attempt to parse as a date, e.g. 'December 25'
                                else {
                                    $parsedDay = Get-Date $TimeRange
                                }
	    
                                if ($parsedDay -ne $null) {
                                    $rangeStart = $parsedDay # Defaults to midnight
                                    $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59) # End of the same day
                                }
                            }
                        }
                        catch {
                            # Record any errors and return false by default
                            Write-Output "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). Check the syntax of entry, e.g. '<StartTime> -> <EndTime>', or days/dates like 'Sunday' and 'December 25'"   
                            return $false
                        }
	
                        # Check if current time falls within range
                        if ($currentTime -ge $rangeStart -and $currentTime -le $rangeEnd) {
                            $timecheckresult = $true
                        }
                        else {
                            $timecheckresult = $false
                        }
	                    if ($timecheckresult -eq $true) {
                            $scheduleMatched = $true
                            $matchedSchedule = $entry            
                        }
                    }
                    # End of time range check

                    # Enforce desired state for group resources based on previous time range check
                    if ($scheduleMatched) {
                        $DesiredState = "StoppedDeallocated"
                        $output = "[$($vm.Name)]: Current time [$currentTime] falls within the scheduled shutdown range [$matchedSchedule]"
                    }
                    else {
                        $DesiredState = "Started"
                        $output = "[$($vm.Name)]: Current time falls outside of all scheduled shutdown ranges."
                    }
                    Write-Output $output
                    
                    # Start or Stop the VM according to the desired state
                    $VirtualMachine = $vm
                    # Classic VM operations
                    if ($VirtualMachine.ResourceType -eq "Microsoft.ClassicCompute/virtualMachines") {
                        if ($DesiredState -eq "Started") {
                            if ($Simulate) {
                                Write-Output "[$($VirtualMachine.Name)]: SIMULATION -- Would have started VM. (No action taken)"
                            }
                            else {
                                Write-Output "[$($VirtualMachine.Name)]: Starting VM"
                                $VirtualMachine | Start-AzureVM
                            }
                        }	
                        elseif ($DesiredState -eq "StoppedDeallocated") {
                            if ($Simulate) {
                                Write-Output "[$($VirtualMachine.Name)]: SIMULATION -- Would have stopped VM. (No action taken)"
                            }
                            else {
                                Write-Output "[$($VirtualMachine.Name)]: Stopping VM"
                                $VirtualMachine | Stop-AzureVM -Force
                            }
                        }
                    }
                    #ARM VM operations
                    elseif ($VirtualMachine.ResourceType -eq "Microsoft.Compute/virtualMachines") {
                        if ($DesiredState -eq "Started") {
                            if ($Simulate) {
                                Write-Output "[$($VirtualMachine.Name)]: SIMULATION -- Would have been started VM. (No action taken)"
                            }
                            else {
                                Write-Output "[$($VirtualMachine.Name)]: Starting VM"
                                Start-AzureRmVM -ResourceGroupName $VirtualMachine.ResourceGroupName -Name $VirtualMachine.Name
                            }
                        }
                        elseif ($DesiredState -eq "StoppedDeallocated") {
                            if ($Simulate) {
                                Write-Output "[$($VirtualMachine.Name)]: SIMULATION -- Would have been stopped VM. (No action taken)"
                            }
                            else {
                                Write-Output "[$($VirtualMachine.Name)]: Stopping VM"
                                Stop-AzureRmVM -ResourceGroupName $VirtualMachine.ResourceGroupName -Name $VirtualMachine.Name -Force
                            }
                        }
                    }
                    else {
                        Write-Output "VM type not recognized: [$($VirtualMachine.ResourceType)]. Skipping."
                    }

                }
            }
            else {
                # No direct or inherited tag. Skip this VM.
                Write-Output "[$($vm.Name)]: Not tagged for shutdown directly or via membership in a tagged resource group. Skipping this VM."

            }	    
        }
        Write-Output "Finished processing virtual machine schedules"
    }
    catch {
        $errorMessage = $_.Exception.Message
        throw "Unexpected exception: $errorMessage"
    }
    finally {
        Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
    }

}
