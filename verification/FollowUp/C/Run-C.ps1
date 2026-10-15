param([ValidateSet('Content','Embedded','Public','ImageRace','SubtitleRace','ImageLease','SubtitleLease')][string]$Mode='Content')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$assetScripts=Join-Path $repo 'verification/PersonalChannels'
$cOutput=Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force $cOutput|Out-Null
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Shared isolated server must be stopped'}
if(Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue){throw 'Shared fixture port occupied'}
# Reuse the existing production fixture without changing another chapter's files.
$source=Get-Content (Join-Path $assetScripts 'Test-ProductionMediaAssets.ps1') -Raw
$source=$source.Replace('$PSScriptRoot','$assetScripts')
$seam="    Phase 'Active' `$true"
if(([regex]::Matches($source,[regex]::Escape($seam))).Count -ne 1){throw 'Asset lifecycle seam changed'}
if($Mode -eq 'Content'){
    $source=$source.Replace($seam,$seam+"`n    . (Join-Path `$cChapter 'Probe-C.ps1')")
}
if($Mode -eq 'Public'){
    $binding="`$boundResponse=Request 'PersonalChannelsFixture/ProductionNativeBindings' `$admin Post @{RootKey=[long]`$lib.LibraryId;OwnerUserId=`$u.UserId}"
    if(([regex]::Matches($source,[regex]::Escape($binding))).Count -ne 1){throw 'Public binding seam changed'}
    $source=$source.Replace($binding,"`$boundResponse=if(`$actor -eq 'a'){@{Status=200;Text='{""Registered"":true}'}}else{Request 'PersonalChannelsFixture/ProductionNativeBindings' `$admin Post @{RootKey=[long]`$lib.LibraryId;OwnerUserId=`$u.UserId}}")
    $source=$source.Replace($seam,"    . (Join-Path `$cChapter 'Public-C.ps1')`n"+$seam)
}
if($Mode -in @('Content','Embedded')){$source=$source.Replace($seam,$seam+"`n    . (Join-Path `$cChapter 'Formats-C.ps1')")}
if($Mode -in @('Content','Embedded')){
    $source=$source.Replace("    Phase 'Restarted' `$false","    Phase 'Restarted' `$false`n    . (Join-Path `$cChapter 'Accounts-C.ps1')")
}
if($Mode -eq 'Embedded'){
    $source=$source.Replace("& (Join-Path `$assetScripts 'Start-NativeClientFixture.ps1') -MediaAssets","& (Join-Path `$cChapter 'Start-Embedded.ps1')")
    $source=$source.Replace("`$_.Type -eq 'Subtitle' -and `$_.IsExternal","`$_.Type -eq 'Subtitle' -and -not `$_.IsExternal")
}
$cChapter=$PSScriptRoot
$cStarted=[DateTime]::UtcNow
$argsForRun=@{DerivedAssets=$true;HttpVariants=$true}
if($Mode -in @('Content','Embedded')){$argsForRun.InspectProcessing=$true}
elseif($Mode -eq 'Public'){$argsForRun.RequireIsolation=$true}
else{
    $argsForRun.WriterRace=if($Mode.StartsWith('Image')){'Image'}else{'Subtitle'}
    $argsForRun.AfterWriteCheckRace=$Mode.EndsWith('Lease')
    $argsForRun.RequireIsolation=$true
}
try{ & ([scriptblock]::Create($source)) @argsForRun }
finally{
    $result=if($Mode -in @('Content','Embedded')){'processing-inspection'}else{'http-variants'}
    $file=Join-Path $assetScripts ('bin/derived-lifecycle-recipe-bound-production-media-assets-'+$result+'-results.json')
    if((Test-Path $file) -and (Get-Item -LiteralPath $file).LastWriteTimeUtc -ge $cStarted){Copy-Item $file (Join-Path $cOutput ($Mode+'-results.json'))}
    else{@{Completed=$false;Reason='No fresh result from this run'}|ConvertTo-Json|Set-Content (Join-Path $cOutput ($Mode+'-results.json')) -Encoding UTF8}
    $inspection=Join-Path $assetScripts 'bin/native-asset-processing-inspection.json'
    if($Mode -eq 'Content' -and (Test-Path $inspection)){Copy-Item $inspection (Join-Path $cOutput 'processing.json')}
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    do{if(-not(Get-Process EmbyServer -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    # Remove only this run's newly created native asset outputs, after recording
    # their retention through profile deletion/restart. Historical cache is kept.
    $removedCache=0
    $isolatedCache=[IO.Path]::GetFullPath((Join-Path $repo 'verification/WatchState/bin/emby-isolated/data/cache'))
    if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Server still running before cache cleanup'}
    foreach($family in @('images','subtitles','temp')){
        $familyPath=[IO.Path]::GetFullPath((Join-Path $isolatedCache $family))
        foreach($file in @(Get-ChildItem -LiteralPath $familyPath -File -Recurse -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTimeUtc -ge $cStarted -and $_.Extension -in @('.png','.jpg','.jpeg','.gif','.vtt','.srt','.ass','.ssa')})){
            if(-not $file.FullName.StartsWith($familyPath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe generated cache cleanup'}
            Remove-Item -LiteralPath $file.FullName
            if(Test-Path -LiteralPath $file.FullName){throw 'Generated cache cleanup readback failed'}
            $removedCache++
        }
    }
    @{ServerStopped=-not[bool](Get-Process EmbyServer -ErrorAction SilentlyContinue);
      JournalGone=-not(Test-Path (Join-Path $assetScripts 'bin/native-client-state.json'));
      ProfilesGone=-not(Test-Path (Join-Path $repo 'verification/WatchState/bin/emby-isolated/data/data/youtube-personal'));
      GeneratedCacheFilesRemoved=$removedCache;
      NativeCleanup=if(Test-Path (Join-Path $assetScripts 'bin/native-client-cleanup.json')){Get-Content (Join-Path $assetScripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json}else{$null};
      Commit=(git -C $repo rev-parse HEAD);PluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;
      FixtureHash=(Get-FileHash (Join-Path $assetScripts 'bin/Release/net6.0/PersonalChannelsFixture.dll')).Hash
    }|ConvertTo-Json -Depth 6|Set-Content (Join-Path $cOutput ($Mode+'-cleanup.json')) -Encoding UTF8
}
