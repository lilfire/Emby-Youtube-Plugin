param([switch]$PublicSource)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixtureScripts=Join-Path $repo 'verification/PersonalChannels'
$output=Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Path $output -Force|Out-Null
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'An Emby process is active; reserve the isolated fixture first'}
if(Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue){throw 'Fixture port is occupied'}
$previousProbe=$env:PERSONAL_YOUTUBE_A_PROBE
try{
    $env:PERSONAL_YOUTUBE_A_PROBE=Join-Path $PSScriptRoot 'Probe-A.ps1'
    & (Join-Path $fixtureScripts 'Test-ProductionDiscoveryLists.ps1') -DiscoveryFamily Metadata -InspectMetadataReferences -PublicMetadataA:$PublicSource
}finally{
    $env:PERSONAL_YOUTUBE_A_PROBE=$previousProbe
    $source=Join-Path $fixtureScripts ('bin/production-discovery-metadata-references-'+$(if($PublicSource){'public-a-'})+'diagnostic-results.json')
    if(Test-Path $source){Copy-Item -LiteralPath $source -Destination (Join-Path $output $(if($PublicSource){'public-results.json'}else{'private-results.json'}))}
    $root=Join-Path $repo 'verification/WatchState/bin/emby-isolated'
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do{$active=@(Get-Process EmbyServer -ErrorAction SilentlyContinue);if(-not $active.Count){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    $cleanup=Get-Content (Join-Path $fixtureScripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json
    @{ServerStopped=-not [bool](Get-Process EmbyServer -ErrorAction SilentlyContinue);
      FixtureRemoved=-not (Test-Path (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll'));
      ProfilesRemoved=-not (Test-Path (Join-Path $root 'data/data/youtube-personal'));
      PluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;
      FixtureHash=(Get-FileHash (Join-Path $fixtureScripts 'bin/Release/net6.0/PersonalChannelsFixture.dll')).Hash;
      SourceCommit=(git -C $repo rev-parse HEAD);PublicSource=[bool]$PublicSource
      NativeCleanup=$cleanup;AuditPlaylistFoldersGone=@(Get-ChildItem (Join-Path $root 'data/data/userplaylists') -Directory -Filter 'A-audit-*' -ErrorAction SilentlyContinue).Count -eq 0
    }|ConvertTo-Json|Set-Content (Join-Path $output $(if($PublicSource){'public-cleanup.json'}else{'private-cleanup.json'})) -Encoding UTF8
}
