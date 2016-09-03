function New-Minion {
    [cmdletBinding()]
    Param (
        [timespan]
        $TTL = [timespan]::MaxValue,
        
        [Guid]
        $MinionID = (New-Guid),
        
        [PSCustomObject[]]
        $InterfaceDefinitions = $null,
        
        [String]
        $DefaultMinionHandler = 'param ($Event); Write-Output $event',
        
        [PSModuleInfo[]]
        $RequiredModule = $null,
        
        [string[]]
        $RequiredModuleName = $null,
        
        [int]
        $LoopInterval = 1,
        
        [String[]]
        $LoopActions = @(  {$MinionPrivateData.INTERFACE_INSTANCES.Values | Receive-Job}.ToString()
                           #,{ }
                        ),
        
        [String[]]
        $StopConditions = @( { $MinionData.Uptime -ge $TTL}.ToString()
                             ,{ $MinionData.STATUS -eq "idle" -and $MinionData.Stop}.ToString()
                             ,{ if($runningJob = ($MinionPrivateData.INTERFACE_INSTANCES.Values | ? { $_.State -in @('Running')} )) { return $false } else {$true} }.ToString()
                           ),
        
        [String[]]
        $StopActions = @( {"Stopping Minion because $($MinionData.STOPPING_CONDITION)"}.ToString()
                          ,{Write-Output $MinionData}.ToString()
                          ,{$MinionPrivateData.INTERFACE_INSTANCES.Values | Receive-Job}.ToString()
                          #,{Write-Output $MinionPrivateData.INTERFACE_INSTANCES.Values}.ToString()
                        )
    )

    $MinionWorker = {
        [cmdletBinding()]
        Param(
            [PSObject]$Parameters
        )

        $MinionWorkerParams = @{}

        switch (($Parameters|Get-Member -MemberType NoteProperty).Name)
        {
            'MinionID'             { $MinionID = $Parameters.MinionID }
            'TTL'                  { $TTL = [timespan]::FromTicks($Parameters.TTL) }
            'InterfaceDefinitions' { $InterfaceDefinitions = $Parameters.InterfaceDefinitions }
            'DefaultMinionHandler' { $DefaultMinionHandler = $Parameters.DefaultMinionHandler}
            'RequiredModule'       { if ($Parameters.RequiredModule) { $Parameters.RequiredModule | Import-Module -ErrorAction Stop } }
            'RequiredModuleName'   { if ($Parameters.RequiredModuleName ) { $Parameters.RequiredModuleName | Import-Module -Name $_ -ErrorAction Stop } }
            'LoopInterval'         { $LoopInterval = $Parameters.LoopInterval }
            'LoopActions'          { $LoopActions = $Parameters.LoopActions }
            'StopConditions'       { $StopConditions = $Parameters.StopConditions}
            'StopActions'          { $StopActions = $Parameters.StopActions}
        }

        Function Set-MinionDataProperty 
        {
            Param(
                [string]$PropertyName,
                [Object]$value
            )
            if($MinionData | get-member -MemberType NoteProperty $PropertyName) 
            {
                $MinionData.($PropertyName) = $value
            }
            Else 
            {
                $MinionData | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $value
            }
        }

        $MinionPrivateData = [PSCustomOBject][Ordered]@{
            'SUBSCRIBER' = Register-EngineEvent -SourceIdentifier MINION -Action {
                            if ($event.MessageData.Handler) 
                            {
                                ([scriptblock]::Create($event.MessageData.Handler)).Invoke(@($event))
                            }
                            else 
                            {
                                 ([scriptblock]::Create($DefaultMinionHandler)).Invoke(@($event))
                            }
                          }
	        'INTERFACE_INSTANCES' = @{}
        }

        $MinionData = [PSCustomOBject][Ordered]@{
            PSTypeName = 'PSMinions.MinionData'
            'MINION_ID' = $MinionID
            'STOP' = $false
            'LOOP_INTERVAL' = [int]$LoopInterval
            'LOOP_ACTIONS' = $LoopActions
            'STOP_CONDITIONS' = $StopConditions
            'STOP_ACTIONS' = $StopActions
            'STATUS' = 'idle'
            'TTL' = $TTL
            'MINION_UPTIME' = [system.diagnostics.stopwatch]::startNew() 
            'INTERFACES' = @{}
        }

        Write-Verbose "Creating Interfaces"
        foreach ($interface in $InterfaceDefinitions)
        {
            Write-Verbose -Message "Creating interface $($interface.Name)"
            $InterfaceInstance = [scriptblock]::Create($Interface.InterfaceConstructor).Invoke()
            Write-Verbose "Instance: $InterfaceInstance"
            if (-not $Interface.InterfaceID) { $Interface | Add-Member -Name InterfaceID -Value (New-Guid) -MemberType NoteProperty}
            $null = $MinionPrivateData.INTERFACE_INSTANCES.add($Interface.InterfaceID,$InterfaceInstance)
            $null = $MinionData.INTERFACES.Add(
                $Interface.InterfaceID,
                [PSCustomObject][ordered]@{
                    PSTypeName              = 'PSMinions.InterfaceInstance'
                    'InterfaceName'         = $interface.InterfaceName
                    'InterfaceID'           = $Interface.InterfaceID
                    'InterfaceUptime'       = [system.diagnostics.stopwatch]::startNew()
                    'InterfaceDefinition'   = $interface
                }
            )
        }
        
        Write-Verbose "Entering Wait loop"
        do
        {
            Write-Verbose "Running Loop Actions"
            $MinionData.LOOP_ACTIONS.Foreach{ [ScriptBlock]::Create($_).Invoke() }
            Start-Sleep -Seconds $MinionData.LOOP_INTERVAL
        }
        while (-Not ($StoppingCondition = $MinionData.STOP_CONDITIONS | Where-Object { [ScriptBlock]::Create($_).Invoke() -eq $true }))
        Set-MinionDataProperty STOPPING_CONDITION $StoppingCondition

        Write-Verbose "Running Stop Actions"
        $MinionData.STOP_ACTIONS.Foreach{ [ScriptBlock]::Create($_).Invoke() }
    }.ToString()

    [PSCustomObject][ordered]@{
        PSTypeName           = 'PSMinions.MinionWorker'
        MinionID             = $MinionID
        MinionWorker         = $MinionWorker
        TTL                  = $TTL.Ticks
        InterfaceDefinitions = $InterfaceDefinitions
        DefaultMinionHandler = $DefaultMinionHandler
        RequiredModule       = $RequiredModule
        RequiredModuleName   = $RequiredModuleName
        LoopInterval         = $LoopInterval
        LoopActions          = $LoopActions
        StopConditions       = $StopConditions
        StopActions          = $StopActions
    } | Add-Member -Name StartAsJob -MemberType ScriptMethod -PassThru -Value {
        $scriptblock = [scriptblock]::Create($this.MinionWorker)
        Start-Job -ScriptBlock $scriptblock -Name $this.MinionID -ArgumentList $this
    }| Add-Member -Name Run -MemberType ScriptMethod -PassThru -Value {
        [scriptblock]::Create($this.MinionWorker).invoke($this)
    }
}