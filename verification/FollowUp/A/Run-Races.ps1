$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scripts=Join-Path $repo 'verification/PersonalChannels'
$summary=[Collections.Generic.List[object]]::new()
$variants=@(
    @{Flag='InventoryRace';File='production-item-list-revocation-protected-results.json'},
    @{Flag='ResultRace';File='production-item-list-result-protected-results.json'},
    @{Flag='WriteRace';File='production-item-list-write-protected-results.json'},
    @{Flag='AfterWriteCheckRace';File='production-item-list-write-lease-results.json'}
)
foreach($variant in $variants){
    if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Isolated resource is busy'}
    $arguments=@{RequireRaceSafe=$true};$arguments[$variant.Flag]=$true
    & (Join-Path $scripts 'Test-ProductionItemLists.ps1') @arguments
    $result=Get-Content (Join-Path $scripts ('bin/'+$variant.File)) -Raw|ConvertFrom-Json
    Copy-Item -LiteralPath (Join-Path $scripts ('bin/'+$variant.File)) -Destination (Join-Path $PSScriptRoot ('bin/'+$variant.File))
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do{$active=@(Get-Process EmbyServer -ErrorAction SilentlyContinue);if(-not $active.Count){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    $cleanup=Get-Content (Join-Path $scripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json
    $summary.Add(@{Boundary=$variant.Flag;Observations=$result.Observations;Completed=$result.Completed;Cleanup=$cleanup;ServerStopped=$active.Count -eq 0;
        EmbyVersion='4.10.1.0';PluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;
        FixtureHash=(Get-FileHash (Join-Path $scripts 'bin/Release/net6.0/PersonalChannelsFixture.dll')).Hash;SourceCommit=(git -C $repo rev-parse HEAD)})
    Write-Output ('A race completed: '+$variant.Flag)
}
$summary|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot 'RACE-EVIDENCE.json') -Encoding UTF8
