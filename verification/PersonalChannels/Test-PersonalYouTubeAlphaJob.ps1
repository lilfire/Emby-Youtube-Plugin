. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
$stage='setup';$workerStarted=$false;$library=$null
if(Test-Path -LiteralPath $profileRoot){throw 'Alpha job test requires absent isolated profiles'}
function WaitAlphaJob($state){
    $deadline=[DateTime]::UtcNow.AddMinutes(3)
    do{
        $job=Call 'YouTubePlugin/MyJob' $subjects.a.Headers
        if($job.State -eq $state){return $job}
        if($job.State -eq 'Failed'){throw ('Alpha job failed: '+$job.ErrorCode)}
        Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $deadline)
    throw ('Alpha job did not reach '+$state)
}
function PersonalLibraryCount($libraries){
    $managedBase=[IO.Path]::GetFullPath((Join-Path $profileRoot 'media'))+[IO.Path]::DirectorySeparatorChar
    return @($libraries|Where-Object{$_.Locations.Count -eq 1 -and [IO.Path]::GetFullPath($_.Locations[0]).StartsWith($managedBase)}).Count
}
function RestartAlphaWorker([switch]$PendingStatus){
    $before=(Call 'PersonalChannelsFixture/Guard').BootId
    Call 'PersonalChannelsFixture/PersonalJobs' $admin Delete|Out-Null
    $script:workerStarted=$false
    & $control -Stop|Out-Null
    if($PendingStatus){
        # Model the durable window after activation but before Ready. Modify
        # only the synthetic owner's job status while the server is stopped.
        $statusPath=Join-Path $profileRoot ('jobs/'+$subjects.a.UserId+'.json')
        $persisted=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json
        if($persisted.State -ne 'Ready'){throw 'Recovery setup requires a completed publication'}
        $persisted.State='Publishing';$persisted.LibraryId=$null
        $persisted|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statusPath -Encoding UTF8
    }
    & $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $before){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $before){throw 'Alpha server restart was not verified'}
    $mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production controls unavailable after restart'}
    $started=Call 'PersonalChannelsFixture/PersonalJobs' $admin Post @{}
    $script:workerStarted=$started.Started
    if(-not $script:workerStarted){throw 'Alpha worker did not restart'}
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $statePath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
    $journal=Get-Content $statePath -Raw|ConvertFrom-Json
    foreach($actor in @('a','b')){
        $user=@($journal.Users|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Closed alpha job verification`", Device=`"Isolated`", DeviceId=`"alpha-job-$actor`", Version=`"1`""} Post @{Username=$user.Name;Pw=''}
        if($login.User.Id -ne $user.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong alpha test identity'}
        $subjects[$actor]=@{UserId=$user.UserId;Headers=@{'X-Emby-Token'=$login.AccessToken}}
    }
    $bPolicy=(Call "Users/$($subjects.b.UserId)").Policy
    $bPolicy.EnableAllFolders=$true
    Call "Users/$($subjects.b.UserId)/Policy" $admin Post $bPolicy|Out-Null
    $aPolicyBefore=(Call "Users/$($subjects.a.UserId)").Policy
    if($aPolicyBefore.EnableAllFolders){throw 'A positive control requires restricted native folders'}
    $mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production controls unavailable'}
    $started=Call 'PersonalChannelsFixture/PersonalJobs' $admin Post @{}
    $workerStarted=$started.Started
    if(-not $workerStarted){throw 'Production job runtime did not start'}
    $draft=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post @{ExpectedRevision=0;Channels=@()}
    $waiting=WaitAlphaJob 'WaitingForSettings'
    if($waiting.State -ne 'WaitingForSettings'){throw 'Empty profile unexpectedly started media extraction'}
    $rows.Add(@{Label='Saving incomplete settings reports WaitingForSettings';State=$waiting.State})
    $media=Join-Path $profileRoot ('media/'+$subjects.a.UserId+'/'+$draft.CollectionId.Replace('-','')+'/'+$draft.GenerationId.Replace('-',''))
    $library=@{Owner='alpha';Name=('YouTube '+$draft.GenerationId.Replace('-',''));LibraryId='';Folder=$media;PlannedRenameName=('YouTube '+$draft.GenerationId.Replace('-',''))}
    $journal.Libraries+=@($library)
    $journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    $stage='save starts production background job'
    $saved=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post @{ExpectedRevision=$draft.Revision;Channels=@('UC'+('a'*22));ApiKey='synthetic-alpha-personal-key'}
    $deadline=[DateTime]::UtcNow.AddMinutes(3)
    $seen=@()
    do{
        $job=Call 'YouTubePlugin/MyJob' $subjects.a.Headers
        $seen+=@($job.State)
        if($job.OwnerUserId.Replace('-','') -ne $subjects.a.UserId -or $job.ProfileRevision -ne $saved.Revision){throw 'Job owner or profile revision mismatch'}
        if($job.State -eq 'Failed'){throw 'Production alpha background job failed'}
        if($job.State -eq 'Ready'){break}
        Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $deadline)
    if($job.State -ne 'Ready' -or -not $job.LibraryId -or $job.TotalVideos -ne 1){throw 'Production job did not publish expected video'}
    $library.LibraryId=[string]$job.LibraryId
    $journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    $rows.Add(@{Label='Authenticated profile save completes actual background publication';State=$job.State;ObservedStates=@($seen|Select-Object -Unique);Videos=$job.TotalVideos})
    $other=Call ('YouTubePlugin/MyJob?OwnerUserId='+$subjects.a.UserId) $subjects.b.Headers
    if($other.OwnerUserId.Replace('-','') -ne $subjects.b.UserId -or $other.LibraryId -or $other.State -ne 'Idle'){throw 'B received A private job status'}
    $rows.Add(@{Label='Forged owner query returns only B own job status';State=$other.State;LibraryId=$other.LibraryId})
    $aPolicyAfter=(Call "Users/$($subjects.a.UserId)").Policy
    $bPolicyAfter=(Call "Users/$($subjects.b.UserId)").Policy
    if($aPolicyAfter.EnableAllFolders -or $aPolicyAfter.EnabledFolders.Count -ne $aPolicyBefore.EnabledFolders.Count+1 -or -not $bPolicyAfter.EnableAllFolders){throw 'Native policy grant changed unrelated folder permissions'}
    $rows.Add(@{Label='Restricted A gains only its own new library; B broad policy preserved';AEnableAllFolders=$false;AddedAFolders=1;BEnableAllFolders=$true})
    $stage='native views and playback'
    $ownViews=Call "Users/$($subjects.a.UserId)/Views" $subjects.a.Headers
    if($job.LibraryId.ToString() -notin @($ownViews.Items|ForEach-Object Id)){throw 'New library absent from ordinary owner views'}
    $foreignViews=Call "Users/$($subjects.b.UserId)/Views" $subjects.b.Headers
    if([string]$job.LibraryId -in @($foreignViews.Items|ForEach-Object Id)){throw 'B views disclose A library'}
    if(@($ownViews.Items|Where-Object Id -eq ([string]$job.LibraryId))[0].Name -ne 'YouTube'){throw 'Library display name contains an internal generation identifier'}
    $items=Call "Users/$($subjects.a.UserId)/Items?ParentId=$($job.LibraryId)&Recursive=true&IncludeItemTypes=Video" $subjects.a.Headers
    if($items.Items.Count -ne 1){throw 'Published video absent from ordinary library query'}
    $video=$items.Items[0].Id
    $metadata=Call "Users/$($subjects.a.UserId)/Items/$video`?Fields=Overview" $subjects.a.Headers
    if($metadata.Name -ne 'Public upstream test video' -or $metadata.Overview -ne '&lt;b&gt;Untrusted catalog description&lt;/b&gt;'){throw 'Native video metadata missing or unsafe'}
    $rows.Add(@{Label='Readable native library/video names and encoded provider description';LibraryName='YouTube';VideoTitle='Public upstream test video';DescriptionEncoded=$true})
    $own=Request "Videos/$video/stream.mp4?Static=true" $subjects.a.Headers
    $foreign=Request "Videos/$video/stream.mp4?Static=true" $subjects.b.Headers
    if($own.Status -ne 200 -or $own.Bytes.Length -le 1000 -or $foreign.Status -ne 404){throw 'Background-published video playback boundary failed'}
    $rows.Add(@{Label='Ordinary library discovery and native video response';OwnerVideoStatus=$own.Status;OwnerBytes=$own.Bytes.Length;ForeignVideoStatus=$foreign.Status})
    foreach($pending in @($false,$true)){
        $stage=if($pending){'recovery after native activation before Ready'}else{'completed library survives actual server restart'}
        $beforeJob=$job
        RestartAlphaWorker -PendingStatus:$pending
        $job=WaitAlphaJob 'Ready'
        $afterItems=Call "Users/$($subjects.a.UserId)/Items?ParentId=$($job.LibraryId)&Recursive=true&IncludeItemTypes=Video" $subjects.a.Headers
        $nativeLibraries=(Call 'Library/VirtualFolders/Query' $admin).Items
        $ownAfter=Request "Videos/$video/stream.mp4?Static=true" $subjects.a.Headers
        $foreignAfter=Request "Videos/$video/stream.mp4?Static=true" $subjects.b.Headers
        $rows.Add(@{Label='Restart identity and playback readback';Pending=$pending;SameRoot=($job.LibraryId -eq $beforeJob.LibraryId);SameRevision=($job.ProfileRevision -eq $saved.Revision);VideoCount=$afterItems.Items.Count;SameVideo=($afterItems.Items[0].Id -eq $video);PersonalLibraryCount=(PersonalLibraryCount $nativeLibraries);OwnerStatus=$ownAfter.Status;ForeignStatus=$foreignAfter.Status})
        if($job.LibraryId -ne $beforeJob.LibraryId -or $job.ProfileRevision -ne $saved.Revision -or $afterItems.Items.Count -ne 1 -or
            $afterItems.Items[0].Id -ne $video -or (PersonalLibraryCount $nativeLibraries) -ne 1 -or
            $ownAfter.Status -ne 200 -or $foreignAfter.Status -ne 404){throw 'Restart changed identities, duplicated library or broke playback boundary'}
        if(-not $pending -and $job.JobId -ne $beforeJob.JobId){throw 'Completed job unexpectedly republished at restart'}
        $rows.Add(@{Label=$stage;ActualServerRestart=$true;SimulatedPendingStatus=$pending;SameRoot=$true;SameVideo=$true;NativeLibraryCount=1;OwnerVideoStatus=$ownAfter.Status;ForeignVideoStatus=$foreignAfter.Status})
    }
    $stage='channel replacement retains key and removes old generation'
    $oldVideo=$video;$oldRoot=$job.LibraryId;$oldMedia=$media
    $bMedia=@($journal.Files|Where-Object{$_ -like '*PrivateNativeVideo_b_client.mp4'})[0]
    $bHashBefore=(Get-FileHash -LiteralPath $bMedia).Hash
    $saved=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post @{ExpectedRevision=$saved.Revision;Channels=@('UC'+('b'*22))}
    if($saved.GenerationId -eq $draft.GenerationId -or -not $saved.HasApiKey){throw 'Published replacement reused identity or discarded owner key'}
    $media=Join-Path $profileRoot ('media/'+$subjects.a.UserId+'/'+$saved.CollectionId.Replace('-','')+'/'+$saved.GenerationId.Replace('-',''))
    $replacement=@{Owner='alpha-refresh';Name=('YouTube '+$saved.GenerationId.Replace('-',''));LibraryId='';Folder=$media;PlannedRenameName=('YouTube '+$saved.GenerationId.Replace('-',''))}
    $journal.Libraries+=@($replacement);$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    $job=WaitAlphaJob 'Ready'
    $replacement.LibraryId=[string]$job.LibraryId
    $journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    if($job.LibraryId -eq $oldRoot -or (Test-Path -LiteralPath $oldMedia)){throw 'Replacement kept retired native root or media'}
    $nativeLibraries=(Call 'Library/VirtualFolders/Query' $admin).Items
    if([string]$oldRoot -in @($nativeLibraries|ForEach-Object ItemId) -or (PersonalLibraryCount $nativeLibraries) -ne 1){throw 'Replacement left duplicate native libraries'}
    $stale=Request "Videos/$oldVideo/stream.mp4?Static=true" $subjects.a.Headers
    if($stale.Status -ne 404){throw 'Retired video reference still usable'}
    $items=Call "Users/$($subjects.a.UserId)/Items?ParentId=$($job.LibraryId)&Recursive=true&IncludeItemTypes=Video" $subjects.a.Headers
    if($items.Items.Count -ne 1){throw 'Replacement video absent from ordinary library'}
    $video=$items.Items[0].Id
    $newStream=Request "Videos/$video/stream.mp4?Static=true" $subjects.a.Headers
    if($newStream.Status -ne 200 -or (Get-FileHash -LiteralPath $bMedia).Hash -ne $bHashBefore){throw 'Replacement broke playback or modified B media'}
    $rows.Add(@{Label='Channel replacement preserves key, removes old root/files and stale references';GenerationChanged=$true;OldMediaGone=$true;OldVideoStatus=$stale.Status;NewVideoStatus=$newStream.Status;BMediaUnchanged=$true})
    $stage='actual interruption during native Preparing creation'
    $saved=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post @{ExpectedRevision=$saved.Revision;Channels=@('UC'+('b'*22))}
    $pendingName='YouTube '+$saved.GenerationId.Replace('-','')
    $pendingMedia=Join-Path $profileRoot ('media/'+$subjects.a.UserId+'/'+$saved.CollectionId.Replace('-','')+'/'+$saved.GenerationId.Replace('-',''))
    $pendingLibrary=@{Owner='alpha-crash';Name=$pendingName;LibraryId='';Folder=$pendingMedia;PlannedRenameName=$pendingName}
    $journal.Libraries+=@($pendingLibrary);$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    Call 'PersonalChannelsFixture/NativeCreationGate' $admin Post @{Name=$pendingName;ReserveIdentity=$false}|Out-Null
    $deadline=[DateTime]::UtcNow.AddMinutes(3)
    do{$gate=Call 'PersonalChannelsFixture/NativeCreationGate';if($gate.Active){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $gate.Active -or -not $gate.NativeExists -or $gate.TimedOut -or $gate.Locations.Count -ne 0){throw 'Actual crash requires a live native pre-source publication'}
    $pendingLibrary.LibraryId=[string]$gate.InternalId
    $journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    $beforeBoot=(Call 'PersonalChannelsFixture/Guard').BootId
    $testPid=[int](Get-Content -LiteralPath (Join-Path $root 'server.pid'))
    $testProcess=Get-Process -Id $testPid
    $expectedExecutable=[IO.Path]::GetFullPath((Join-Path $root 'server/system/EmbyServer.exe'))
    if($testProcess.Path -ne $expectedExecutable){throw 'Refusing to interrupt an unrelated process'}
    Stop-Process -Id $testPid -Force
    if(-not $testProcess.WaitForExit(10000)){throw 'Interrupted isolated process remained live'}
    $workerStarted=$false
    & $control -Stop|Out-Null
    & $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$guard=Call 'PersonalChannelsFixture/Guard';if($guard.Ready -and $guard.BootId -ne $beforeBoot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $guard.Ready -or $guard.BootId -eq $beforeBoot){throw 'Interrupted alpha server failed to restart'}
    $mode=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($mode.ExperimentalEnabled -or -not $mode.Production.Installed){throw 'Production controls unavailable after interruption'}
    $started=Call 'PersonalChannelsFixture/PersonalJobs' $admin Post @{};$workerStarted=$started.Started
    if(-not $workerStarted){throw 'Interrupted worker failed to recover'}
    $recoveredProfile=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers
    if($recoveredProfile.GenerationId -eq $saved.GenerationId -or -not $recoveredProfile.HasApiKey){throw 'Preparing repair failed to rotate identity and retain key'}
    $saved=$recoveredProfile
    $media=Join-Path $profileRoot ('media/'+$subjects.a.UserId+'/'+$saved.CollectionId.Replace('-','')+'/'+$saved.GenerationId.Replace('-',''))
    $recoveredLibrary=@{Owner='alpha-recovery';Name=('YouTube '+$saved.GenerationId.Replace('-',''));LibraryId='';Folder=$media;PlannedRenameName=('YouTube '+$saved.GenerationId.Replace('-',''))}
    $journal.Libraries+=@($recoveredLibrary);$journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    $job=WaitAlphaJob 'Ready';$recoveredLibrary.LibraryId=[string]$job.LibraryId
    $journal|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $statePath -Encoding UTF8
    $nativeLibraries=(Call 'Library/VirtualFolders/Query' $admin).Items
    if([string]$pendingLibrary.LibraryId -in @($nativeLibraries|ForEach-Object ItemId) -or (Test-Path -LiteralPath $pendingMedia)
        ){throw 'Recovery retained interrupted Preparing library or media'}
    if((PersonalLibraryCount $nativeLibraries) -ne 1){throw 'Recovery left duplicate personal libraries'}
    $items=Call "Users/$($subjects.a.UserId)/Items?ParentId=$($job.LibraryId)&Recursive=true&IncludeItemTypes=Video" $subjects.a.Headers
    if($items.Items.Count -ne 1){throw 'Recovered personal video missing'}
    $video=$items.Items[0].Id
    $recoveredOwn=Request "Videos/$video/stream.mp4?Static=true" $subjects.a.Headers
    $recoveredForeign=Request "Videos/$video/stream.mp4?Static=true" $subjects.b.Headers
    if($recoveredOwn.Status -ne 200 -or $recoveredForeign.Status -ne 404 -or (Get-FileHash -LiteralPath $bMedia).Hash -ne $bHashBefore){throw 'Recovered playback boundary or B media changed'}
    $rows.Add(@{Label='Actual process interruption in native Preparing and automatic recovery';ActualProcessKilled=$true;InterruptedRootGone=$true;InterruptedMediaGone=$true;NativeLibraryCount=1;OwnerVideoStatus=$recoveredOwn.Status;ForeignVideoStatus=$recoveredForeign.Status;BMediaUnchanged=$true})
    $stage='profile deletion'
    Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$saved.Revision}|Out-Null
    $deleted=WaitAlphaJob 'Deleted'
    if($deleted.State -ne 'Deleted' -or $deleted.LibraryId){throw 'Deleted collection retained active job status'}
    $revoked=Request "Videos/$video/stream.mp4?Static=true" $subjects.a.Headers
    if($revoked.Status -ne 404){throw 'Deleted background publication still accessible'}
    $nativeLibraries=(Call 'Library/VirtualFolders/Query' $admin).Items
    if([string]$job.LibraryId -in @($nativeLibraries|ForEach-Object ItemId) -or (Test-Path -LiteralPath $media) -or (Get-FileHash -LiteralPath $bMedia).Hash -ne $bHashBefore){throw 'Deletion retained managed root/files or changed B media'}
    $rows.Add(@{Label='Deletion cancels job and revokes published video';State=$deleted.State;VideoStatus=$revoked.Status})
    $completed=$true
}catch{$failure=$_.Exception.Message;throw}finally{
    try{
        @{Completed=$completed;Failure=$failure;LastStage=$stage;Observations=$rows.ToArray();Scope='Real authenticated save/status, production jobs, media and native libraries; actual restarts, simulated Publishing over active publication, real process interruption in Preparing, replacement and deletion. Controlled Google transport; no main server or physical app.'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/personal-alpha-job-results.json') -Encoding UTF8
    }finally{
        try{
            if($workerStarted){Call 'PersonalChannelsFixture/PersonalJobs' $admin Delete|Out-Null}
            & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
            if(Test-Path -LiteralPath $profileRoot){
                $expected=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
                if($profileRoot -ne $expected -or -not $profileRoot.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe alpha profile cleanup'}
                $allowed=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required','publication-journal.json','publication-journal.required','DTi8wZ1a1TA.mp4')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
                if(@(Get-ChildItem -LiteralPath $profileRoot -Recurse -Force|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (-not $_.PSIsContainer -and $_.Name -notin $allowed)}).Count){throw 'Unexpected alpha cleanup file'}
                [IO.Directory]::Delete($profileRoot,$true)
            }
        }finally{$client.Dispose()}
    }
}
Write-Output ('Personal alpha job observations='+$rows.Count)
