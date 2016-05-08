Import-Module -Force RabbitMQTools
Import-Module -Force psRabbitMQ

if(-not $cred) {
    #$cred = (Get-Credential)
}

$MQconf = @{
    'BaseURI' = 'http://rabbitmq.vas.inth8:15672'
    'Credential' = $cred
}

#Register-RabbitMQServer @MQconf

#Per Node
##Create Communication queue
##Bind communication queue to COMMS Exchange
##GET other nodes config
##Listen to WorkeQueue with fair dispatch


$Minions = [PSCustomObject][ordered]@{
    'version' = [version]'0.1.0.0'
    'rabbitmq' = [PSCustomObject][ordered]@{
        'server' = [PSCustomObject][ordered]@{
            'Ssl' = 'Tls12'
            'ComputerName' = 'rabbitmq.vas.inth8'
            'BaseUri' = 'http://rabbitmq.vas.inth8:15672'
            'credential' = [PSCustomObject][ordered]@{
                'username' = 'guest'
                'password' = 'guest'
            }
        }
        'exchanges' = @(
            [PSCustomObject][ordered]@{
                'name' = 'WORK'
                'vhost' = '/'
                'type' = 'topic' #direct,fanout,headers
                'durable' = $true
                'AutoDelete' = $false
                'internal'=$false
                'arguments'=''
            }
            [PSCustomObject][ordered]@{
                'Name' = 'COMS'
                'vhost' = '/'
                'type' = 'topic' #direct,fanout,headers
                'durable' = $true
                'AutoDelete' = $false
                'internal'=$false
                'arguments'=''
            }
        )
        'queues' = @(
            [PSCustomObject][ordered]@{
                'name'=  'workqueue'
                'vhost'=  '/'
                'durable'=  $true
                'auto_delete'=  $false #delete the queue when not subscribed
                'arguments'=  ''
             }
        )
        'bindings' = @(
            [PSCustomObject][ordered]@{
                'source'=  'WORK'
                'vhost'=  '/'
                'destination'=  'workqueue'
                'destination_type'=  'queue'
                'routing_key'=  '*'
                'arguments'=  ''
            }
        )
    }
    'Minions' = @(
        [PSCustomObject][ordered]@{
            'ArgumentList' = @( [PSCustomObject][ordered]@{
                'log4psConfig' = 'C:\log4psconfig.json'
            })
            'ComputerName' = @('localhost')
            'WorkerPerComputer' = 1
            'TTL' = '1:01:00:10.250'
            'interfaces' = @(
                [PSCustomObject][ordered]@{
                    'name' = 'COMSInterface'
                    'prefetchSize' = 0
                    'prefetchCount' =5
                    'global' = $false
                    'key' = @('','role1.MULTICAST','BROADCAST') #the queuename will be appended if the last char is a . or if empty
                    'exchange' = 'COMS'
                    'autodelete' = $true
                    'requireack' = $false
                    'durable' = $True
                    'action' = @{
                        'type' = 'script'
                        'path' = 'C:\dev\psworker\MinionDefinitions\Minion1\MinionCommunications.ps1'
                    }
                }, 
                [PSCustomObject][ordered]@{
                    'name' = 'WORKInterface' 
                    'prefetchSize' = 0
                    'prefetchCount' =1
                    'global' = $false
                    'key'='#'
                    'exchange' = 'WORK'
                    'queuename' = 'workqueue'
                    'requireack' = $true
                    'durable' = $True
                    'action' = @{
                        'type' = 'script';
                        'path' = 'C:\dev\psworker\MinionDefinitions\Minion1\MinionWorkHandler.ps1'
                    }
                }
            )

        }
    )
    
}


#Create Exchange
#Create Queues
#Create Binding
#Register-RabbitMqEvent for each minion
if($Minions.rabbitmq.server.credential) {
    $secpasswd = ConvertTo-SecureString $Minions.rabbitmq.server.credential.password -AsPlainText -Force
    $RabbitMQCredential = New-Object System.Management.Automation.PSCredential ($Minions.rabbitmq.server.credential.username, $secpasswd)
}
Register-RabbitMQServer -BaseUri $Minions.rabbitmq.server.BaseUri

foreach ($exchange in $Minions.rabbitmq.exchanges) {

    Add-RabbitMQExchange -Name $exchange.name -Type $exchange.type -Durable:$exchange.durable -AutoDelete:$exchange.AutoDelete -VirtualHost $exchange.vhost -BaseUri $Minions.rabbitmq.server.BaseUri -Credentials $RabbitMQCredential -Verbose
    
}
foreach ($queue in $Minions.rabbitmq.queues) {
    Add-RabbitMQQueue -Name $queue.name -VirtualHost $queue.vhost -Durable:$queue.durable -AutoDelete:$queue.autodelete -BaseUri $minions.rabbitmq.server.BaseUri -Credentials $RabbitMQCredential
}
foreach ($binding in $Minions.rabbitmq.bindings) {
    Add-RabbitMQQueueBinding -Name $binding.destination -ExchangeName $binding.source -RoutingKey $binding.routing_key -VirtualHost $binding.vhost -BaseUri $Minions.rabbitmq.server.BaseUri -Credentials $RabbitMQCredential
}

foreach ($MinionType in $Minions.Minions) {
    1..$MinionType.WorkerPerComputer | ForEach-Object {

       $guid = New-Guid

       #Region WORKER BODY
        $MinionWorker =  {
            Import-Module psRabbitMQ

            $listeners = @()

            if($MinionType.TTL) { $TTL = [timespan]$MinionType.TTL}
            else { $TTL = [timespan]::new(0) } 

            $MinionData = [PSCustomObject]@{
                'ID' = $using:guid
                'STOP' = $false #If STOP AND WORK_STATUS idle, then gracefully stop MINION
                'WORK_STATUS' = 'idle'
                'TTL' = $TTL.ToString()
                'Interfaces' = @{}
            }
            #helper to allow set new properties on object
            Function Set-MinionDataProperty {
                Param(
                    [string]$PropertyName,
                    [Object]$value
                )
                if($MinionData | get-member -MemberType NoteProperty $PropertyName) {
                    $MinionData.($PropertyName) = $value
                }
                Else {
                    $MinionData | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $value
                }
            }

            $subscriber = Register-EngineEvent -SourceIdentifier MINION -Action {
                            ([scriptblock]::Create($event.MessageData.Handler)).Invoke(@($event))
                          }

            foreach($interface in $using:MinionType.interfaces){
                
                $ifaceGuid = New-Guid
                $interface.key = $interface.key | % { if($_ -match '\.$' -or $_ -eq '') { return ($_ + $using:guid) } else { return $_ } }
            
                $queuename = $interface.queuename
                #if the QueueName is empty use the Minion GUID as queuename
                if(-not $queuename) { $queuename = $using:guid }

                $action = $null
                switch($interface.action.type) {
                    'script' { $action = [scriptblock]::Create("
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
                                'interfaceid' = '$ifaceGuid'
                            })
                        }
                        #Processing Starts
                        Invoke-MinionAction -action { Set-MinionDataProperty -PropertyName 'LastMessage' -Value (Get-Date); } #-MessageData `$_
                        & $($interface.action.path) `$_ $using:guid '$ifaceGuid'
                        
                        ") }
                    'scriptblock' { $action = [scriptblock]::Create($interface.action.scriptblock) }
                }
                if(-not ($durable = $interface.durable)) {
                    $durable = $false
                }
                [bool]::TryParse($interface.durable,[ref]$durable) | Out-Null
                
                $RMQParams  = @{
                    ComputerName= $using:Minions.rabbitmq.server.ComputerName
                    Exchange = $interface.exchange 
                    Key = $interface.key
                    QueueName= $queuename 
                    Durable = [bool]$durable 
                    Action=$action
                    AutoDelete=[bool]$interface.autodelete
                    RequireAck= [bool]$interface.requireack
                    Credential=$using:RabbitMQCredential
                    prefetchSize=[int]$interface.prefetchSize
                    prefetchCount=[int]$interface.prefetchCount
                    global=$interface.global
                }
                $job = Register-RabbitMqEvent @RMQParams
                $listeners += $job
                $MinionData.Interfaces.add($ifaceGuid.ToString(),([PSCustomObject]@{
                    'InterfaceName' = $interface.name
                    'JobInstanceID' = $job.InstanceId
                    'StartTime' = $job.PSBeginTime
                    'InterfaceDefinition' = $interface
                }))
                
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $timeout = New-TimeSpan -Seconds $using:timeoutSec
            while((Get-Job) -or ($stopwatch.Elapsed -lt $TTL) -or ($MinionData.WORK_STATUS -ne 'busy' -and $MinionData.STOP) ) {
                $listeners | Receive-Job
                $subscriber | Receive-Job
                Wait-Event -Timeout 1
            }
        }
       #Endregion
        Start-Job -Name $guid -ScriptBlock $MinionWorker

    }
}
#region send messages to work Exchange
Wait-Event -Timeout 3

#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 1 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 2 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 3 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 4 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 5 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 6 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 7 WORK!';
#Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject 'Hello 8 WORK!';
#endregion

Wait-Event -Timeout 2

#
#Send-RabbitMqMessage -Exchange COMS -Key 'BROADCAST' -InputObject '{"Action":"STOP"}';
#Send-RabbitMqMessage -Exchange COMS -Key 'role1.MULTICAST' -InputObject 'MULTICAST';
#Send-RabbitMqMessage -Exchange COMS -Key $guid -InputObject '{"Action":"QUERYMINIONSTATE"}';
#Send-RabbitMqMessage -Exchange COMS -Key $guid -InputObject '{"Action":"QUERYJOB"}';
#Send-RabbitMqMessage -Exchange COMS -Key $guid -InputObject '{"Action":"STOP"}';
#Send-RabbitMqMessage -Exchange COMS -Key $guid -InputObject '{"Action":"KILL"}';
Start-Sleep -Seconds 3

Get-Content .\outWorker_* -ErrorAction SilentlyContinue
Get-Content .\outComms_* -ErrorAction SilentlyContinue
Get-Job | Receive-Job

break

Remove-Item .\outWorker_* -ErrorAction SilentlyContinue
Remove-Item .\outComms_* -ErrorAction SilentlyContinue
Get-Job | Remove-Job -Force
Clear-Host