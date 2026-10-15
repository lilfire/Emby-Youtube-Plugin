param([switch]$PublicSource)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scripts=Join-Path $repo 'verification/PersonalChannels'
$out=Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force $out|Out-Null
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Isolated server must be reserved and stopped'}
if(Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue){throw 'Port occupied'}
$previous=$env:PERSONAL_YOUTUBE_A_PROBE
$env:PERSONAL_YOUTUBE_B_OUTPUT=$out
if(Test-Path (Join-Path $out 'outputs.json')){
    $previousOutputs=@(Get-Content (Join-Path $out 'outputs.json') -Raw|ConvertFrom-Json)
    if(@($previousOutputs|Where-Object{Test-Path -LiteralPath $_.Path}).Count){throw 'Previous recorded Sync outputs remain; inspect before another run'}
}
Remove-Item -LiteralPath (Join-Path $out 'outputs.json') -ErrorAction SilentlyContinue
try{
    # Reuse the existing production-only lifecycle and its probe seam.
    $env:PERSONAL_YOUTUBE_A_PROBE=Join-Path $PSScriptRoot 'Probe-B.ps1'
    & (Join-Path $scripts 'Test-ProductionDiscoveryLists.ps1') -DiscoveryFamily Metadata -InspectMetadataReferences -PublicMetadataA:$PublicSource
}finally{
    $env:PERSONAL_YOUTUBE_A_PROBE=$previous
    $source=Join-Path $scripts ('bin/production-discovery-metadata-references-'+$(if($PublicSource){'public-a-'})+'diagnostic-results.json')
    if(Test-Path $source){Copy-Item $source (Join-Path $out $(if($PublicSource){'public-results.json'}else{'private-results.json'}))}
    $root=Join-Path $repo 'verification/WatchState/bin/emby-isolated'
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    do{if(-not(Get-Process EmbyServer -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    $removed=0
    $outputs=if(Test-Path (Join-Path $out 'outputs.json')){@(Get-Content (Join-Path $out 'outputs.json') -Raw|ConvertFrom-Json)}else{@()}
    foreach($record in $outputs){
        $path=[IO.Path]::GetFullPath($record.Path)
        $allowed=[IO.Path]::GetFullPath((Join-Path $root 'data/sync'))+[IO.Path]::DirectorySeparatorChar
        if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Get-Process EmbyServer -ErrorAction SilentlyContinue)){throw 'Unsafe output cleanup'}
        if(Test-Path -LiteralPath $path){
            if((Get-FileHash -LiteralPath $path).Hash -ne $record.Hash){throw 'Output changed before cleanup'}
            Remove-Item -LiteralPath $path
            $removed++
        }
    }
    @{ServerStopped=-not[bool](Get-Process EmbyServer -ErrorAction SilentlyContinue);
      JournalGone=-not(Test-Path (Join-Path $scripts 'bin/native-client-state.json'));
      FixtureGone=-not(Test-Path (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll'));
      ProfilesGone=-not(Test-Path (Join-Path $root 'data/data/youtube-personal'));
      ConvertedFilesRemoved=$removed;RecordedOutputsGone=@($outputs|Where-Object{Test-Path -LiteralPath $_.Path}).Count -eq 0;
      NativeCleanup=(Get-Content (Join-Path $scripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json);
      Commit=(git -C $repo rev-parse HEAD);PluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;
      FixtureHash=(Get-FileHash (Join-Path $scripts 'bin/Release/net6.0/PersonalChannelsFixture.dll')).Hash;PublicSource=[bool]$PublicSource
    }|ConvertTo-Json -Depth 5|Set-Content (Join-Path $out $(if($PublicSource){'public-cleanup.json'}else{'private-cleanup.json'})) -Encoding UTF8
    $env:PERSONAL_YOUTUBE_B_OUTPUT=$null
}
