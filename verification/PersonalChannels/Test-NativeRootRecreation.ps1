param([switch]$ReuseFolder)
# Synthetic local verification only; no production or main-server changes.
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$journal=Join-Path $PSScriptRoot 'bin/native-client-state.json'
$stage='setup';$identity=$null;$restartVerified=$false
function SaveJournal {$state|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $journal -Encoding UTF8}
function Observe($label,$path,$headers,$expected,$marker=$null){
    $r=Request $path $headers
    $matches=$null
    if($marker){$matches=$r.Status -eq 200 -and $r.Text.Contains($marker)}
    $rows.Add(@{Label=$label;Status=$r.Status;Expected=$expected;MatchesExpectation=$r.Status -eq $expected;CorrectOwnMarker=$matches;ContainsOldA=$r.Text.Contains('PrivateNativeVideo_a_client');ContainsRecreatedB=$r.Text.Contains('PrivateNativeVideo_b_recreated')})
    return $r
}
try {
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $state=Get-Content -LiteralPath $journal -Raw|ConvertFrom-Json
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Root recreation test`", Device=`"Isolated`", DeviceId=`"root-recreate-$owner`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Invalid ordinary test account'}
        $subjects[$owner]=@{User=$u;Library=$l;Headers=@{'X-Emby-Token'=$login.AccessToken}}
    }
    $a=$subjects.a;$b=$subjects.b
    $originalProbe=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe'
    Check 'Baseline A own' "Users/$($a.User.UserId)/Items/$($a.Library.VideoId)" $a.Headers 200|Out-Null
    Check 'Baseline B own' "Users/$($b.User.UserId)/Items/$($b.Library.VideoId)" $b.Headers 200|Out-Null
    Check 'Baseline B foreign A' "Users/$($b.User.UserId)/Items/$($a.Library.VideoId)" $b.Headers 404|Out-Null
    $stage='native deletion'
    $config=Join-Path $root 'data/data/personal-channels-fixture.json.guard.json';$hash=(Get-FileHash $config).Hash
    Call 'PersonalChannelsFixture/ApproveFixtureRootDeletion' $admin Post @{RootKey=[long]$a.Library.LibraryId}|Out-Null
    Call 'Library/VirtualFolders/Delete' $admin Post @{Id=$a.Library.LibraryId}|Out-Null
    $gone=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($a.Library.LibraryId)"
    $videoGone=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($a.Library.VideoId)"
    if($gone.NativeItemExists -or $videoGone.NativeItemExists -or $hash -ne (Get-FileHash $config).Hash){throw 'Deletion or unchanged ownership readback failed'}
    # Remove the confirmed absent root from cleanup identities before possible ID reuse.
    $state.Libraries=@($state.Libraries|Where-Object Owner -ne 'a');SaveJournal
    $stage='same-name creation'
    $folder=if($ReuseFolder){$a.Library.Folder}else{Join-Path $PSScriptRoot 'bin/native-client/b-recreated'}
    $file=Join-Path $folder 'PrivateNativeVideo_b_recreated.mp4'
    $state.Files+=@($file);SaveJournal
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    if($ReuseFolder){
        $oldFile=[IO.Path]::GetFullPath((Join-Path $a.Library.Folder 'PrivateNativeVideo_a_client.mp4'))
        $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin/native-client/a'))+[IO.Path]::DirectorySeparatorChar
        if(-not $oldFile.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe synthetic file removal'}
        Remove-Item -LiteralPath $oldFile
    }
    Copy-Item -LiteralPath (Join-Path $b.Library.Folder 'PrivateNativeVideo_b_client.mp4') -Destination $file
    Call 'Library/VirtualFolders' $admin Post @{Name=$a.Library.Name;CollectionType='homevideos';Paths=@($folder);RefreshLibrary=$true;LibraryOptions=@{EnableRealtimeMonitor=$false;SaveLocalMetadata=$false;TypeOptions=@(@{Type='Video';MetadataFetchers=@();ImageFetchers=@()})}}|Out-Null
    $probe=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe'
    if(-not $probe.Exists){throw 'Native recreated root missing'}
    $state.Libraries+=@(@{Owner='b-recreated';Name=$a.Library.Name;LibraryId=[string]$probe.RootKey;LibraryGuid=[string]$probe.RootGuid;Folder=$folder});SaveJournal
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do{$probe=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe';if(@($probe.Videos).Count -eq 1){break};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow -lt $deadline)
    if(@($probe.Videos).Count -ne 1 -or $probe.Videos[0].Name -ne 'PrivateNativeVideo_b_recreated'){throw 'Recreated video scan missing'}
    $newVideo=$probe.Videos[0]
    $sourceHash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $identity=@{SameNativeRootKey=[string]$probe.RootKey -eq [string]$a.Library.LibraryId;SameNativeRootGuid=[string]$probe.RootGuid -eq [string]$a.Library.LibraryGuid;SameVideoKey=[string]$newVideo.Key -eq [string]$a.Library.VideoId;NewRootKey=$probe.RootKey;NewRootGuid=$probe.RootGuid;NewVideoKey=$newVideo.Key;NewVideoGuid=$newVideo.Guid}
    $identity.SamePhysicalParentKey=[string]$newVideo.ParentKey -eq [string]$originalProbe.Videos[0].ParentKey
    $identity.SamePhysicalParentGuid=[string]$newVideo.ParentGuid -eq [string]$originalProbe.Videos[0].ParentGuid
    $policy=(Call "Users/$($b.User.UserId)").Policy
    $policy.EnabledFolders=@($b.Library.LibraryGuid,$probe.RootGuid)|Select-Object -Unique
    Call "Users/$($b.User.UserId)/Policy" $admin Post $policy|Out-Null
    $readback=(Call "Users/$($b.User.UserId)").Policy
    if($readback.EnableAllFolders -or $probe.RootGuid -notin $readback.EnabledFolders){throw 'B native folder policy readback failed'}
    $mapping=@{};$mapping[$a.Library.LibraryId]=$a.User.UserId;$mapping[$b.Library.LibraryId]=$b.User.UserId;$mapping[[string]$probe.RootKey]=$b.User.UserId
    $stage='owner mapping'
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$mapping}|Out-Null
    foreach($phase in @('after recreation','after restart')){
        if($phase -eq 'after restart'){
            $stage='restart';$oldBoot=(Call 'PersonalChannelsFixture/Guard').BootId
            & $control -Stop|Out-Null
            & $control|Out-Null
            $deadline=[DateTime]::UtcNow.AddSeconds(30);$ready=$null
            do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready -and $ready.Enabled -and $ready.BootId -ne $oldBoot){break}}catch{};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow -lt $deadline)
            $restartVerified=$ready.Ready -and $ready.Enabled -and $ready.BootId -ne $oldBoot
            if(-not $restartVerified){throw 'Recreation restart not ready'}
        }
        $stage=$phase
        $nativeProbe=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe'
        $referenceStatus=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($newVideo.Key)"
        $parentStatus=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($nativeProbe.Videos[0].ParentKey)"
        $nativeVisibility=Call "PersonalChannelsFixture/NativeVisibilityTrace?ItemKey=$($newVideo.Key)&UserKey=$($b.User.UserId)&Reset=true"
        $rows.Add(@{Label="$phase native diagnostic";VideoRoots=$nativeProbe.Videos[0].CollectionRoots;KnownPrivate=$referenceStatus.KnownPrivate;Quarantined=$referenceStatus.Quarantined;ParentKey=$nativeProbe.Videos[0].ParentKey;ParentGuid=$nativeProbe.Videos[0].ParentGuid;ParentKnownPrivate=$parentStatus.KnownPrivate;ParentQuarantined=$parentStatus.Quarantined;NativeVisible=$nativeVisibility.Visible;NativeStandalone=$nativeVisibility.Standalone;EnabledFolders=(Call "Users/$($b.User.UserId)").Policy.EnabledFolders})
        Observe "$phase B original own" "Users/$($b.User.UserId)/Items/$($b.Library.VideoId)" $b.Headers 200 'PrivateNativeVideo_b_client'|Out-Null
        foreach($reference in @([string]$probe.RootKey,[string]$probe.RootGuid,[string]$newVideo.Key,[string]$newVideo.Guid)){
            $marker=if($reference -in @([string]$newVideo.Key,[string]$newVideo.Guid)){'PrivateNativeVideo_b_recreated'}else{'Private Native Fixture a'}
            Observe "$phase B recreated own $reference" "Users/$($b.User.UserId)/Items/$reference" $b.Headers 200 $marker|Out-Null
            Observe "$phase A foreign recreated $reference" "Users/$($a.User.UserId)/Items/$reference" $a.Headers 404|Out-Null
        }
        foreach($owner in @('a','b')){
            Observe "$phase $owner old A video" "Users/$($subjects[$owner].User.UserId)/Items/$($a.Library.VideoId)" $subjects[$owner].Headers 404|Out-Null
        }
        $playback=Observe "$phase B recreated playback" "Items/$($newVideo.Key)/PlaybackInfo?UserId=$($b.User.UserId)" $b.Headers 200
        $correctSource=$false
        if($playback.Status -eq 200){$p=$playback.Text|ConvertFrom-Json;$correctSource=@($p.MediaSources|Where-Object Path -eq $file).Count -gt 0}
        $rows[$rows.Count-1].CorrectOwnSource=$correctSource
        Observe "$phase A recreated playback" "Items/$($newVideo.Key)/PlaybackInfo?UserId=$($a.User.UserId)" $a.Headers 404|Out-Null
        foreach($actor in @('b','a','anonymous')){
            $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
            $r=Request "Items/$($newVideo.Key)/Download" $headers
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$digest=[BitConverter]::ToString($sha.ComputeHash([byte[]]$r.Bytes)).Replace('-','')}finally{$sha.Dispose()}
            $expected=if($actor -eq 'b'){200}else{404}
            $rows.Add(@{Label="$phase $actor recreated raw download";Status=$r.Status;Expected=$expected;MatchesExpectation=$r.Status -eq $expected;PayloadBytes=$r.Bytes.Length;MatchesRecreatedSource=$digest -eq $sourceHash})
        }
    }
    $completed=$true
}finally{
    $report=if($ReuseFolder){'bin/native-root-recreation-reused-folder-results.json'}else{'bin/native-root-recreation-results.json'}
    @{Completed=$completed;ReuseFolder=$ReuseFolder.IsPresent;LastStage=$stage;Identity=$identity;RestartVerified=$restartVerified;Observations=$rows.ToArray();Scope='Same native library name recreated for B; direct numeric/GUID metadata, PlaybackInfo and raw download'}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot $report) -Encoding UTF8
    try{& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null}finally{$client.Dispose()}
}
Write-Output ('Recreation observations='+$rows.Count+'; expectation mismatches='+@($rows|Where-Object {$_.MatchesExpectation -eq $false}).Count)
