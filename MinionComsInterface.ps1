param ($msg,$guid,$interfaceID)
try {
    $message = $msg | ConvertFrom-Json
}
catch {
    Write-Error "There was an issue loading the Message: $($Error[0].Exception)"
}

#return an handler executed by the Executive (parent) Job.
$handler = switch ($message.action)
{
  'KILL'{ 
    { Get-Job | Remove-Job -Force }
    break;
  }
  'STOP' {
    { Set-MinionDataProperty -propertyName STOP -value $true }
    break;
  }
  'QUERYJOB' {
    { 
        $MinionData | ConvertTo-Json -Depth ([int]::MaxValue)
    }
    break;
  }
  'QUERYMINIONSTATE' {
    {
        Send-RabbitMqMessage -Exchange WORK -Key '#' -InputObject ($MinionData | ConvertTo-Json -Depth ([int]::MaxValue) -Compress);
    }
    break;
   }

  default {
    { Write-Host $event.MessageData -ForegroundColor Green;
    Get-job |FL * | out-string | write-host -ForegroundColor Yellow }
    $MinionData | ConvertTo-Json -Depth ([int]::MaxValue) | Write-Host -ForegroundColor White
    break;
  }
}

Invoke-MinionAction -Action $handler -MessageData $msg

"This is a TEST::MSG:$msg:::GUID:$guid" | Out-File -Encoding ascii -FilePath "C:\dev\psworker\outComms_$guid.txt" -Append
"This is a TEST in Communications::: $msg ::Count $($args.count)" | Write-Host
#$null = New-Event -SourceIdentifier TEST -MessageData $msgData
