param([switch]$Converted)
# Timing-only synthetic native preparation/deletion overlap, no production edits.
$DeleteRoot=$true
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$overlap=$false;$gateFinal=$null;$oldBoot=$null
$stage='setup';$initialGate=$null
$creationClient=$null;$creationMessage=$null;$creationTask=$null
$convertedOutput=$null;$convertedReadback=$null
function StartPreparation {
    $task=@((Call 'ScheduledTasks')|Where-Object Key -eq 'SyncPrepare')
    if($task.Count -ne 1){throw 'Native preparation task missing'}
    Call "ScheduledTasks/Running/$($task[0].Id)" $admin Post|Out-Null
}
function WaitBReady {
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do{$items=Call "Sync/JobItems?JobId=$($subjects.b.JobId)" $subjects.b.Headers;if($items.Items.Count -eq 1 -and $items.Items[0].Status -eq 'ReadyToTransfer'){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if($items.Items.Count -ne 1 -or $items.Items[0].Status -ne 'ReadyToTransfer'){throw 'B own native file not ready'}
    $subjects.b.JobItemId=[string]$items.Items[0].Id
}
& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
try{
    $journalPath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
    $journal=Get-Content $journalPath -Raw|ConvertFrom-Json
    $journal|Add-Member NoteProperty SyncJobs @()
    $info=Call 'System/Info/Public';$initial=Call 'PersonalChannelsFixture/Guard'
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $initial.Ready){throw 'Wrong isolated server'}
    Call 'PersonalChannelsFixture/Surface'|Out-Null
    foreach($owner in @('b','a')){
        $u=@($journal.Users|Where-Object Owner -eq $owner)[0];$l=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $target="native-write-race-$owner"
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Native write race test`", Device=`"Isolated`", DeviceId=`"$target`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary subject'}
        $headers=@{'X-Emby-Token'=$login.AccessToken}
        $capabilities=@{Id=$login.SessionInfo.Id;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@()}
        if($Converted -and $owner -eq 'a'){$capabilities.DeviceProfile=@{Name='Synthetic MPEG4 Sync';DirectPlayProfiles=@();TranscodingProfiles=@(@{Container='mp4';Type='Video';VideoCodec='mpeg4';AudioCodec='aac';Context='Static';Protocol='http'})}}
        Call 'Sessions/Capabilities/Full' $headers Post $capabilities|Out-Null
        if(@((Call "Sync/Targets?UserId=$($u.UserId)" $headers)|Where-Object Id -eq $target).Count -ne 1){throw 'Native target missing'}
        if($owner -eq 'a'){
            Call 'PersonalChannelsFixture/NativeSyncWriteGate' $admin Post @{SourceKey=[long]$l.VideoId;Converted=$Converted.IsPresent}|Out-Null
            Call 'PersonalChannelsFixture/ApproveFixtureRootDeletion' $admin Post @{RootKey=[long]$l.LibraryId}|Out-Null
        }
        $stage="creating $owner job"
        if($owner -eq 'a'){
            # This installed server prepares Original inside CreateJob. Send
            # creation asynchronously so its native write pause is observable.
            $creationClient=[System.Net.Http.HttpClient]::new();$creationClient.Timeout=[TimeSpan]::FromSeconds(45)
            $creationMessage=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post,"$base/Sync/Jobs")
            $creationMessage.Headers.TryAddWithoutValidation('X-Emby-Token',[string]$headers['X-Emby-Token'])|Out-Null
            $body=@{TargetId=$target;ItemIds=@($l.VideoId);UserId=$u.UserId;Quality='Original';Profile='Original';Downloaded=$false}
            if($Converted){$body.Quality='Custom';$body.Profile='General';$body.Bitrate=100000;$body.Container='mp4';$body.VideoCodec='mpeg4';$body.AudioCodec='aac'}
            $payload=$body|ConvertTo-Json -Depth 10
            $creationMessage.Content=[System.Net.Http.StringContent]::new($payload,[Text.Encoding]::UTF8,'application/json')
            $file=Join-Path $l.Folder 'PrivateNativeVideo_a_client.mp4'
            $subjects.a=@{UserId=$u.UserId;Headers=$headers;SourceHash=(Get-FileHash $file -Algorithm SHA256).Hash;Library=$l;Target=$target}
            $creationTask=$creationClient.SendAsync($creationMessage)
            break
        }
        $created=Call 'Sync/Jobs' $headers Post @{TargetId=$target;ItemIds=@($l.VideoId);UserId=$u.UserId;Quality='Original';Profile='Original';Downloaded=$false}
        $job=if($created.Job){$created.Job}else{$created}
        if(-not $job.Id -or $job.Name -ne "PrivateNativeVideo_${owner}_client"){throw 'Unexpected synthetic job'}
        $journal.SyncJobs+=@(@{JobId=[string]$job.Id;Name=$job.Name});$journal|ConvertTo-Json -Depth 12|Set-Content $journalPath -Encoding UTF8
        $file=Join-Path $l.Folder "PrivateNativeVideo_${owner}_client.mp4"
        $subjects[$owner]=@{UserId=$u.UserId;Headers=$headers;JobId=[string]$job.Id;SourceHash=(Get-FileHash $file -Algorithm SHA256).Hash;Library=$l;Target=$target}
        if($owner -eq 'b'){
            $stage='preparing B positive'
            StartPreparation;WaitBReady
            Check 'B own Original before overlap' "Sync/JobItems/$($subjects.b.JobItemId)/File" $headers 200 'b'|Out-Null
            $deadline=[DateTime]::UtcNow.AddSeconds(20)
            do{$task=@((Call 'ScheduledTasks')|Where-Object Key -eq 'SyncPrepare')[0];if($task.State -eq 'Idle'){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
            if($task.State -ne 'Idle'){throw 'B preparation did not finish'}
        }
    }
    if($Converted){
        $stage='starting native conversion'
        $creationResponse=$creationTask.GetAwaiter().GetResult()
        $creationStatus=[int]$creationResponse.StatusCode
        $created=$creationResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
        $creationResponse.Dispose()
        $job=if($created.Job){$created.Job}else{$created}
        if($creationStatus -ne 200 -or -not $job.Id -or $job.Name -ne 'PrivateNativeVideo_a_client'){throw 'Converted A creation failed'}
        $journal.SyncJobs+=@(@{JobId=[string]$job.Id;Name=$job.Name});$journal|ConvertTo-Json -Depth 12|Set-Content $journalPath -Encoding UTF8
        StartPreparation
    }
    $stage='waiting for gate'
    $deadline=[DateTime]::UtcNow.AddSeconds(15);$gate=$null
    do{$gate=Call 'PersonalChannelsFixture/NativeSyncWriteGate';if($gate.Reached -and $gate.Active){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $gate.Active -or -not $gate.NativeOutputFileExists -or -not $gate.OutputMatchesExpectedFixture -or $gate.JobKey -le 0 -or $gate.ItemKey -le 0){throw 'Relevant native pause not confirmed'}
    $initialGate=$gate
    if($Converted){
        $path=[IO.Path]::GetFullPath($gate.CapturedOutputPath)
        $allowed=[IO.Path]::GetFullPath((Join-Path $root 'data/sync'))+[IO.Path]::DirectorySeparatorChar
        if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or $gate.CapturedOutputHash -eq $subjects.a.SourceHash){throw 'Not a distinct converted native output'}
        $convertedOutput=@{Path=$path;Hash=$gate.CapturedOutputHash}
        $mediaText=& (Join-Path $root 'server/system/ffprobe.exe') -v error -show_entries stream=codec_name,codec_type -show_entries format=duration -of json $path
        if($LASTEXITCODE -ne 0){throw 'Converted race output not probed'}
        $media=($mediaText -join "`n")|ConvertFrom-Json
        $codec=@($media.streams|Where-Object codec_type -eq 'video')[0].codec_name
        $convertedReadback=@{VideoCodec=$codec;DurationSeconds=[double]$media.format.duration;Bytes=$gate.CapturedOutputBytes;DifferentFromOriginalHash=$true}
        if($codec -ne 'mpeg4' -or $convertedReadback.DurationSeconds -lt 5){throw 'Race did not involve actual MPEG4 conversion'}
        $subjects.a.SourceHash=$gate.CapturedOutputHash
    }
    $subjects.a.JobId=[string]$gate.JobKey
    $subjects.a.JobItemId=[string]$gate.ItemKey
    $journal.SyncJobs+=@(@{JobId=[string]$gate.JobKey;Name='PrivateNativeVideo_a_client'});$journal|ConvertTo-Json -Depth 12|Set-Content $journalPath -Encoding UTF8
    $config=Join-Path $root 'data/data/personal-channels-fixture.json.guard.json';$hash=(Get-FileHash $config -Algorithm SHA256).Hash
    $stage='native root deletion during gate'
    Call 'Library/VirtualFolders/Delete' $admin Post @{Id=$subjects.a.Library.LibraryId}|Out-Null
    $rootAfter=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($subjects.a.Library.LibraryId)"
    $sourceAfter=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($subjects.a.Library.VideoId)"
    $gateAfter=Call 'PersonalChannelsFixture/NativeSyncWriteGate'
    $overlap=-not $rootAfter.NativeItemExists -and -not $sourceAfter.NativeItemExists -and $gateAfter.Active -and -not $gateAfter.TimedOut
    if(-not $overlap -or $hash -ne (Get-FileHash $config -Algorithm SHA256).Hash){throw 'Deletion did not complete inside actual native pause'}
    $stage='releasing native gate'
    Call 'PersonalChannelsFixture/NativeSyncWriteGate' $admin Post @{Release=$true}|Out-Null
    if(-not $Converted){$creationResponse=$creationTask.GetAwaiter().GetResult();$creationStatus=[int]$creationResponse.StatusCode;$creationResponse.Dispose()}
    $rows.Add(@{Label='A native creation response';Status=$creationStatus;CompletedBeforePause=$Converted.IsPresent})
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{$gateFinal=Call 'PersonalChannelsFixture/NativeSyncWriteGate';$task=@((Call 'ScheduledTasks')|Where-Object Key -eq 'SyncPrepare')[0];if(-not $gateFinal.Active -and $task.State -eq 'Idle'){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if($gateFinal.Active -or $gateFinal.TimedOut -or $task.State -ne 'Idle'){throw 'Native worker did not finish after controlled release'}
    $features=(Call 'PersonalChannelsFixture/Surface').SyncSecurity.FeatureChecks
    if(-not @($features|Where-Object {$_.Feature -eq 'sync' -and $_.Allowed}).Count){throw 'Legitimate sync feature not observed before restart'}
    foreach($phase in @('after overlap','after restart')){
        $stage=$phase
        if($phase -eq 'after restart'){
            $oldBoot=(Call 'PersonalChannelsFixture/Guard').BootId;& $control -Stop|Out-Null;& $control|Out-Null
            $deadline=[DateTime]::UtcNow.AddSeconds(30);$ready=$null
            do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready -and $ready.Enabled -and $ready.BootId -ne $oldBoot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
            if(-not $ready.Ready -or $ready.BootId -eq $oldBoot){throw 'Race restart not ready'}
        }
        foreach($actor in @('a','b','anonymous')){
            $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
            foreach($path in @("Sync/Jobs/$($subjects.a.JobId)","Sync/JobItems?JobId=$($subjects.a.JobId)","Sync/JobItems/$($subjects.a.JobItemId)/File")){
                Check "$phase $actor old A reference" $path $headers 404|Out-Null
            }
        }
        Check "$phase B own Original" "Sync/JobItems/$($subjects.b.JobItemId)/File" $subjects.b.Headers 200 'b'|Out-Null
        $job=Call "PersonalChannelsFixture/NativeSyncJobProbe?JobKey=$($subjects.a.JobId)"
        $rows.Add(@{Label="$phase native A parent retention";ExistsInNativeManager=$job.Exists})
        ProbeItem "$phase direct native A item retention"
        if($Converted){$rows.Add(@{Label="$phase converted physical output retention";Exists=Test-Path -LiteralPath $convertedOutput.Path})}
    }
    $completed=$true
}finally{
    $report=if($Converted){'bin/native-converted-sync-root-race-results.json'}else{'bin/native-sync-prepare-root-race-results.json'}
    @{Completed=$completed;ConvertedRequested=$Converted.IsPresent;ConvertedReadback=$convertedReadback;RestartVerified=($null -ne $ready -and $ready.Ready -and $ready.Enabled -and $ready.BootId -ne $oldBoot);LastObservedGate=$gate;LastStage=$stage;RequestFailure=$RequestFailure;LegitimateSyncFeatureObservedBeforeRestart=@($features|Where-Object {$_.Feature -eq 'sync' -and $_.Allowed}).Count -gt 0;DeletionInsideConfirmedNativePause=$overlap;InitialGate=$initialGate;GateFinal=$gateFinal;Observations=$rows.ToArray();Scope='Actual native ReadyToTransfer write paused; root deletion, raw file access and native retention, before/after restart; B surviving Original positive control'}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot $report) -Encoding UTF8
    try{Call 'PersonalChannelsFixture/NativeSyncWriteGate' $admin Post @{Release=$true}|Out-Null}catch{}
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if($convertedOutput -and (Test-Path -LiteralPath $convertedOutput.Path)){
            $allowed=[IO.Path]::GetFullPath((Join-Path $root 'data/sync'))+[IO.Path]::DirectorySeparatorChar
            if(-not [IO.Path]::GetFullPath($convertedOutput.Path).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $convertedOutput.Path -Algorithm SHA256).Hash -ne $convertedOutput.Hash){throw 'Unsafe converted race cleanup'}
            Remove-Item -LiteralPath $convertedOutput.Path
        }
    }finally{
        $client.Dispose();if($creationClient){$creationClient.Dispose()};if($creationMessage){$creationMessage.Dispose()}
    }
}
Write-Output ("Native preparation/root deletion overlap="+$overlap+"; observations="+$rows.Count)
