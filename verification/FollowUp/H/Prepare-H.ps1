$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workspace=Join-Path $PSScriptRoot 'bin/workspace'
if(Test-Path $workspace){throw 'Inspect existing H workspace before preparing again'}
$sourceRoot=Join-Path $repo 'verification/WatchState/bin/emby-isolated'
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Source fixture must be stopped for a consistent copy'}
New-Item -ItemType Directory -Force $workspace|Out-Null
$fixtureRoot=Join-Path $workspace 'verification/WatchState/bin/emby-isolated'
New-Item -ItemType Directory -Force $fixtureRoot|Out-Null
Copy-Item (Join-Path $sourceRoot 'server') $fixtureRoot -Recurse
Copy-Item (Join-Path $sourceRoot 'data') $fixtureRoot -Recurse
Copy-Item (Join-Path $sourceRoot 'test-auth.json') $fixtureRoot
foreach($relative in @('bin/Release/net6.0','verification/EmbyFixture/bin/Release/net6.0','verification/PersonalChannels/bin/Release/net6.0','verification/PersonalChannels/bin/media-tools')){
    New-Item -ItemType Directory -Force (Join-Path $workspace $relative)|Out-Null
}
foreach($relative in @('bin/Release/net6.0/Emby.YouTubePlugin.dll','verification/EmbyFixture/bin/Release/net6.0/WatchStateFixture.dll','verification/PersonalChannels/bin/Release/net6.0/PersonalChannelsFixture.dll','verification/PersonalChannels/bin/media-tools/youtube-buffer-test.mp4')){
    Copy-Item (Join-Path $repo $relative) (Join-Path $workspace $relative)
}
foreach($relative in @('verification/EmbyFixture/Start-IsolatedServer.ps1','verification/PersonalChannels/Start-NativeClientFixture.ps1','verification/PersonalChannels/NativeReadyHelpers.ps1')){
    $source=Get-Content (Join-Path $repo $relative) -Raw -Encoding UTF8
    $source=$source.Replace('18096','18108').Replace('Isolated Watch State Test','Isolated H Client Test')
    Set-Content (Join-Path $workspace $relative) $source -Encoding UTF8
}
$configPath=Join-Path $fixtureRoot 'data/config/system.xml'
[xml]$config=Get-Content $configPath -Raw
$config.ServerConfiguration.HttpServerPortNumber='18108'
$config.ServerConfiguration.PublicPort='18108'
$config.ServerConfiguration.HttpsPortNumber='18109'
$config.ServerConfiguration.PublicHttpsPort='18109'
$config.ServerConfiguration.ServerName='Isolated H Client Test'
$config.Save($configPath)
$sources=@('bin/Release/net6.0/Emby.YouTubePlugin.dll','verification/PersonalChannels/bin/Release/net6.0/PersonalChannelsFixture.dll','verification/PersonalChannels/Start-NativeClientFixture.ps1')|ForEach-Object{
    @{File=$_;SHA256=(Get-FileHash (Join-Path $repo $_)).Hash}
}
@{Commit=(git -C $repo rev-parse HEAD);ServerVersion='4.10.1.0';Port=18108;Sources=$sources;Catalog='No Google catalog; buffered historical media sample';ProductionChanged=$false}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'ENVIRONMENT.json') -Encoding UTF8
& (Join-Path $workspace 'verification/PersonalChannels/Start-NativeClientFixture.ps1') -BufferedYouTube -MediaAssets
if($LASTEXITCODE){throw 'H client fixture setup failed'}
