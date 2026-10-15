param([switch]$Stop,[switch]$MediaAssets,[switch]$Movies,[switch]$Metadata,[switch]$MetadataImages,[switch]$BufferedYouTube)
if($MetadataImages -and -not $Metadata){throw 'Metadata images require native metadata sources'}
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$stateFile=Join-Path $PSScriptRoot 'bin/native-client-state.json'
$fixture=Join-Path $root 'data/plugins/PersonalChannelsFixture.dll'
$guardFile=Join-Path $root 'data/data/personal-channels-fixture.json.guard.json'
$tokenLedger=Join-Path $root 'data/data/personal-channels-fixture.json.open-token-owners.json'
$nativeLedger=Join-Path $root 'data/data/personal-channels-fixture.json.native-reference-owners.json'
$state=@{Users=@();Libraries=@();Files=@();SetupReady=$false;Version='4.10.1.0';ServerName='Isolated Watch State Test'}
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=15}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=$body | ConvertTo-Json -Depth 14}
    Invoke-RestMethod @args
}
function WaitServer {
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong client fixture server'}
}
function SaveState {$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $stateFile -Encoding UTF8}
if ($Stop) {
    if (-not (Test-Path -LiteralPath $stateFile)) {throw 'No client fixture cleanup journal'}
    $state=Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($state.ServerName -ne 'Isolated Watch State Test') {throw 'Invalid cleanup journal'}
    $live=Get-Process EmbyServer -ErrorAction SilentlyContinue
    if ($live) {WaitServer;& $control -Stop}
    foreach ($path in @($fixture,$guardFile,$tokenLedger,($tokenLedger+'.tmp'),$nativeLedger,($nativeLedger+'.tmp'),(Join-Path $root 'data/data/personal-channels-fixture.json.production-bindings-mode'))) {
        $target=[IO.Path]::GetFullPath($path)
        if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe client plugin cleanup'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
    & $control
    try {
        WaitServer
        foreach ($record in $state.Users) {
            $existing=@((Call 'Users') | Where-Object Id -eq $record.UserId)
            if ($existing.Count) {
                if ($existing.Count -ne 1 -or $existing[0].Name -ne $record.Name -or $existing[0].Policy.IsAdministrator) {throw 'Unexpected client user identity'}
                Call "Users/$($record.UserId)" $admin Delete | Out-Null
            }
        }
        foreach ($record in @($state.SyncJobs | Where-Object {$_})) {
            $existing=@((Call 'Sync/Jobs').Items | Where-Object Id -eq $record.JobId)
            if ($existing.Count) {
                if ($existing.Count -ne 1 -or $existing[0].Name -ne $record.Name -or $record.Name -notin @('PrivateNativeVideo_a_client','PrivateNativeVideo_b_client')) {throw 'Unexpected synthetic Sync identity'}
                Call "Sync/Jobs/$($record.JobId)" $admin Delete | Out-Null
            }
        }
        foreach ($record in $state.Libraries) {
            $existing=@((Call 'Library/VirtualFolders/Query').Items | Where-Object ItemId -eq $record.LibraryId)
            if (-not $existing.Count -and $record.PlannedRenameName) {
                $existing=@((Call 'Library/VirtualFolders/Query').Items | Where-Object {
                    ($_.Name -eq $record.PlannedRenameName -or ($record.PlannedRenameName -match '^YouTube [0-9a-f]{32}$' -and $_.Name -eq 'YouTube')) -and $_.Locations.Count -eq 1 -and
                    [IO.Path]::GetFullPath($_.Locations[0]) -eq [IO.Path]::GetFullPath($record.Folder)
                })
                if ($existing.Count -gt 1) {throw 'Ambiguous renamed synthetic library'}
                if ($existing.Count -eq 1) {$record.LibraryId=[string]$existing[0].ItemId;$record.Name=$existing[0].Name}
            }
            if ($existing.Count) {
                if($record.Name -match '^YouTube [0-9a-f]{32}$' -and $existing[0].Name -eq 'YouTube'){$record.Name='YouTube'}
                if ($record.PlannedRenameName -and $existing[0].Name -eq $record.PlannedRenameName) {$record.Name=$existing[0].Name}
                $pendingGeneration=if($record.Name -match '^JournalPending_([0-9a-f]{32})$'){$Matches[1]}elseif($record.Name -match '^YouTube ([0-9a-f]{32})$'){$Matches[1]}else{''}
                $pausedCreation=$record.PlannedRenameName -eq $record.Name -and $pendingGeneration -and $existing[0].Locations.Count -eq 0 -and [IO.Path]::GetFileName($record.Folder) -eq $pendingGeneration -and [IO.Path]::GetFullPath($record.Folder).StartsWith([IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal/media'))+[IO.Path]::DirectorySeparatorChar)
                if ($existing.Count -ne 1 -or $existing[0].Name -ne $record.Name -or (-not $pausedCreation -and ($existing[0].Locations.Count -ne 1 -or [IO.Path]::GetFullPath($existing[0].Locations[0]) -ne [IO.Path]::GetFullPath($record.Folder)))) {throw 'Unexpected client library identity'}
                Call 'Library/VirtualFolders/Delete' $admin Post @{Id=$record.LibraryId} | Out-Null
            }
        }
        $remainingUsers=@((Call 'Users') | ForEach-Object Id)
        $remainingLibraries=@((Call 'Library/VirtualFolders/Query').Items | ForEach-Object ItemId)
        if (@($state.Users | Where-Object {$_.UserId -in $remainingUsers}).Count -or @($state.Libraries | Where-Object {$_.LibraryId -in $remainingLibraries}).Count) {throw 'Client cleanup failed readback'}
        $remainingJobs=@((Call 'Sync/Jobs').Items | ForEach-Object Id)
        if (@($state.SyncJobs | Where-Object {$_.JobId -in $remainingJobs}).Count) {throw 'Synthetic Sync cleanup readback failed'}
    } finally {& $control -Stop}
    foreach ($file in $state.Files) {
        $target=[IO.Path]::GetFullPath($file)
        $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin/native-client'))+[IO.Path]::DirectorySeparatorChar
        if (-not $target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) {throw 'Unsafe client media cleanup'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
    @{UsersGone=$true;LibrariesGone=$true;FixtureGone=(-not (Test-Path $fixture));GuardGone=(-not (Test-Path $guardFile));MediaGone=(@($state.Files|Where-Object{Test-Path -LiteralPath $_}).Count -eq 0);ServerStopped=(@(Get-Process EmbyServer -ErrorAction SilentlyContinue).Count -eq 0)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/native-client-cleanup.json') -Encoding UTF8
    Remove-Item -LiteralPath $stateFile
    Write-Output 'Client fixture cleanup verified.'
    exit 0
}
if (Test-Path -LiteralPath $stateFile) {throw 'Client fixture already has a journal; inspect before continuing'}
if ((Test-Path $fixture) -or (Test-Path $guardFile) -or (Test-Path $tokenLedger) -or (Test-Path ($tokenLedger+'.tmp')) -or (Test-Path $nativeLedger) -or (Test-Path ($nativeLedger+'.tmp')) -or (Get-Process EmbyServer -ErrorAction SilentlyContinue)) {throw 'Client setup requires a clean stopped isolated server'}
SaveState
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination $fixture
    & $control
    WaitServer
    foreach ($owner in @('a','b')) {
        $userName="native-privacy-fixture-$owner"
        if (@((Call 'Users') | Where-Object Name -eq $userName).Count) {throw 'Synthetic client user exists'}
        $name="Private Native Fixture $owner"
        if (@((Call 'Library/VirtualFolders/Query').Items | Where-Object Name -eq $name).Count) {throw 'Synthetic client library exists'}
        $folder=Join-Path $PSScriptRoot "bin/native-client/$owner"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $media=Join-Path $folder "PrivateNativeVideo_${owner}_client.mp4"
        $state.Files+=@($media);SaveState
        $color=if ($owner -eq 'a') {'blue'} else {'red'}
        if($BufferedYouTube -and $owner -eq 'a'){
            $bufferFile=Join-Path $PSScriptRoot 'bin/media-tools/youtube-buffer-test.mp4'
            if(-not (Test-Path -LiteralPath $bufferFile) -or (Get-Item -LiteralPath $bufferFile).Length -gt 64MB){throw 'Missing or oversized buffered YouTube test video'}
            Copy-Item -LiteralPath $bufferFile -Destination $media
            if((Get-FileHash -LiteralPath $media).Hash -ne (Get-FileHash -LiteralPath $bufferFile).Hash){throw 'Buffered YouTube fixture copy mismatch'}
            $state.BufferedYouTube=@{Owner='a';VideoId='DTi8wZ1a1TA';SourceHash=(Get-FileHash -LiteralPath $bufferFile).Hash};SaveState
        }else{
            & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel error -f lavfi -i "color=c=$color`:s=160x90:r=25:d=6" -f lavfi -i 'anullsrc=r=44100:cl=stereo' -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac -y $media
            if ($LASTEXITCODE -ne 0) {throw 'Client media generation failed'}
        }
        if ($MediaAssets) {
            $subtitle=Join-Path $folder "PrivateNativeVideo_${owner}_client.en.srt"
            $image=Join-Path $folder "fixture-primary-$owner.png"
            $state.Files+=@($subtitle,$image);SaveState
            "1`r`n00:00:00,000 --> 00:00:05,000`r`nPrivateSubtitle_${owner}_native_media`r`n" | Set-Content -LiteralPath $subtitle -Encoding UTF8
            & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel error -f lavfi -i "color=c=$color`:s=160x90" -frames:v 1 -update 1 -y $image
            if ($LASTEXITCODE -ne 0) {throw 'Synthetic image generation failed'}
        }
        $collectionType=if($Movies){'movies'}else{'homevideos'}
        $nativeItemType=if($Movies){'Movie'}else{'Video'}
        Call 'Library/VirtualFolders' $admin Post @{Name=$name;CollectionType=$collectionType;Paths=@($folder);RefreshLibrary=$false;LibraryOptions=@{EnableRealtimeMonitor=$false;SaveLocalMetadata=$false;TypeOptions=@(@{Type=$nativeItemType;MetadataFetchers=@();ImageFetchers=@()})}} | Out-Null
        $library=@((Call 'Library/VirtualFolders/Query').Items|Where-Object Name -eq $name)[0]
        $state.Libraries+=@(@{Owner=$owner;Name=$name;LibraryId=[string]$library.ItemId;LibraryGuid=$library.Guid;Folder=$folder});SaveState
        $user=Call 'Users/New' $admin Post @{Name=$userName}
        $state.Users+=@(@{Owner=$owner;Name=$userName;UserId=[string]$user.Id});SaveState
        $policy=$user.Policy
        $policy.IsAdministrator=$false;$policy.EnableAllFolders=$false;$policy.EnabledFolders=@($library.Guid)
        $policy.EnableAllChannels=$false;$policy.EnabledChannels=@();$policy.EnableRemoteControlOfOtherUsers=$false;$policy.EnableSharedDeviceControl=$false
        Call "Users/$($user.Id)/Policy" $admin Post $policy | Out-Null
        $check=(Call "Users/$($user.Id)").Policy
        if ($check.IsAdministrator -or $check.EnableAllFolders -or $check.EnabledFolders.Count -ne 1 -or $check.EnabledFolders[0] -ne $library.Guid -or $check.EnableRemoteControlOfOtherUsers -or $check.EnableSharedDeviceControl) {throw 'Client policy readback failed'}
        Call "Items/$($library.ItemId)/Refresh?Recursive=true&MetadataRefreshMode=FullRefresh&ImageRefreshMode=ValidationOnly" $admin Post | Out-Null
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {
        $ready=$true
        foreach ($library in $state.Libraries) {
            $nativeItemType=if($Movies){'Movie'}else{'Video'}
            try { $items=Call "Items?ParentId=$($library.LibraryId)&Recursive=true&IncludeItemTypes=$nativeItemType" }
            catch {
                # A library scan can change sources while this readiness query
                # runs. Only readiness polls may retry the resulting denial.
                if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
                $ready=$false; continue
            }
            if ($items.Items.Count -ne 1) {$ready=$false} else {$library.VideoId=[string]$items.Items[0].Id}
        }
        if (-not $ready) {Start-Sleep -Milliseconds 200}
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    if (-not $ready) {throw 'Client video scan timed out'}
    if($Metadata){
        foreach($library in $state.Libraries){
            $item=Call "Users/$($auth.UserId)/Items/$($library.VideoId)?Fields=Genres,Studios,Tags"
            $item|Add-Member -NotePropertyName Genres -NotePropertyValue @("PrivateNativeGenre_$($library.Owner)",'SharedNativeGenre') -Force
            $item|Add-Member -NotePropertyName GenreItems -NotePropertyValue $null -Force
            $item|Add-Member -NotePropertyName Studios -NotePropertyValue @(@{Name="PrivateNativeStudio_$($library.Owner)"},@{Name='SharedNativeStudio'}) -Force
            $item|Add-Member -NotePropertyName Tags -NotePropertyValue @("PrivateNativeTag_$($library.Owner)",'SharedNativeTag') -Force
            $item|Add-Member -NotePropertyName TagItems -NotePropertyValue $null -Force
            if($env:PERSONAL_YOUTUBE_A_PROBE){
                $item|Add-Member -NotePropertyName ProductionYear -NotePropertyValue $(if($library.Owner -eq 'a'){2001}else{2002}) -Force
                $item|Add-Member -NotePropertyName OfficialRating -NotePropertyValue "PrivateNativeRating_$($library.Owner)" -Force
                $item|Add-Member -NotePropertyName People -NotePropertyValue @(@{Name="PrivateNativePerson_$($library.Owner)";Type='Actor'}) -Force
            }
            Call "Items/$($library.VideoId)" $admin Post $item|Out-Null
            $readback=Call "Users/$($auth.UserId)/Items/$($library.VideoId)?Fields=Genres,Studios,Tags"
            $actualTags=@($readback.Tags)+@($readback.TagItems.Name)
            $actualGenres=@($readback.Genres)+@($readback.GenreItems.Name)
            $privateIds=@(@($readback.GenreItems)+@($readback.Studios)+@($readback.TagItems)|Where-Object {$_.Name -like "PrivateNative*_$($library.Owner)"}|ForEach-Object {[string]$_.Id})
            if($privateIds.Count -ne 3 -or @($privateIds|Where-Object {[long]$_ -le 0}).Count){throw 'Synthetic metadata private reference readback incomplete'}
            $metadataMap=@{}
            foreach($category in @('Genres','Studios','Tags')){
                $pairs=if($category -eq 'Genres'){$readback.GenreItems}elseif($category -eq 'Studios'){$readback.Studios}else{$readback.TagItems}
                $metadataMap[$category]=@($pairs|Where-Object Name -like 'PrivateNative*'|Select-Object Name,Id)
            }
            @{Owner=$library.Owner;Genres=$actualGenres;Studios=@($readback.Studios.Name);Tags=$actualTags;PrivateIds=$privateIds;Metadata=$metadataMap}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot ('bin/native-client-metadata-readback-'+$library.Owner+'.json')) -Encoding UTF8
            if("PrivateNativeGenre_$($library.Owner)" -notin $actualGenres -or "PrivateNativeStudio_$($library.Owner)" -notin $readback.Studios.Name -or "PrivateNativeTag_$($library.Owner)" -notin $actualTags){throw 'Synthetic native metadata readback failed'}
            if($MetadataImages){
                $image=Join-Path $library.Folder "fixture-primary-$($library.Owner).png"
                $state.Files+=@($image);SaveState
                $color=if($library.Owner -eq 'a'){'blue'}else{'red'}
                & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel error -f lavfi -i "color=c=$color`:s=160x90" -frames:v 1 -update 1 -y $image
                if($LASTEXITCODE -ne 0){throw 'Synthetic metadata image generation failed'}
                $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($image))
                foreach($id in $privateIds){Invoke-RestMethod -Uri "$base/Items/$id/Images/Primary" -Headers $admin -Method Post -ContentType 'image/png' -Body $encoded -TimeoutSec 15|Out-Null}
            }
        }
    }
    if ($MediaAssets) {
        foreach ($library in $state.Libraries) {
            $image=Join-Path $library.Folder "fixture-primary-$($library.Owner).png"
            $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($image))
            Invoke-RestMethod -Uri "$base/Items/$($library.VideoId)/Images/Primary" -Headers $admin -Method Post -ContentType 'image/png' -Body $encoded -TimeoutSec 15 | Out-Null
        }
    }
    $mapping=@{}
    foreach ($library in $state.Libraries) {$mapping[$library.LibraryId]=@($state.Users|Where-Object Owner -eq $library.Owner)[0].UserId}
    $guard=Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$mapping}
    if (-not $guard.Ready -or -not $guard.Enabled) {throw 'Client guard unavailable'}
    $state.SetupReady=$true;$state.BootId=$guard.BootId;SaveState
    $state | ConvertTo-Json -Depth 8
} catch {
    Write-Output 'Client fixture setup failed. Cleanup journal retained.'
    throw
}
