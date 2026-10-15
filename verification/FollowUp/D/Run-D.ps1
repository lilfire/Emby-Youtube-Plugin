param([ValidateSet('Transport','Public','Hls','Channel','Key','Accounts','Content','Lease','BeforeWrite','Boundary','Abort')][string]$Mode='Transport',
    [ValidateSet('Factory','Reader','AfterReader')][string]$BoundaryPhase='Factory',
    [ValidateSet('Path','Parent','Journal','Token','File')][string]$BoundaryMutation='Path')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$dChapter=$PSScriptRoot
$dOutput=Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force $dOutput|Out-Null
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Shared isolated server must be stopped'}
if(Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue){throw 'Shared fixture port occupied'}
$videoScripts=Join-Path $repo 'verification/PersonalChannels'
$source=Get-Content (Join-Path $videoScripts 'Test-ProductionVideoStreams.ps1') -Raw -Encoding UTF8
$source=$source.Replace('$PSScriptRoot','$videoScripts')
$seam="    ForeignStreams 'Active'"
if(([regex]::Matches($source,[regex]::Escape($seam))).Count -ne 1){throw 'Video lifecycle seam changed'}
$source=$source.Replace($seam,$seam+"`n    . (Join-Path `$dChapter 'Probe-D.ps1')`n    `$completed=`$true`n    return")
if($Mode -eq 'Boundary'){
    $source=$source.Replace("& (Join-Path `$videoScripts 'Start-NativeClientFixture.ps1') -BufferedYouTube:`$BufferedYouTube","& (Join-Path `$dChapter 'Start-D.ps1')")
}
if($Mode -eq 'Public'){
    $binding="`$bound=Call 'PersonalChannelsFixture/ProductionNativeBindings' `$admin Post @{RootKey=[long]`$lib.LibraryId;OwnerUserId=`$u.UserId}"
    if(([regex]::Matches($source,[regex]::Escape($binding))).Count -ne 1){throw 'Binding seam changed'}
    $source=$source.Replace($binding,"`$bound=if(`$actor -eq 'a'){@{Registered=`$true}}else{Call 'PersonalChannelsFixture/ProductionNativeBindings' `$admin Post @{RootKey=[long]`$lib.LibraryId;OwnerUserId=`$u.UserId}}")
    $source=$source.Replace($seam,'')
}
$started=[DateTime]::UtcNow
try{ & ([scriptblock]::Create($source)) -RequireIsolation }
finally{
    $result=Join-Path $videoScripts 'bin/production-video-stream-protected-results.json'
    $runName=if($Mode -eq 'Boundary'){'Boundary-'+$BoundaryPhase+'-'+$BoundaryMutation}else{$Mode}
    if((Test-Path $result) -and (Get-Item $result).LastWriteTimeUtc -ge $started){Copy-Item $result (Join-Path $dOutput ($runName+'-results.json'))}
    else{@{Completed=$false;Observations=@();Reason='No fresh result from this run'}|ConvertTo-Json|Set-Content (Join-Path $dOutput ($runName+'-results.json')) -Encoding UTF8}
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    do{if(-not(Get-Process EmbyServer -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    @{ServerStopped=-not[bool](Get-Process EmbyServer -ErrorAction SilentlyContinue);
      PortFree=-not[bool](Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue);
      JournalGone=-not(Test-Path (Join-Path $videoScripts 'bin/native-client-state.json'));
      ProfilesGone=-not(Test-Path (Join-Path $repo 'verification/WatchState/bin/emby-isolated/data/data/youtube-personal'));
      NativeCleanup=if(Test-Path (Join-Path $videoScripts 'bin/native-client-cleanup.json')){Get-Content (Join-Path $videoScripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json}else{$null};
      Commit=(git -C $repo rev-parse HEAD);PluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;
      FixtureHash=(Get-FileHash $(if($Mode -eq 'Boundary'){Join-Path $dChapter 'bin/Release/net6.0/PersonalChannelsFixture.dll'}else{Join-Path $videoScripts 'bin/Release/net6.0/PersonalChannelsFixture.dll'})).Hash
    }|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dOutput ($runName+'-cleanup.json')) -Encoding UTF8
    if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'D server cleanup incomplete'}
}
