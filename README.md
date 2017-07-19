# StartStopVMbyTag
[MSFT] This powershell workflow script connects to Azure and start/stops parallely any VM (V1/V2) tagged with the corresponding status tag in the specified Azure subscription.   Tags are using the following format [autoShutdownSchedule:5pm -> 8am, Saturday, Sunday] and should correspond to the closing hours.
