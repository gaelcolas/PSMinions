
Function New-RabbitInterface {
    [cmdletBinding(DefaultParameterSetName='ActionFile')]
    [OutputType([PSCustomObject])]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Guid]
        [ValidateNotNullOrEmpty()]
        $InterfaceId = (New-Guid),
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('ComputerName')]
        [String]
        $RabbitMQServer = 'localhost',
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $InterfaceName = $InterfaceID.ToString(),
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [uint32]
        $PrefetchSize = 0,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [uint16]
        $PrefetchCount = 1,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $global,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $key = @('#'),
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $Exchange = 'celery',
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $QueueName = 'celery',
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $AutoDelete,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $RequireAck,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $Durable,
        [Parameter(ParameterSetName = 'ActionScriptBlock',ValueFromPipelineByPropertyName = $true)]
        [String]
        $ActionScriptBlock,
        [Parameter(ParameterSetName = 'ActionFile',ValueFromPipelineByPropertyName = $true)]
        [System.IO.FileInfo]
        $ActionFile,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [PSCredential]
        $RabbitMQCredential,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $IncludeEnvelope
    )

    $InterfaceConstructor = {
        Param (
            [PSCustomObject]
            $Parameters
        )
        $RMQParams  = @{} 

        switch (($Parameters|Get-Member -MemberType NoteProperty).Name)
        {
        'RabbitMQServer'    { $RMQParams['ComputerName'] = [string]$Parameters.'RabbitMQServer'}
        'InterfaceId'       { $InterfaceId = $Parameters['InterfaceId']}
        'PrefetchSize'      { $RMQParams['PrefetchSize'] = [uint32]$Parameters.'PrefetchSize'}
        'PrefetchCount'     { $RMQParams['PrefetchCount'] = [uint16]$Parameters.'PrefetchCount'}
        'global'            { $RMQParams['global'] = [bool]$Parameters.global}
        'key'               { $RMQParams['key'] = [string[]]$Parameters.'key'}
        'Exchange'          { $RMQParams['Exchange'] = [string]$Parameters.'Exchange'}
        'QueueName'         { $RMQParams['QueueName'] = [string]$Parameters.'QueueName'}
        'AutoDelete'        { $RMQParams['AutoDelete'] = [bool]$Parameters.'AutoDelete'}
        'RequireAck'        { $RMQParams['RequireAck'] = [bool]$Parameters.'RequireAck'}
        'Durable'           { $RMQParams['Durable'] = [bool]$Parameters.'Durable'}
        #'ActionScriptBlock' { $RMQParams['ActionScriptBlock'] = $Parameters['ActionScriptBlock']}
        'ActionFile'        { $ActionFile = $Parameters.'ActionFile'.FullName}
        'RabbitMQCredential'{ $RMQParams['Credential'] = [PSCredential]$Parameters.'RabbitMQCredential'}
        'IncludeEnvelope'   { $RMQParams['IncludeEnvelope'] = [bool]$Parameters.'IncludeEnvelope'}
        }

        if ([string]::IsNullOrEmpty($Parameters.QueueName))
        {
            $RMQParams['QueueName'] = $MinionData.MinionId.ToString()
        }
        
        #If a Key ends by . or is null/empty, replace by 'unchangedpart.<InterfaceID>' or '<interfaceID>'
        if (-not $RMQParams['key']) 
        {
            $RMQParams['key'] = @($InterfaceId) 
        }
        else
        {
            $routing_key = switch -regex ($RMQParams['key'] ) {
                    "\.$"   { $_ + $InterfaceId }
                    "^$"      { $InterfaceId }
                    Default { $_ }
                }
            $RMQParams['key'] = $routing_key
        }
        

        $RMQParams['Action'] = [scriptblock]::Create("
                    Register-EngineEvent -SourceIdentifier MINION -Forward;
                    Function Invoke-MinionAction {
                        param(
                            [scriptblock]
                            `$action,
                            [PSObject]
                            `$MessageData
                        )
                                
                        `$null = New-Event -SourceIdentifier MINION -MessageData ([PSCustomObject]@{
                            'Handler' = `$action
                            'message' = `$MessageData
                            'interfaceid' = '$InterfaceID'
                        })
                    }
                    #Processing Starts
                    Invoke-MinionAction -action { Set-MinionDataProperty -PropertyName 'LastMessage' -Value (Get-Date); }
                    #Write-Verbose `$_
                    #Write-Verbose $InterfaceID
                    & '$ActionFile' `$_ '`$Miniondata.minionID' '$InterfaceId' 
                    ")

        return Register-RabbitMqEvent @RMQParams
    }.ToString()

     return [PSCustomObject][Ordered]@{
        PSTypeName             = 'PSMinions.RabbitInterface'
        'RabbitMQServer'       = $RabbitMQServer
        'InterfaceId'          = $InterfaceId
        'InterfaceName'        = $InterfaceName
        'InterfaceConstructor' = $InterfaceConstructor
        'PrefetchSize'         = $PrefetchSize
        'PrefetchCount'        = $PrefetchCount
        'global'               = [bool]$global
        'key'                  = $key
        'Exchange'             = $Exchange
        'QueueName'            = $QueueName
        'Autodelete'           = [bool]$AutoDelete
        'RequireAck'           = [bool]$RequireAck
        'Durable'              = [bool]$Durable
        'ActionScriptBlock'    = $ActionScriptBlock
        'ActionFile'           = $ActionFile.FullName
        'RabbitMQCredential'   = $RabbitMQCredential
        'IncludeEnvelope'      = [bool]$IncludeEnvelope
    } | Add-Member -Name Start -MemberType ScriptMethod -PassThru -Value {
        [scriptblock]::Create($this.InterfaceConstructor).Invoke()
    }
}

break
#$gues = (get-Credential)
$definition = [PSCustomObject][ordered]@{
                    'ComputerName' = '10.111.111.116'
                    'interfaceId' = (New-Guid)
                    'InterfaceName' = 'COMSInterface'
                    'prefetchSize' = 0
                    'prefetchCount' =1
                    'global' = $false
                    'key' = @('#','role1.MULTICAST','BROADCAST') #the queuename will be appended if the last char is a . or if empty
                    'exchange' = 'WORK'
                    'QueueName' = 'workqueue'
                    'autodelete' = $false
                    'requireack' = $true
                    'durable' = $True
                    'ActionFile' = 'C:\src\psMinions\MinionComsInterface.ps1'
                    'RabbitMQCredential' = $gues
                } | New-RabbitInterface

#$iface = [scriptblock]::Create($definition.InterfaceConstructor).Invoke($definition)
#$iface | Wait-Job | Receive-Job
#
#$iface | Remove-Job