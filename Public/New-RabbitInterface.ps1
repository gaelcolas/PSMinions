
Function New-RabbitInterface {
    [cmdletBinding()]
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
        $InterfaceName = ($InterfaceID),
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
        $QueueName = $InterfaceID,
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
        $ActionScriptBlock = ("Register-EngineEvent -SourceIdentifier MINION -Forward;`
                                `$null = New-Event -SourceIdentifier MINION -MessageData ([PSCustomObject]@{`
                                    'message' = `$_;`
                                    'interfaceid' = '$InterfaceID';`
                                })"),
        [Parameter(ParameterSetName = 'ActionFile',ValueFromPipelineByPropertyName = $true)]
        [System.IO.FileInfo]
        $ActionFile,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [pscredential]
        $RabbitMQCredential,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $IncludeEnvelope
    )

    if (!$PSBoundParameters.keys.Contains('InterfaceName'))
    {
        $InterfaceName = $InterfaceId
    }
    if (!$PSBoundParameters.keys.Contains('QueueName'))
    {
        $QueueName = $InterfaceId
    }

    $InterfaceConstructor = {
        Param (
            [PSCustomObject]
            $Parameters
        )
        $RMQParams  = @{} 

        switch (($Parameters|Get-Member -MemberType NoteProperty).Name)
        {
        'RabbitMQServer'    { $RMQParams['ComputerName']  = [string]$Parameters.'RabbitMQServer'}
        'InterfaceId'       { $InterfaceId                = [string]$Parameters.'InterfaceId';  }
        'Interfacename'     { $InterfaceName              = [string]$Parameters.'Interfacename';        }
        'PrefetchSize'      { $RMQParams['PrefetchSize']  = [uint32]$Parameters.'PrefetchSize'  }
        'PrefetchCount'     { $RMQParams['PrefetchCount'] = [uint16]$Parameters.'PrefetchCount' }
        'global'            { $RMQParams['global']        = [bool]$Parameters.global            }
        'key'               { $RMQParams['key']           = [string[]]$Parameters.'key'         } 
        'Exchange'          { $RMQParams['Exchange']      = [string]$Parameters.'Exchange'      }
        'QueueName'         { $RMQParams['QueueName']     = [string]$Parameters.'QueueName'     }
        'AutoDelete'        { $RMQParams['AutoDelete']    = [bool]$Parameters.'AutoDelete'      }
        'RequireAck'        { $RMQParams['RequireAck']    = [bool]$Parameters.'RequireAck'      }
        'Durable'           { $RMQParams['Durable']       = [bool]$Parameters.'Durable'         }
        'ActionScriptBlock' {
                                 if (!( $ActionScriptBlock = $Parameters.ActionScriptBlock))
                                 {
                                    Write-Verbose "No scriptblock defined for event action."
                                 }
                            }
        'ActionFile'        {   if (!($ActionFile = [string]$Parameters.ActionFile) )
                                { Write-Verbose "No file defined for event action." }
                            }
        'RabbitMQCredential'{   if (!$Parameters.RabbitMQCredential) { continue }
                                $PlainPassword = $Parameters.RabbitMQCredential.password
                                $SecurePassword = $PlainPassword | ConvertTo-SecureString -AsPlainText -Force
                                $UserName =  $Parameters.RabbitMQCredential.username
                                $RMQParams['Credential'] = New-Object System.Management.Automation.PSCredential `
                                     -ArgumentList $UserName, $SecurePassword
                            }
        'IncludeEnvelope'   { $RMQParams['IncludeEnvelope'] = [bool]$Parameters.'IncludeEnvelope'}
        }

        if ([string]::IsNullOrEmpty($Parameters.QueueName))
        {
            $RMQParams['QueueName'] = $MinionData.MinionId.ToString()
        }
        
        #If a Key ends by . or is null/empty, replace by 'unchangedpart.<InterfaceID>' or '<interfaceID>'
        Write-Verbose "Processing the Keys to add $InterfaceID where needed"
        if (-not $RMQParams['key']) 
        {
            $RMQParams['key'] = @($InterfaceId) 
        }
        else
        {
            $routing_key = switch -regex ($RMQParams['key'] ) {
                    "\.$"   {
                                Write-Verbose "Appending the InterfaceID to $_"
                                $_ + $InterfaceId 
                             }
                    "^$"     {
                                Write-Verbose "Replacing with $InterfaceID"
                                $InterfaceId 
                             }
                    Default {Write-verbose "Key $_ unchanged"; $_ }
                }
            $RMQParams['key'] = $routing_key
        }
        
        if ($ActionFile)
        {
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
                    Invoke-MinionAction -action { 
                                Set-MinionDataProperty -PropertyName 'LastMessage' -Value (Get-Date); 
                                }
                    #Write-Verbose `$_
                    #Write-Verbose $InterfaceID
                    & '$ActionFile' `$_ '`$Miniondata.minionID' '$InterfaceId' 
                    ")
        }
        elseif ($ActionScriptBlock)
        {
            $RMQParams['Action'] = [scriptblock]::Create($ActionScriptBlock)
        }
        

        return Register-RabbitMqEvent @RMQParams
    }.ToString()

    if ($RabbitMQCredential)
    {
       $RMQCredential = ([PSCustomObject]@{
                                    PSTypeName = 'Json.Serializable.unsecure.Credentials'
                                    'username' = $RabbitMQCredential.UserName
                                    'password' = $RabbitMQCredential.GetNetworkCredential().Password
                             })
    }
    

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
        'RabbitMQCredential'   = $RMQCredential
        'IncludeEnvelope'      = [bool]$IncludeEnvelope
    } | Add-Member -Name Start -MemberType ScriptMethod -PassThru -Value {
        [scriptblock]::create($this.InterfaceConstructor).Invoke($this)
    }
}
