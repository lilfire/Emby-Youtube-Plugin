$ErrorActionPreference='Stop'
$summary=[Collections.Generic.List[object]]::new()
foreach($mode in @('Content','Embedded','Public','ImageRace','SubtitleRace','ImageLease','SubtitleLease')){
    $result=Get-Content (Join-Path $PSScriptRoot ('bin/'+$mode+'-results.json')) -Raw|ConvertFrom-Json
    $cleanup=Get-Content (Join-Path $PSScriptRoot ('bin/'+$mode+'-cleanup.json')) -Raw|ConvertFrom-Json
    if(-not $result.Completed){throw "Incomplete C matrix: $mode"}
    foreach($key in @('ServerStopped','JournalGone','ProfilesGone')){if(-not $cleanup.$key){throw "Incomplete cleanup: $mode $key"}}
    foreach($key in @('UsersGone','LibrariesGone','FixtureGone','GuardGone','MediaGone')){if(-not $cleanup.NativeCleanup.$key){throw "Incomplete native cleanup: $mode $key"}}
    $failed=@($result.Observations | Where-Object {$_.PSObject.Properties.Name -contains 'IsolationPass' -and $_.IsolationPass -eq $false})
    if(($mode -eq 'Content' -and $failed.Count -ne 2) -or ($mode -ne 'Content' -and $failed.Count -ne 0)){throw "Unexpected C assertions: $mode"}
    # The reused fixture's cleanup snapshot is taken before process exit. The
    # wrapper's later ServerStopped readback is authoritative for completion.
    $portable=@{Mode=$mode;Completed=$result.Completed;Observations=$result.Observations;Cleanup=$cleanup}
    $json=$portable|ConvertTo-Json -Depth 10
    if($json -match '(?i)X-Emby-Token|AccessToken|https?://|C:\\|Bearer\s'){throw 'Unexpected sensitive or machine-local evidence field'}
    $json|Set-Content (Join-Path $PSScriptRoot ($mode+'-EVIDENCE.json')) -Encoding UTF8
    $summary.Add(@{Mode=$mode;Observations=@($result.Observations).Count;FailedAssertions=$failed.Count;Completed=$true;CleanupVerified=$true;Commit=$cleanup.Commit;PluginHash=$cleanup.PluginHash;FixtureHash=$cleanup.FixtureHash})
}
$inspection=Get-Content (Join-Path $PSScriptRoot 'bin/processing.json') -Raw|ConvertFrom-Json
$inventory=@($inspection.Methods|ForEach-Object {@{Type=$_.Type;Method=$_.Method;BodyHash=$_.BodyHash;Depth=$_.Depth;Calls=@($_.Instructions | Where-Object {$_.Op -match '^call' -and $_.Operand -match '^(Emby|MediaBrowser)\.'} | Select-Object -ExpandProperty Operand -Unique)}})
@{Methods=$inventory;InspectionTruncated=$inspection.Truncated;Scope='Four selected native asset types, depth <= 4; external interface implementations are not a complete transitive inventory'}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot 'NATIVE-INVENTORY.json') -Encoding UTF8
$summary.ToArray()|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'SUMMARY.json') -Encoding UTF8
$summary.ToArray()|ForEach-Object {[pscustomobject]$_}|Format-Table Mode,Observations,FailedAssertions,Completed,CleanupVerified -AutoSize
