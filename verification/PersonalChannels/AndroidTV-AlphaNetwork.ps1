param([ValidateSet('Enable','Restore')][string]$Action='Enable')
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$snapshotPath=Join-Path $PSScriptRoot 'bin/androidtv-alpha-network.json'
$names=@('EnableRemoteAccess','LocalNetworkSubnets','LocalNetworkAddresses','RemoteIPFilter','IsRemoteIPFilterBlacklist')
try {
    $info=Call 'System/Info/Public'
    if($info.Id -ne 'faa414b10408459bae6e69dcc5ddcd6e' -or $info.ServerName -ne 'Isolated Watch State Test'){throw 'Unexpected Android test server'}
    $configuration=Call 'System/Configuration'
    if($Action -eq 'Enable'){
        if(Test-Path -LiteralPath $snapshotPath){throw 'Inspect saved Android network state before another change'}
        $before=@{}
        foreach($name in $names){$before[$name]=$configuration.$name}
        @{ServerId=$info.Id;Before=$before;TV='10.0.0.95'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $snapshotPath -Encoding UTF8
        $configuration.EnableRemoteAccess=$false
        $configuration.LocalNetworkSubnets=@('127.0.0.0/8','10.0.0.95/32')
        $configuration.LocalNetworkAddresses=@('10.0.10.17','127.0.0.1')
        $configuration.RemoteIPFilter=@('127.0.0.1','10.0.0.95')
        $configuration.IsRemoteIPFilterBlacklist=$false
    }else{
        $snapshot=Get-Content -LiteralPath $snapshotPath -Raw|ConvertFrom-Json
        if($snapshot.ServerId -ne $info.Id -or $snapshot.TV -ne '10.0.0.95'){throw 'Unexpected Android network restore target'}
        foreach($name in $names){$configuration.$name=$snapshot.Before.$name}
    }
    Call 'System/Configuration' $admin Post $configuration|Out-Null
    $readback=Call 'System/Configuration'
    foreach($name in $names){
        if(($readback.$name|ConvertTo-Json -Compress) -ne ($configuration.$name|ConvertTo-Json -Compress)){throw ('Network readback failed: '+$name)}
    }
    Write-Output ('Isolated Android network '+$Action+' verified; remote access remains '+$readback.EnableRemoteAccess+'.')
}finally{$client.Dispose()}
