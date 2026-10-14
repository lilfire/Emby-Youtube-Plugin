param([switch]$DeleteRoot)
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') | Out-Null
try {
    $journalPath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
    $journal=Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
    $journal | Add-Member NoteProperty SyncJobs @()
    $info=Call 'System/Info/Public'
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong isolated server'}
    Call 'PersonalChannelsFixture/Surface' | Out-Null
    foreach ($owner in @('a','b')) {
        $user=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $library=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $target="native-owner-ready-$owner"
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Owner Ready file test`", Device=`"Isolated`", DeviceId=`"$target`", Version=`"1.0`""} Post @{Username=$user.Name;Pw=''}
        if ($login.User.Id -ne $user.UserId -or $login.User.Policy.IsAdministrator) {throw 'Unexpected synthetic subject'}
        $headers=@{'X-Emby-Token'=$login.AccessToken}
        Call 'Sessions/Capabilities/Full' $headers Post @{Id=$login.SessionInfo.Id;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@()} | Out-Null
        $targets=@((Call "Sync/Targets?UserId=$($user.UserId)" $headers)|Where-Object Id -eq $target)
        if ($targets.Count -ne 1) {throw 'Missing positive native target'}
        $created=Call 'Sync/Jobs' $headers Post @{TargetId=$target;ItemIds=@($library.VideoId);UserId=$user.UserId;Quality='Original';Profile='Original';Downloaded=$false}
        $job=if ($created.Job) {$created.Job} else {$created}
        if (-not $job.Id -or $job.Name -ne "PrivateNativeVideo_${owner}_client") {throw 'Unexpected created synthetic job'}
        $journal.SyncJobs+=@(@{JobId=[string]$job.Id;Name=$job.Name})
        $journal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $journalPath -Encoding UTF8
        $file=@($journal.Files|Where-Object {[IO.Path]::GetFileName($_) -eq "PrivateNativeVideo_${owner}_client.mp4"})[0]
        $subjects[$owner]=@{UserId=$user.UserId;Headers=$headers;JobId=[string]$job.Id;SourceHash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
    }
    $tasks=@((Call 'ScheduledTasks')|Where-Object Key -eq 'SyncPrepare')
    if ($tasks.Count -ne 1) {throw 'Missing native SyncPrepare task'}
    Call "ScheduledTasks/Running/$($tasks[0].Id)" $admin Post | Out-Null
    foreach ($owner in @('a','b')) {
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do {$items=Call "Sync/JobItems?JobId=$($subjects[$owner].JobId)" $subjects[$owner].Headers;if ($items.Items.Count -eq 1 -and $items.Items[0].Status -eq 'ReadyToTransfer') {break};Start-Sleep -Milliseconds 200} while ([DateTime]::UtcNow -lt $deadline)
        if ($items.Items.Count -ne 1 -or $items.Items[0].Status -ne 'ReadyToTransfer') {throw 'Native Original file not prepared'}
        $subjects[$owner].JobItemId=[string]$items.Items[0].Id
        if($DeleteRoot -and $owner -eq 'a'){ProbeItem 'Before file retrieval A direct native Ready item' $true}
        Check "$owner own native Ready Original" "Sync/JobItems/$($items.Items[0].Id)/File" $subjects[$owner].Headers 200 $owner | Out-Null
    }
    Check 'Before deletion B foreign A file' "Sync/JobItems/$($subjects.a.JobItemId)/File" $subjects.b.Headers 404 | Out-Null
    if($DeleteRoot){ProbeItem 'Before deletion A direct native item after file retrieval'}
    $features=(Call 'PersonalChannelsFixture/Surface').SyncSecurity.FeatureChecks
    if (-not @($features | Where-Object {$_.Feature -eq 'sync' -and $_.Allowed}).Count) {throw 'No legitimate positive native sync feature check'}
    if($DeleteRoot){
        $library=@($journal.Libraries|Where-Object Owner -eq 'a')[0]
        $guardPath=Join-Path $root 'data/data/personal-channels-fixture.json.guard.json'
        $guardHash=(Get-FileHash $guardPath -Algorithm SHA256).Hash
        $approval=Call 'PersonalChannelsFixture/ApproveFixtureRootDeletion' $admin Post @{RootKey=[long]$library.LibraryId}
        if(-not $approval.Approved){throw 'Synthetic root not approved'}
        Call 'Library/VirtualFolders/Delete' $admin Post @{Id=$library.LibraryId}|Out-Null
        $rootState=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($library.LibraryId)"
        $videoState=Call "PersonalChannelsFixture/NativeReferenceStatus?Candidate=$($library.VideoId)"
        if($rootState.NativeItemExists -or $videoState.NativeItemExists){throw 'Root/source remained in native catalog'}
        if($guardHash -ne (Get-FileHash $guardPath -Algorithm SHA256).Hash){throw 'Root deletion changed owner configuration'}
        if(@((Call 'Users')|Where-Object Id -eq $subjects.a.UserId).Count -ne 1){throw 'A owner unexpectedly removed'}
    }else{
        Call "Users/$($subjects.a.UserId)" $admin Delete | Out-Null
        if (@((Call 'Users')|Where-Object Id -eq $subjects.a.UserId).Count) {throw 'Deleted owner still exists'}
    }
    ForeignViews 'After deletion'
    $oldBoot=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop | Out-Null
    & $control | Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$ready=Call 'PersonalChannelsFixture/Guard';if ($ready.Enabled -and $ready.Ready -and $ready.BootId -ne $oldBoot) {break}} catch {};Start-Sleep -Milliseconds 200} while ([DateTime]::UtcNow -lt $deadline)
    if (-not $ready.Ready -or $ready.BootId -eq $oldBoot) {throw 'Guard restart not verified'}
    ForeignViews 'After restart'
    $completed=$true
    $name=if($DeleteRoot){'bin/native-root-ready-files-results.json'}else{'bin/native-owner-ready-files-results.json'}
    @{Completed=$true;Version=$info.Version;Server=$info.ServerName;RestartVerified=$true;RootDeletionReadback=$DeleteRoot.IsPresent;OwnerDeletionReadback=(-not $DeleteRoot.IsPresent);OwnerKeptWithUnchangedConfiguration=$DeleteRoot.IsPresent;LegitimateFeatureCheck=$true;FeatureChecks=@($features|Select-Object Feature,Allowed);Observations=$rows.ToArray();Scope='Two real native Original files, deleted owner or whole root, exact job/job-item/file references and B lists; native retention explicitly observed'} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Encoding UTF8
    $rows | ForEach-Object {[pscustomobject]$_} | Format-Table Label,Status,ExistsInNativeManager,PayloadBytes,MatchesSource -AutoSize
} finally {
    if(-not $completed){@{Completed=$false;RootDeletionRequested=$DeleteRoot.IsPresent;Observations=$rows.ToArray()}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-ready-direct-item-incomplete.json') -Encoding UTF8}
    try{& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop}finally{$client.Dispose()}
}
