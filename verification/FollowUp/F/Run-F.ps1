$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scripts=Join-Path $repo 'verification/PersonalChannels'
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Shared isolated server must be stopped'}
if(Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue){throw 'Shared fixture port occupied'}
$out=Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force $out|Out-Null
$source=Get-Content (Join-Path $scripts 'Test-PersonalYouTubeAlphaJob.ps1') -Raw
$start=$source.IndexOf('    foreach($pending in @($false,$true)){')
$end=$source.IndexOf('    $completed=$true',$start)
if($start -lt 0 -or $end -lt 0){throw 'Alpha fixture seam changed'}
$source=$source.Substring(0,$start)+"    . (Join-Path `$fChapter 'Collect-Permissions-F.ps1')`n    . (Join-Path `$fChapter 'Probe-F.ps1')`n"+$source.Substring($end)
$source=$source.Replace('$PSScriptRoot','$scripts')
$source=$source.Replace('Real authenticated save/status, production jobs, media and native libraries; actual restarts, simulated Publishing over active publication, real process interruption in Preparing, replacement and deletion. Controlled Google transport; no main server or physical app.','F: actual authenticated profiles/jobs, native publication and playback; identical key/channel for two owners; disabled/revoked/deleted accounts, same name new GUID. Controlled Google catalog transport; real yt-dlp media extraction; no main server or physical app.')
$fChapter=$PSScriptRoot
$fStarted=[DateTime]::UtcNow
try{& ([scriptblock]::Create($source))}
finally{
    $file=Join-Path $scripts 'bin/personal-alpha-job-results.json'
    if((Test-Path $file) -and (Get-Item $file).LastWriteTimeUtc -ge $fStarted){Copy-Item $file (Join-Path $out 'integration-results.json')}
    else{throw 'No fresh F integration evidence'}
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    do{if(-not(Get-Process EmbyServer -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    @{Commit=(git -C $repo rev-parse HEAD);Platform='Windows x64';EmbyVersion='4.10.1.0';
      PluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;
      FixtureHash=(Get-FileHash (Join-Path $scripts 'bin/Release/net6.0/PersonalChannelsFixture.dll')).Hash;
      ServerStopped=-not[bool](Get-Process EmbyServer -ErrorAction SilentlyContinue);
      JournalGone=-not(Test-Path (Join-Path $scripts 'bin/native-client-state.json'));
      ProfilesGone=-not(Test-Path (Join-Path $repo 'verification/WatchState/bin/emby-isolated/data/data/youtube-personal'));
      NativeCleanup=if(Test-Path (Join-Path $scripts 'bin/native-client-cleanup.json')){Get-Content (Join-Path $scripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json}else{$null}
    }|ConvertTo-Json -Depth 6|Set-Content (Join-Path $out 'cleanup.json') -Encoding UTF8
}
