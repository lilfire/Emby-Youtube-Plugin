# Investigation only: real native Sync conversion, no fabricated status/output.
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$stage='setup';$jobStates=@{};$outputReadbacks=@{};$featureObserved=$false;$restarted=$false
$convertedCleanupFiles=[Collections.Generic.List[object]]::new()
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $journalPath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
    $journal=Get-Content $journalPath -Raw|ConvertFrom-Json
    $journal|Add-Member NoteProperty SyncJobs @()
    foreach($owner in @('a','b')){
        $user=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $library=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $target="native-converted-sync-$owner"
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Converted Sync test`", Device=`"Isolated`", DeviceId=`"$target`", Version=`"1.0`""} Post @{Username=$user.Name;Pw=''}
        if($login.User.Id -ne $user.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary subject'}
        $headers=@{'X-Emby-Token'=$login.AccessToken}
        Call 'Sessions/Capabilities/Full' $headers Post @{Id=$login.SessionInfo.Id;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@();DeviceProfile=@{Name='Synthetic MPEG4 Sync';DirectPlayProfiles=@();TranscodingProfiles=@(@{Container='mp4';Type='Video';VideoCodec='mpeg4';AudioCodec='aac';Context='Static';Protocol='http'})}}|Out-Null
        $stage="creating $owner"
        $created=Call 'Sync/Jobs' $headers Post @{TargetId=$target;ItemIds=@($library.VideoId);UserId=$user.UserId;Quality='Custom';Profile='General';Bitrate=100000;Container='mp4';VideoCodec='mpeg4';AudioCodec='aac';Downloaded=$false}
        $job=if($created.Job){$created.Job}else{$created}
        if(-not $job.Id -or $job.Name -ne "PrivateNativeVideo_${owner}_client"){throw 'Unexpected synthetic job'}
        $journal.SyncJobs+=@(@{JobId=[string]$job.Id;Name=$job.Name})
        $journal|ConvertTo-Json -Depth 12|Set-Content $journalPath -Encoding UTF8
        $source=Join-Path $library.Folder "PrivateNativeVideo_${owner}_client.mp4"
        $subjects[$owner]=@{UserId=$user.UserId;Headers=$headers;JobId=[string]$job.Id;OriginalHash=(Get-FileHash $source -Algorithm SHA256).Hash;OriginalPath=$source}
    }
    $stage='native conversion'
    Call 'PersonalChannelsFixture/Surface'|Out-Null
    $task=@((Call 'ScheduledTasks')|Where-Object Key -eq 'SyncPrepare')[0]
    if(-not $task.Id){throw 'Missing SyncPrepare'}
    Call "ScheduledTasks/Running/$($task.Id)" $admin Post|Out-Null
    foreach($owner in @('a','b')){
        $deadline=[DateTime]::UtcNow.AddSeconds(40)
        do{
            $items=Call "Sync/JobItems?JobId=$($subjects[$owner].JobId)" $subjects[$owner].Headers
            $jobStates[$owner]=@($items.Items|Select-Object Id,Status,Progress)
            if($items.Items.Count -eq 1 -and $items.Items[0].Status -in @('ReadyToTransfer','Failed')){break}
            Start-Sleep -Milliseconds 200
        }while([DateTime]::UtcNow -lt $deadline)
        if($items.Items.Count -ne 1 -or $items.Items[0].Status -ne 'ReadyToTransfer'){throw 'Actual conversion did not reach ReadyToTransfer'}
        $item=$items.Items[0];$path=[IO.Path]::GetFullPath($item.OutputPath)
        $allowed=[IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar
        if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or $path -eq [IO.Path]::GetFullPath($subjects[$owner].OriginalPath) -or -not (Test-Path -LiteralPath $path)){throw 'No distinct native converted output under isolated server'}
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $convertedCleanupFiles.Add(@{Path=$path;Hash=$hash})
        $mediaText=& (Join-Path $root 'server/system/ffprobe.exe') -v error -show_entries stream=codec_name,codec_type -show_entries format=duration -of json $path
        if($LASTEXITCODE -ne 0){throw 'Converted file not probed'}
        $media=($mediaText -join "`n")|ConvertFrom-Json
        $video=@($media.streams|Where-Object codec_type -eq 'video')[0]
        $readback=@{DistinctOutputPath=$true;DifferentFromOriginalHash=$hash -ne $subjects[$owner].OriginalHash;VideoCodec=$video.codec_name;DurationSeconds=[double]$media.format.duration;PayloadBytes=(Get-Item -LiteralPath $path).Length;NativeReadyToTransfer=$true}
        $outputReadbacks[$owner]=$readback
        if(-not $readback.DifferentFromOriginalHash -or $video.codec_name -ne 'mpeg4' -or $readback.DurationSeconds -lt 5){throw 'Output did not verify actual MPEG4 conversion'}
        $subjects[$owner].SourceHash=$hash;$subjects[$owner].JobItemId=[string]$item.Id
    }
    $features=(Call 'PersonalChannelsFixture/Surface').SyncSecurity.FeatureChecks
    $featureObserved=@($features|Where-Object {$_.Feature -eq 'sync' -and $_.Allowed}).Count -gt 0
    if(-not $featureObserved){throw 'No legitimate Sync feature check'}
    foreach($phase in @('before restart','after restart')){
        if($phase -eq 'after restart'){
            $stage='restart';$oldBoot=(Call 'PersonalChannelsFixture/Guard').BootId
            & $control -Stop|Out-Null
            & $control|Out-Null
            $deadline=[DateTime]::UtcNow.AddSeconds(30);$ready=$null
            do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready -and $ready.Enabled -and $ready.BootId -ne $oldBoot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
            $restarted=$ready.Ready -and $ready.Enabled -and $ready.BootId -ne $oldBoot
            if(-not $restarted){throw 'Guard not ready after restart'}
        }
        $stage=$phase
        foreach($owner in @('a','b')){
            $other=if($owner -eq 'a'){'b'}else{'a'}
            Check "$phase $owner own converted file" "Sync/JobItems/$($subjects[$owner].JobItemId)/File" $subjects[$owner].Headers 200 $owner|Out-Null
            Check "$phase $other foreign converted $owner file" "Sync/JobItems/$($subjects[$owner].JobItemId)/File" $subjects[$other].Headers 404|Out-Null
            Check "$phase anonymous converted $owner file" "Sync/JobItems/$($subjects[$owner].JobItemId)/File" @{} 404|Out-Null
            $own=Check "$phase $owner own Ready list" "Sync/Items/Ready?TargetId=native-converted-sync-$owner" $subjects[$owner].Headers 200
            if(-not $own.Text.Contains("PrivateNativeVideo_${owner}_client") -or $own.Text.Contains("PrivateNativeVideo_${other}_client")){throw 'Ready list failed own/foreign marker control'}
        }
    }
    $completed=$true
}finally{
    @{Completed=$completed;LastStage=$stage;RestartVerified=$restarted;LegitimateSyncFeatureObserved=$featureObserved;NativeJobStates=$jobStates;OutputReadbacks=$outputReadbacks;Observations=$rows.ToArray();Scope='Native MPEG4 converted Sync files for ordinary A/B; full owner payload hashes, cross-account/anonymous raw denials and Ready lists before/after restart'}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot 'bin/native-converted-sync-files-results.json') -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        foreach($record in $convertedCleanupFiles){
            $path=[IO.Path]::GetFullPath($record.Path)
            $allowed=[IO.Path]::GetFullPath((Join-Path $root 'data/sync'))+[IO.Path]::DirectorySeparatorChar
            if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe converted-output cleanup'}
            if(Test-Path -LiteralPath $path){
                if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $record.Hash){throw 'Converted output changed before cleanup'}
                Remove-Item -LiteralPath $path
            }
        }
        $cleanup=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json
        @{UsersGone=$cleanup.UsersGone;LibrariesGone=$cleanup.LibrariesGone;SourceMediaGone=$cleanup.MediaGone;FixtureGone=$cleanup.FixtureGone;GuardGone=$cleanup.GuardGone;ConvertedOutputsGone=@($convertedCleanupFiles|Where-Object{Test-Path -LiteralPath $_.Path}).Count -eq 0;ServerStopped=@(Get-Process EmbyServer -ErrorAction SilentlyContinue).Count -eq 0}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'bin/native-converted-sync-files-cleanup.json') -Encoding UTF8
    }finally{$client.Dispose()}
}
Write-Output ('Converted Sync observations='+$rows.Count)
