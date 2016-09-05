$here = Split-Path -Parent $MyInvocation.MyCommand.Path 
#this is still a draft

if (!$RabbitMQServer)
{
    $RabbitMQServer = 'localhost'
}
if (!$RabbitMQCredential)
{
    $PlainPassword          = "guest"
    $UserName               = "guest"
    $SecurePassword         = $PlainPassword | ConvertTo-SecureString -AsPlainText -Force
    $RabbitMQCredential = (New-Object System.Management.Automation.PSCredential -ArgumentList $UserName,$SecurePassword)
}

$RMQServer = @{
    'Credential' = $RabbitMQCredential
    'baseuri' = "http://$($RabbitMQServer):15672"
}

$RMQObjectConfiguration = [PSCustomObject]@{
    'exchanges' = @(
        [PSCustomObject][ordered]@{
            'name' = 'WORK'
            'vhost' = '/'
            'type' = 'topic' #direct,fanout,headers
            'durable' = $true
            'AutoDelete' = $false
            'internal'=$false
        },
        [PSCustomObject][ordered]@{
            'Name' = 'COMS'
            'vhost' = '/'
            'type' = 'topic' #direct,fanout,headers
            'durable' = $true
            'AutoDelete' = $false
            'internal'=$false
        },
        [PSCustomObject][ordered]@{
            'Name' = 'PINGPONG'
            'vhost' = '/'
            'type' = 'topic' #direct,fanout,headers
            'durable' = $true
            'AutoDelete' = $false
            'internal'=$false
        }
    )
    'queues' = @(
        [PSCustomObject][ordered]@{
            'name'=  'workqueue'
            'vhost'=  '/'
            'durable'=  $true
            'auto_delete'=  $false #delete the queue when not subscribed
            },
            [PSCustomObject][ordered]@{
            'name'=  'pingpong'
            'vhost'=  '/'
            'durable'=  $true
            'auto_delete'=  $false #delete the queue when not subscribed
            }
    )
    'bindings' = @(
        [PSCustomObject][ordered]@{
            'source'=  'WORK'
            'vhost'=  '/'
            'destination'=  'workqueue'
            'destination_type'=  'queue'
            'routing_key'=  '*'
        },
        [PSCustomObject][ordered]@{
            'source'=  'PINGPONG'
            'vhost'=  '/'
            'destination'=  'pingpong'
            'destination_type'=  'queue'
            'routing_key'=  '*'
        }
    )
}

Describe 'Ensure the RabbitMQ is setup for integration Tests' {
    Import-Module RabbitMQTools,PSRabbitMQ
    $RMQObjectConfiguration.Exchanges | Add-RabbitMQExchange @RMQServer
    $RMQObjectConfiguration.queues | Add-RabbitMQQueue @RMQServer
    $RMQObjectConfiguration.bindings | Add-RabbitMQQueueBinding @RMQServer

    Context 'Doing a Ping/Pong interface' {
        $PingListernerInterface = [PSCustomObject][ordered]@{
                    'name' = 'PONG'
                    'InterfaceID' = '18a3fd00-bfeb-4a94-9aa8-b74ab3270511'
                    'prefetchSize' = 0
                    'prefetchCount' =1
                    'global' = $false
                    'key' = @('','PING.MULTICAST','BROADCAST') #the queuename will be appended if the last char is a . or if empty
                    'exchange' = 'PINGPONG'
                    'autodelete' = $false
                    'requireack' = $true
                    'durable' = $True
                    #'actionfile' = 'C:\src\psMinions\MinionComsInterface.ps1'
                    'actionScriptBlock' = " Write-host 'Sending message to PINGPONG: `$_'`
                                            Send-RabbitMqMessage -ComputerName $RabbitMQServer -Exchange PINGPONG -Key 'PONG.MULTICAST' -InputObject ('PONG')`
                                           "
                    'RabbitMQCredential' = $RabbitMQCredential
                    'ComputerName' = $RabbitMQServer
                } | New-RabbitInterface
        $PingListenerJob = $PingListernerInterface.Start()
        $PongListenerJob = Start-Job -ScriptBlock { Wait-RabbitMqMessage -ComputerName $using:RabbitMQServer -Exchange PINGPONG -QueueName (New-guid) -Timeout 6 -Key 'PONG.MULTICAST' -AutoDelete $true}
        while ($PongListenerJob.State -notin 'failed','running','completed') { Sleep -seconds 1 -Verbose }
        
        do {
            sleep -Milliseconds 700
            Send-RabbitMqMessage -ComputerName $RabbitMQServer -Exchange PINGPONG -Key 'PING.MULTICAST' -InputObject 'PINGGGGGGG' -Persistent
        }
        while ($PongListenerJob.State -eq 'Running')
        

        $result = ($PongListenerJob | Receive-Job -Keep)

        It 'The interface return PONG when PING is sent' {
            $result | Should not beNullOrEmpty
        }

        $PongListenerJob,$PingListenerJob | Remove-job -Force
    }
}
 



<#
$if = [PSCustomObject][ordered]@{
                    'name' = 'COMSInterface'
                    'InterfaceID' = '18a3fd00-bfeb-4a94-9aa8-b74ab3270511'
                    'prefetchSize' = 0
                    'prefetchCount' =5
                    'global' = $false
                    'key' = @('','role1.MULTICAST','BROADCAST') #the queuename will be appended if the last char is a . or if empty
                    'exchange' = 'COMS'
                    'autodelete' = $true
                    'requireack' = $false
                    'durable' = $True
                    #'actionfile' = 'C:\src\psMinions\MinionComsInterface.ps1'
                    'RabbitMQCredential' = $RabbitMQCredential
                    'ComputerName' = $RabbitMQServer
                } | New-RabbitInterface

$job = $if.Start()
Register-EngineEvent -SourceIdentifier MINION -Action { $event | ConvertTo-Json | Write-Host }
Send-RabbitMqMessage -SerializeAs application/json -Exchange COMS -Key '18a3fd00-bfeb-4a94-9aa8-b74ab3270511' -InputObject 'Hello 1 WORK!' -ComputerName 10.111.111.116

#>