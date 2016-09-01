$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\..\..\Public\$sut"

Describe 'New-Minion' {

    Context 'New-Minion Called without Parameter' {
        $Minion = New-Minion
    
        It 'creates a PSCustomObject of PSTypeName PSMinions.MinionWorker' {
            $Minion.PSTypeNames[0] | Should Be 'PSMinions.MinionWorker'
        }

        It 'has a MinionID property of Type Guid' {
            $Minion.MinionID | Should Not BeNullOrEmpty
            $Minion.MinionID | Should BeOfType [Guid]
        }

        It 'has a MinionWorker property of type String' {
            $Minion.MinionWorker | Should Not BeNullOrEmpty
            $Minion.MinionWorker | Should BeOfType [string]
        }

        It 'has a TTL property of type int64' {
            $Minion.TTL | Should not BeNullOrEmpty
            $Minion.TTL | Should BeOfType [int64]
        }

        It 'has an empty InterfaceDefinitions property when called without parameter' {
            $Minion.InterfaceDefinitions | Should Be $null
        }

        It 'has a DefaultMinionHandler of type String' {
            $Minion.DefaultMinionHandler | Should Not BeNullOrEmpty
            $Minion.DefaultMinionHandler | Should BeOfType [string]
        }

        It 'has a RequiredModule Property null' {
            $Minion.RequiredModule | Should be $null
        }

        It 'has a RequiredModuleName Property null' {
            $Minion.RequiredModuleName | Should be $null
        }

        It 'has a LoopInterval property of type int defaulting to 1' {
            $Minion.LoopInterval | Should be 1
            $Minion.LoopInterval | Should BeOfType [int]
        }

        It 'has a LoopActions property of type [string[]] with 1 default' {
            $Minion.LoopActions.Count | Should be 1
            $Minion.LoopActions[0]    | Should be {$MinionPrivateData.INTERFACE_INSTANCES.Values | Receive-Job}.ToString()
            ,$Minion.LoopActions       | Should BeOfType [string[]]
        }

        It 'has a StopConditions property of Type [string[]] with 3 defaults' {
            $Minion.StopConditions.Count | Should be 3
            $Minion.StopConditions       | Should be @( { $MinionData.Uptime -ge $TTL}.ToString()
                             ,{ $MinionData.STATUS -eq "idle" -and $MinionData.Stop}.ToString()
                             ,{ if($runningJob = ($MinionPrivateData.INTERFACE_INSTANCES.Values | ? { $_.State -in @('Running')} )) { return $false } else {$true} }.ToString()
                           )
             ,$Minion.StopConditions     | Should BeOfType [string[]]
        }

        It 'has a StopActions property of Type [String[]] with 3 defaults' {
            $Minion.StopActions.Count | Should be 3
            $Minion.StopActions | Should be @( {"Stopping Minion because $($MinionData.STOPPING_CONDITION)"}.ToString()
                          ,{Write-Output $MinionData}.ToString()
                          ,{$MinionPrivateData.INTERFACE_INSTANCES.Values | Receive-Job}.ToString()
                        )
            ,$Minion.StopActions | Should BeOfType [String[]]
        }

        It 'has a .Run() method to execute the worker and return the PSMinions.MinionData object' {
            {$Minion.Run() } | Should not Throw
            #$Minion.Run().PSTypeNames[0] | Should be 'PSMinions.MinionData'
        }

        It 'has a .StartAsJob() method that execute the worker as a Job' {
            { $Minion.StartAsJob() } | Should not Throw
            $MinionJob =  $Minion.StartAsJob()

            $MinionJob     | Should BeOfType [System.Management.Automation.Job]
            {$MinionJob     | Wait-Job | Receive-Job} | Should not throw
        }

    }

    Context 'New-Minion Called without a simple interface' {
        $InterfaceDefinition = @([PSCustomObject][Ordered]@{
            'InterfaceConstructor' = {Start-Job -Name 'IF01' -ScriptBlock { Write-Output "Interface writing to output"; }}.ToString()
            'Name' = 'IF01'
        })
        $Minion = New-Minion -InterfaceDefinitions @($InterfaceDefinition)
        it 'Run the interface as sub jobs and return the output after execution' {
            ,$Minion.Run() | Should match 'Interface writing to output'
        }

        it 'Run the Minion worker after JSON Serialization/de-serialization' {
        
        }
    }
}



break


$InterfaceDefinition = @([PSCustomObject][Ordered]@{
    'InterfaceConstructor' = {Start-Job -Name 'IF01' -ScriptBlock {$a = 1; do { Write-Host "a = $a"; Start-Sleep -Seconds 1; $a+=1} while ($a -le 5); Write-Host "Closing Interface"; sleep -seconds 5; }}.ToString()
    'Name' = 'IF01'
})

$InterfaceDefinition2 = @([PSCustomObject][Ordered]@{
    'InterfaceConstructor' = {Start-Job -Name 'IF02' -ScriptBlock {$b = 1; do { Write-Host "b = $b"; Start-Sleep -Seconds 2; $b+=1} while ($b -le 5); Write-Host "Closing Interface"; sleep -seconds 5; }}.ToString()
    'Name' = 'IF02'
})

$a = New-Minion -InterfaceDefinitions @($InterfaceDefinition,$InterfaceDefinition2) -Verbose
$a.run()


Get-Job