$here = Split-Path -Parent $MyInvocation.MyCommand.Path 
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.' 
. "$here\..\..\Public\$sut"


Describe 'New-RabbitInterface' {

    Context 'New-RabbitInterface Called without Parameter returned object' {
        $RabbitInterface = New-RabbitInterface -ea SilentlyContinue

        It 'does not error generating a default RabbitInterface' {
            { New-RabbitInterface } | Should Not Throw
        }

        It 'creates a PSCustomObject of PSTypeName PSMinions.RabbitInterface' {
            $RabbitInterface.PSTypeNames[0] | Should be 'PSMinions.RabbitInterface'
        }

        It 'has a property RabbitMQServer of type String' {
            $RabbitInterface.RabbitMQServer  | Should Not BeNullOrEmpty
            $RabbitInterface.RabbitMQServer | Should BeOfType [String]
        }

        It 'has a property InterfaceId of type Guid' {
            $RabbitInterface.InterfaceId | Should Not BeNullOrEmpty
            $RabbitInterface.InterfaceId | Should BeOfType [Guid]
        }
        
        It 'has a property InterfaceName of type String defaulting to InterfaceId' {
            $RabbitInterface.InterfaceName | Should Not BeNullOrEmpty
            $RabbitInterface.InterfaceName | Should BeOfType [String]
            $RabbitInterface.InterfaceName | Should be $RabbitInterface.InterfaceId
        }

        It 'has a propety InterfaceConstructor of type String' {
            $RabbitInterface.InterfaceConstructor | Should not BeNullOrEmpty
            $RabbitInterface.InterfaceConstructor | should BeOfType [String]
        }

        It 'has a property PrefetchSize of type uint32 defaulting to 0' {
            $RabbitInterface.PrefetchSize | Should not BeNullOrEmpty
            $RabbitInterface.PrefetchSize | Should BeOfType [uint32]
            $RabbitInterface.PrefetchSize | Should be 0
        }

        It 'has a property PrefetchCount of Type uint16 defaulting to 1' {
            $RabbitInterface.PrefetchCount | Should not BeNullOrEmpty
            $RabbitInterface.PrefetchCount | Should BeOfType [uint16]
            $RabbitInterface.PrefetchCount | Should be 1
        }

        It 'has a property global of type [bool] defaulting to $false' {
            $RabbitInterface.global | Should not BeNullOrEmpty
            $RabbitInterface.global | Should BeOfType [bool]
            $RabbitInterface.global | Should be $false
        }

        It 'has a property key of type [string[]] defaulting to @("#")' {
            $RabbitInterface.key | Should not BeNullOrEmpty
            ,$RabbitInterface.key | Should BeOfType [string[]]
            ,$RabbitInterface.key | Should be @("#")
        }

        It 'has a property Exchange of type [string] defaulting to "celery"' {
            $RabbitInterface.Exchange | Should not BeNullOrEmpty
            $RabbitInterface.Exchange | Should BeOfType [string]
            $RabbitInterface.Exchange | Should be 'celery'
        }

        It 'has a property QueueName of type [string] defaulting to celery' {
            $RabbitInterface.QueueName | Should not BeNullOrEmpty
            $RabbitInterface.QueueName | Should BeOfType [string]
            $RabbitInterface.QueueName | Should be 'celery'
        }

        It 'has a property Autodelete of type [bool] defaulting to false' {
            $RabbitInterface.Autodelete | Should not BeNullOrEmpty
            $RabbitInterface.Autodelete | Should BeOfType [bool]
            $RabbitInterface.Autodelete | Should be $false
        }

        It 'has a property RequireAck of type [bool] defaulting to false' {
            $RabbitInterface.RequireAck | Should not BeNullOrEmpty
            $RabbitInterface.RequireAck | Should BeOfType [bool]
            $RabbitInterface.RequireAck | Should be $false
        }

        It 'has a property Durable of type [bool] default to false' {
            $RabbitInterface.Durable | Should not BeNullOrEmpty
            $RabbitInterface.Durable | Should BeOfType [bool]
            $RabbitInterface.Durable | Should be $false
        }

        It 'has a property ActionScriptblock defaulting to null' {
            $RabbitInterface.ActionScriptblock | Should BeNullOrEmpty
        }

        It 'has a property ActionFile defaulting to null' {
            $RabbitInterface.ActionFile | Should BeNullOrEmpty
        }

        It 'has a property IncludeEnvelope of type [bool] defaulting to false' {
            $RabbitInterface.IncludeEnvelope | Should not BeNullOrEmpty
            $RabbitInterface.IncludeEnvelope | Should BeOfType [bool]
            $RabbitInterface.IncludeEnvelope | Should be $false
        }
    }

    Context 'Creating Custom RabbitInterface' {
        It 'Should do something' -pending {
            $true | should be $true 
        } 
    }
}