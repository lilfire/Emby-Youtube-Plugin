param([switch]$RequireProtected,[switch]$ProbeDlna,[switch]$ProbeSync,[switch]$ProbeNewRoot,[switch]$ProbeNativeSocket,[switch]$ProbeDeletedSync,[switch]$ProbeMultiSourceSync,[switch]$ProbeMixedSync,[switch]$ProbeReadParity,[switch]$ProbeSyncTargets,[switch]$ProbeDevicePolicy,[switch]$ProbeTargetVariants,[switch]$ProbeSharedSync,[switch]$ProbeSharedReferences,[switch]$ProbeConcurrentSync,[switch]$ProbeBroadSync,[switch]$ProbeVisibility,[switch]$ProbeConfiguration,[switch]$ProbeRealSyncFiles,[switch]$ProbeStrictUserPolicy)
$ErrorActionPreference='Stop'
if ($ProbeRealSyncFiles -and -not $ProbeSync) {throw 'Real Sync files require -ProbeSync'}
if (($ProbeSharedReferences -or $ProbeConcurrentSync -or $ProbeBroadSync) -and -not $ProbeSharedSync) {throw 'Shared-reference, concurrent and broad Sync probes require -ProbeSharedSync'}
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$results=[Collections.Generic.List[object]]::new()
$createdUsers=[Collections.Generic.List[string]]::new()
$createdLibraries=[Collections.Generic.List[string]]::new()
$createdFiles=[Collections.Generic.List[string]]::new()
$subjects=[Collections.Generic.List[object]]::new()
$started=$false
$fixtureInstalled=$false
$originalDlna=$null
$soapRootControls=@{}
$createdSyncJobs=[Collections.Generic.List[string]]::new()
function NativeSocketProbe($phase,$privateId,$privateOwner) {
    $stamp=[guid]::NewGuid().ToString('N')
    $sockets=@{}
    try {
        foreach ($owner in @('a','b')) {
            $session=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Native libraries test`", Device=`"Isolated test`", DeviceId=`"native-$owner`", Version=`"1.0`""} Post @{Username="native-privacy-fixture-$owner";Pw=''}
            if ($session.User.Id -ne $state[$owner].UserId -or $session.User.Policy.IsAdministrator) {throw 'Native socket subject reauthentication failed'}
            $state[$owner].Headers=@{'X-Emby-Token'=$session.AccessToken}
            $state[$owner].SessionId=$session.SessionInfo.Id
            $socket=[Net.WebSockets.ClientWebSocket]::new()
            $sockets[$owner]=$socket
            $uri=[uri]($base.Replace('http:','ws:')+'/embywebsocket?api_key='+[uri]::EscapeDataString($state[$owner].Headers['X-Emby-Token'])+'&deviceId=native-'+$owner)
            $cts=[Threading.CancellationTokenSource]::new(3000)
            try {$socket.ConnectAsync($uri,$cts.Token).GetAwaiter().GetResult() | Out-Null} finally {$cts.Dispose()}
        }
        Call 'PersonalChannelsFixture/NotifyNative' $admin Post @{UserA=$state.a.UserId;UserB=$state.b.UserId;Stamp=$stamp} | Out-Null
        foreach ($owner in @('a','b')) {
            $cts=[Threading.CancellationTokenSource]::new(4000)
            $message=$null
            try {
                $buffer=New-Object byte[] 65536
                while (-not $cts.IsCancellationRequested -and -not $message) {
                    $stream=[IO.MemoryStream]::new()
                    try {
                        do {
                            $frame=$sockets[$owner].ReceiveAsync([ArraySegment[byte]]::new($buffer),$cts.Token).GetAwaiter().GetResult()
                            if ($frame.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {throw 'Native socket closed before control event'}
                            $stream.Write($buffer,0,$frame.Count)
                        } while (-not $frame.EndOfMessage)
                        $decoded=[Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
                        if ($decoded.MessageType -eq 'LibraryChanged' -and $decoded.Data.FixtureControlStamp -eq $stamp) {$message=$decoded}
                    } finally {$stream.Dispose()}
                }
            } catch {if (-not $cts.IsCancellationRequested) {throw 'Native socket control receive failed'}} finally {$cts.Dispose()}
            if (-not $message) {throw 'Native socket has no matching positive control event'}
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $ids=@($message.Data.ItemsAdded)
            $shouldSee=$privateOwner -eq $owner
            $seen=$ids -contains $privateId
            $foreignIds=@($state[$other].Items | ForEach-Object Id)
            $ownIds=@($state[$owner].Items | ForEach-Object Id)
            $foreign=@($ids | Where-Object {$_ -in $foreignIds})
            $own=@($ids | Where-Object {$_ -in $ownIds})
            $results.Add(@{Label="Socket $phase $owner";MatchedControl=$true;Own=($own.Count -eq 2);Other=($foreign.Count -ne 0 -or ($seen -and -not $shouldSee));PrivateItemVisible=$seen;ExpectedPrivateItemVisible=$shouldSee;PublicControlVisible=($ids -contains '25');Baseline=$false;Data=$message})
            if ($own.Count -ne 2 -or $foreign.Count -ne 0 -or $seen -ne $shouldSee -or $ids -notcontains '25') {throw 'Native socket ownership control failed'}
            foreach ($name in @('ItemsUpdated','FoldersAddedTo')) {
                $refs=@($message.Data.$name)
                $foreignRef=if ($name -eq 'FoldersAddedTo') {$state[$other].LibraryId} else {$foreignIds[0]}
                if ($refs -contains $foreignRef -or (-not $shouldSee -and ($refs -contains $privateId -or $refs -contains $newRoot.RootKey))) {throw 'Native socket secondary references leak'}
            }
        }
    } finally {foreach ($socket in $sockets.Values) {$socket.Abort();$socket.Dispose()}}
}
function NaturalSocketScan($taskId,$mode='Added',$removedId='',$removeFile='') {
    $sockets=@{}
    $stamp=[guid]::NewGuid().ToString('N')
    try {
        foreach ($owner in @('a','b')) {
            $session=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Native libraries test`", Device=`"Isolated test`", DeviceId=`"native-$owner`", Version=`"1.0`""} Post @{Username="native-privacy-fixture-$owner";Pw=''}
            if ($session.User.Id -ne $state[$owner].UserId -or $session.User.Policy.IsAdministrator) {throw 'Natural socket subject validation failed'}
            $state[$owner].Headers=@{'X-Emby-Token'=$session.AccessToken}
            $state[$owner].SessionId=$session.SessionInfo.Id
            $socket=[Net.WebSockets.ClientWebSocket]::new()
            $sockets[$owner]=$socket
            $cts=[Threading.CancellationTokenSource]::new(3000)
            try {
                $uri=[uri]($base.Replace('http:','ws:')+'/embywebsocket?api_key='+[uri]::EscapeDataString($session.AccessToken)+'&deviceId=native-'+$owner)
                $socket.ConnectAsync($uri,$cts.Token).GetAwaiter().GetResult() | Out-Null
            } finally {$cts.Dispose()}
        }
        if ($mode -eq 'Removed') {
            $target=[IO.Path]::GetFullPath($removeFile)
            $allowedFolder=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin/native-c'))+[IO.Path]::DirectorySeparatorChar
            if (-not $target.StartsWith($allowedFolder,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target) -ne 'LibraryScanAddition_c_2.mp4') {throw 'Unsafe natural deletion fixture path'}
            Remove-Item -LiteralPath $target
        }
        Call "ScheduledTasks/Running/$taskId" $admin Post | Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do {Start-Sleep -Milliseconds 200;$task=Call "ScheduledTasks/$taskId"} while ($task.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
        if ($task.State -eq 'Running') {throw 'Natural socket scan did not finish'}
        $rootAfter=Call 'PersonalChannelsFixture/NativeRootProbe'
        if ($mode -eq 'Removed') {
            if ($removedId -in $rootAfter.VideoKeys) {throw 'Natural deletion scan retained the removed video'}
            $added=@($removedId)
        } else {
            $added=@($rootAfter.VideoKeys | Where-Object {$_ -notin $newRoot.VideoKeys})
        }
        if ($added.Count -ne 1) {throw 'Natural scan lacks exactly one new video'}
        # Keep both sockets open through Emby's debounced library notification window.
        Start-Sleep -Seconds 45
        Call 'PersonalChannelsFixture/NotifyNative' $admin Post @{UserA=$state.a.UserId;UserB=$state.b.UserId;Stamp=$stamp} | Out-Null
        foreach ($owner in @('a','b')) {
            $cts=[Threading.CancellationTokenSource]::new(4000)
            $natural=[Collections.Generic.List[object]]::new()
            $controlReceived=$false
            try {
                $buffer=New-Object byte[] 65536
                while (-not $cts.IsCancellationRequested -and -not $controlReceived) {
                    $stream=[IO.MemoryStream]::new()
                    try {
                        do {
                            $frame=$sockets[$owner].ReceiveAsync([ArraySegment[byte]]::new($buffer),$cts.Token).GetAwaiter().GetResult()
                            if ($frame.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {throw 'Natural socket closed'}
                            $stream.Write($buffer,0,$frame.Count)
                        } while (-not $frame.EndOfMessage)
                        $message=[Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
                        if ($message.MessageType -eq 'LibraryChanged') {
                            if ($message.Data.FixtureControlStamp -eq $stamp) {$controlReceived=$true}
                            elseif (-not $message.Data.FixtureControlStamp) {$natural.Add($message.Data)}
                        }
                    } finally {$stream.Dispose()}
                }
            } catch {if (-not $cts.IsCancellationRequested) {throw 'Natural socket receive failed'}} finally {$cts.Dispose()}
            $json=ConvertTo-Json -InputObject @($natural.ToArray()) -Depth 20 -Compress
            $eventField=if ($mode -eq 'Removed') {'ItemsRemoved'} else {'ItemsAdded'}
            $seen=@($natural.ToArray() | ForEach-Object {$_.$eventField}) -contains $added[0]
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $foreign=@($state[$other].Items | ForEach-Object Id)+@($state[$other].LibraryId)
            if ($owner -eq 'a') {$foreign+=@($rootAfter.VideoKeys)+@($rootAfter.RootKey)+@($added)}
            $leaking=@($foreign | Where-Object {$json -match ('"'+[regex]::Escape($_)+'"')}).Count -ne 0
            $results.Add(@{Label="Natural scan $mode socket $owner";ChangeKind=$mode;NaturalEvents=$natural.Count;MatchedControl=$controlReceived;NewVideoVisible=$seen;ExpectedNewVideoVisible=($owner -eq 'b');Other=$leaking;Baseline=$false;Data=$natural.ToArray()})
            Write-Host "Natural scan $mode socket $owner : events=$($natural.Count); new video=$seen; foreign=$leaking; control=$controlReceived"
            if (-not $controlReceived -or $leaking -or ($owner -eq 'b' -and -not $seen) -or ($owner -eq 'a' -and $natural.Count -ne 0)) {throw 'Natural scan socket privacy/positive control failed'}
        }
    } finally {foreach ($socket in $sockets.Values) {$socket.Abort();$socket.Dispose()}}
}
function MixedSyncCreation {
    if (-not $RequireProtected -or -not $ProbeSync) {throw 'Mixed Sync test requires protected Sync setup'}
    function Snapshot($owner) {Call "PersonalChannelsFixture/NativeJobsSnapshot?UserKey=$($state[$owner].UserId)"}
    function StablePair {
        $previous=@{a=(Snapshot 'a');b=(Snapshot 'b')}
        $stable=0
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 200
            $current=@{a=(Snapshot 'a');b=(Snapshot 'b')}
            if ($current.a.StateDigest -eq $previous.a.StateDigest -and $current.b.StateDigest -eq $previous.b.StateDigest) {$stable++} else {$stable=0}
            $previous=$current
            if ($stable -ge 3) {return $current}
        } while ([DateTime]::UtcNow -lt $deadline)
        throw 'Native Sync state did not settle before mutation test'
    }
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $before=Snapshot $owner
        $foreignBefore=Snapshot $other
        $created=Probe "Mixed Sync $owner own create control" 'Sync/Jobs' $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @{TargetId="native-$owner";UserId=$state[$owner].UserId;ItemIds=@([string]$state[$owner].Items[0].Id);Quality='Original';Profile='Original'}
        $jobId=if ($created.Data.Job.Id) {[string]$created.Data.Job.Id} else {[string]$created.Data.Id}
        if ($jobId) {$createdSyncJobs.Add($jobId)}
        $after=Snapshot $owner
        $foreignAfter=Snapshot $other
        $results.Add(@{Label="Mixed Sync $owner snapshot positive control";Status=$created.Status;HasJobKey=[bool]$jobId;OwnJobsBefore=$before.JobCount;OwnJobsAfter=$after.JobCount;OwnStateChanged=($after.StateDigest -ne $before.StateDigest);OtherJobsBefore=$foreignBefore.JobCount;OtherJobsAfter=$foreignAfter.JobCount;OtherStateChanged=($foreignBefore.StateDigest -ne $foreignAfter.StateDigest);Baseline=$false})
        if ($created.Status -ne 200 -or -not $jobId -or $after.JobCount -ne $before.JobCount+1 -or $after.StateDigest -eq $before.StateDigest) {throw 'Mixed Sync native snapshot positive control failed'}
        Call "Sync/Jobs/$jobId" $state[$owner].Headers Delete | Out-Null
        if ((Snapshot $owner).JobCount -ne $before.JobCount) {throw 'Mixed Sync positive control cleanup failed'}
        foreach ($order in @('own-first','foreign-first')) {
            $sources=if ($order -eq 'own-first') {@([string]$state[$owner].Items[0].Id,[string]$state[$other].Items[0].Id)} else {@([string]$state[$other].Items[0].Id,[string]$state[$owner].Items[0].Id)}
            $settled=StablePair;$beforeOwn=$settled[$owner];$beforeOther=$settled[$other]
            $response=Probe "Mixed Sync $owner $order denied" 'Sync/Jobs' $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @{TargetId="native-$owner";UserId=$state[$owner].UserId;ItemIds=$sources;Quality='Original';Profile='Original'}
            $afterOwn=Snapshot $owner;$afterOther=Snapshot $other
            $unchanged=$beforeOwn.StateDigest -eq $afterOwn.StateDigest -and $beforeOther.StateDigest -eq $afterOther.StateDigest
            $results.Add(@{Label="Mixed Sync $owner $order native state";Status=$response.Status;Unchanged=$unchanged;OwnJobCountBefore=$beforeOwn.JobCount;OwnJobCountAfter=$afterOwn.JobCount;OtherJobCountBefore=$beforeOther.JobCount;OtherJobCountAfter=$afterOther.JobCount;Baseline=$false;Other=(-not $unchanged)})
            if ($response.Status -ne 404 -or -not $unchanged) {throw 'Mixed Sync creates or changes native jobs before denial'}
            $missingSources=if ($order -eq 'own-first') {@([string]$state[$owner].Items[0].Id,'999999999')} else {@('999999999',[string]$state[$owner].Items[0].Id)}
            $settled=StablePair;$missingBeforeOwn=$settled[$owner];$missingBeforeOther=$settled[$other]
            $missing=Probe "Mixed Sync $owner $order missing comparison" 'Sync/Jobs' $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @{TargetId="native-$owner";UserId=$state[$owner].UserId;ItemIds=$missingSources;Quality='Original';Profile='Original'}
            $newJobId=if ($missing.Data.Job.Id) {[string]$missing.Data.Job.Id} else {[string]$missing.Data.Id}
            if ($newJobId) {$createdSyncJobs.Add($newJobId)}
            $missingAfterOwn=Snapshot $owner;$missingAfterOther=Snapshot $other
            foreach ($key in @($missingAfterOwn.JobKeys | Where-Object {$_ -notin $missingBeforeOwn.JobKeys})+@($missingAfterOther.JobKeys | Where-Object {$_ -notin $missingBeforeOther.JobKeys})) {
                if ($key -and $key -notin $createdSyncJobs) {$createdSyncJobs.Add([string]$key)}
            }
            $missingUnchanged=$missingBeforeOwn.StateDigest -eq $missingAfterOwn.StateDigest -and $missingBeforeOther.StateDigest -eq $missingAfterOther.StateDigest
            $sameResponse=$missing.Status -eq $response.Status -and (ConvertTo-Json -InputObject $missing.Data -Depth 20 -Compress) -eq (ConvertTo-Json -InputObject $response.Data -Depth 20 -Compress)
            $results.Add(@{Label="Mixed Sync $owner $order hidden/missing comparison";HiddenStatus=$response.Status;MissingStatus=$missing.Status;SameResponse=$sameResponse;NativeStateUnchanged=$missingUnchanged;Baseline=$false})
            if (-not $sameResponse -or -not $missingUnchanged) {throw 'Mixed Sync distinguishes hidden and unknown source or changes native jobs'}
        }
    }
}
function SyncTargetIsolation {
    if (-not $RequireProtected -or -not $ProbeSync) {throw 'Sync target isolation requires protected Sync setup'}
    if ($ProbeDevicePolicy) {
        foreach ($owner in @('a','b')) {
            $policy=(Call "Users/$($state[$owner].UserId)").Policy
            $policy.EnableAllDevices=$false
            $policy.EnabledDevices=@("native-$owner")
            Call "Users/$($state[$owner].UserId)/Policy" $admin Post $policy | Out-Null
            $readback=(Call "Users/$($state[$owner].UserId)").Policy
            if ($readback.EnableAllDevices -or $readback.EnabledDevices.Count -ne 1 -or $readback.EnabledDevices[0] -ne "native-$owner") {throw 'Device policy readback failed'}
            $results.Add(@{Label="Sync targets $owner device policy";EnableAllDevices=$readback.EnableAllDevices;OwnDeviceOnly=$true;Baseline=$false})
        }
    }
    function TargetSnapshot($owner) {Call "PersonalChannelsFixture/NativeJobsSnapshot?UserKey=$($state[$owner].UserId)"}
    function TargetStablePair {
        $previous=@{a=(TargetSnapshot 'a');b=(TargetSnapshot 'b')};$stable=0
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 200
            $current=@{a=(TargetSnapshot 'a');b=(TargetSnapshot 'b')}
            if ($current.a.StateDigest -eq $previous.a.StateDigest -and $current.b.StateDigest -eq $previous.b.StateDigest) {$stable++} else {$stable=0}
            $previous=$current
            if ($stable -ge 3) {return $current}
        } while ([DateTime]::UtcNow -lt $deadline)
        throw 'Target native state did not settle'
    }
    $failures=0
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $session=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Native libraries test`", Device=`"Isolated test`", DeviceId=`"native-$owner`", Version=`"1.0`""} Post @{Username="native-privacy-fixture-$owner";Pw=''}
        if ($session.User.Id -ne $state[$owner].UserId -or $session.User.Policy.IsAdministrator) {throw 'Target test subject validation failed'}
        $state[$owner].Headers=@{'X-Emby-Token'=$session.AccessToken}
        $state[$owner].SessionId=$session.SessionInfo.Id
        Call 'Sessions/Capabilities/Full' $state[$owner].Headers Post @{Id=$session.SessionInfo.Id;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@()} | Out-Null
    }
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $targets=Call "Sync/Targets?UserId=$($state[$owner].UserId)" $state[$owner].Headers
        $targetIds=@($targets | ForEach-Object {[string]$_.Id})
        $results.Add(@{Label="Sync targets $owner enumeration";OwnTargetVisible=("native-$owner" -in $targetIds);ForeignTargetVisible=("native-$other" -in $targetIds);Baseline=$false})
        if ("native-$owner" -notin $targetIds) {throw 'Own Sync target not visible'}
        if ($ProbeDevicePolicy -and "native-$other" -in $targetIds) {$failures++}
        $options=Probe "Sync targets $owner options target list" "Sync/Options?UserId=$($state[$owner].UserId)&ItemIds=$($state[$owner].Items[0].Id)" $state[$owner].Headers "native-$owner" "native-$other"
        if ($options.Status -ne 200 -or -not $options.Own -or $options.Other) {$failures++}
        $xmlStatus=200;$xmlContentType='';$xmlIds=@()
        try {
            $xmlResponse=Invoke-WebRequest -Uri "$base/Sync/Options?UserId=$($state[$owner].UserId)&ItemIds=$($state[$owner].Items[0].Id)&format=xml" -Headers $state[$owner].Headers -UseBasicParsing -TimeoutSec 20
            $xmlContentType=[string]$xmlResponse.Headers['Content-Type']
            if ($xmlContentType.Contains('xml')) {
                $document=[xml]$xmlResponse.Content
                $xmlIds=@($document.SelectNodes("//*[local-name()='Targets']/*/*[local-name()='Id']") | ForEach-Object {$_.InnerText})
            }
        } catch {if (-not $_.Exception.Response) {throw 'XML options failed without HTTP response'};$xmlStatus=[int]$_.Exception.Response.StatusCode}
        $xmlOwn="native-$owner" -in $xmlIds;$xmlForeign="native-$other" -in $xmlIds
        $nativeXmlWorks=$state[$owner].SyncOptionsXmlStatus -eq 200
        $results.Add(@{Label="Sync targets $owner options XML target list";Status=$xmlStatus;NativeStatus=$state[$owner].SyncOptionsXmlStatus;Supported=$nativeXmlWorks;Own=$xmlOwn;Other=$xmlForeign;TargetCount=$xmlIds.Count;Baseline=$false})
        if ($nativeXmlWorks) {
            if ($xmlStatus -ne 200 -or -not $xmlContentType.Contains('xml') -or -not $xmlOwn -or $xmlForeign) {$failures++}
        } elseif ($xmlStatus -ne $state[$owner].SyncOptionsXmlStatus -or $xmlForeign) {$failures++}
        foreach ($role in @('own','foreign','missing')) {
            $targetId=if ($role -eq 'own') {"native-$owner"} elseif ($role -eq 'foreign') {"native-$other"} else {'native-nonexistent-target'}
            foreach ($entry in @(
                @{Name='ready';Path="Sync/Items/Ready?TargetId=$targetId";Method='Get';Body=$null},
                @{Name='options';Path="Sync/Options?TargetId=$targetId&UserId=$($state[$owner].UserId)&ItemIds=$($state[$owner].Items[0].Id)";Method='Get';Body=$null},
                @{Name='data';Path='Sync/Data';Method='Post';Body=@{TargetId=$targetId;LocalItemIds=@()}}
            )) {
                $endpoint=Probe "Sync targets $owner $role $($entry.Name)" $entry.Path $state[$owner].Headers "native-$owner" "native-$other" $false $entry.Method $entry.Body
                if ($endpoint.Other -or ($role -eq 'own' -and $endpoint.Status -ne 200) -or ($role -ne 'own' -and $endpoint.Status -ne 404)) {$failures++}
            }
            $settled=TargetStablePair;$before=$settled[$owner];$otherBefore=$settled[$other]
            $response=Probe "Sync targets $owner $role create" 'Sync/Jobs' $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @{TargetId=$targetId;UserId=$state[$owner].UserId;ItemIds=@([string]$state[$owner].Items[0].Id);Quality='Original';Profile='Original'}
            $after=TargetSnapshot $owner;$otherAfter=TargetSnapshot $other
            $newKeys=@($after.JobKeys | Where-Object {$_ -notin $before.JobKeys})+@($otherAfter.JobKeys | Where-Object {$_ -notin $otherBefore.JobKeys})
            foreach ($key in $newKeys) {if ($key -and $key -notin $createdSyncJobs) {$createdSyncJobs.Add([string]$key)}}
            $jobId=if ($response.Data.Job.Id) {[string]$response.Data.Job.Id} else {[string]$response.Data.Id}
            if ($jobId -and $jobId -notin $createdSyncJobs) {$createdSyncJobs.Add($jobId)}
            $created=$after.JobCount -ne $before.JobCount -or $otherAfter.JobCount -ne $otherBefore.JobCount
            $unchanged=$after.StateDigest -eq $before.StateDigest -and $otherAfter.StateDigest -eq $otherBefore.StateDigest
            $results.Add(@{Label="Sync targets $owner $role native state";Status=$response.Status;CreatedNativeJob=$created;NativeStateUnchanged=$unchanged;OwnJobsBefore=$before.JobCount;OwnJobsAfter=$after.JobCount;OtherJobsBefore=$otherBefore.JobCount;OtherJobsAfter=$otherAfter.JobCount;HasReturnedJob=[bool]$jobId;Baseline=$false})
            if ($role -eq 'own') {
                if ($response.Status -ne 200 -or -not $jobId -or $after.JobCount -ne $before.JobCount+1) {throw 'Own target job creation positive control failed'}
                $state[$owner].NativeInternalTargetId=[long]$response.Data.Job.InternalTargetId
            } elseif ($created -or -not $unchanged -or $response.Status -ne 404) {$failures++}
            foreach ($key in $newKeys) {
                $jobOwner=if ($key -in $after.JobKeys) {$owner} else {$other}
                Call "Sync/Jobs/$key" $state[$jobOwner].Headers Delete | Out-Null
            }
            if ((TargetSnapshot $owner).JobCount -ne $before.JobCount -or (TargetSnapshot $other).JobCount -ne $otherBefore.JobCount) {throw 'Target test job cleanup failed'}
        }
    }
    if ($ProbeTargetVariants) {
        foreach ($owner in @('a','b')) {
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $ownInternal=[long]$state[$owner].NativeInternalTargetId
            $foreignInternal=[long]$state[$other].NativeInternalTargetId
            if ($ownInternal -le 0 -or $foreignInternal -le 0 -or $ownInternal -eq $foreignInternal) {throw 'Internal target controls unavailable'}
            $cases=@(
                @{Name='implicit data omitted targets';Path='Sync/Data';Body=@{LocalItemIds=@()};Expected=200},
                @{Name='implicit data empty internals';Path='Sync/Data';Body=@{InternalTargetIds=@();LocalItemIds=@()};Expected=200},
                @{Name='implicit data null internals';Path='Sync/Data';Body=@{InternalTargetIds=$null;LocalItemIds=@()};Expected=200},
                @{Name='implicit data empty external';Path='Sync/Data';Body=@{TargetId='';LocalItemIds=@()};Expected=200},
                @{Name='own internal only';Path='Sync/Data';Body=@{InternalTargetIds=@($ownInternal);LocalItemIds=@()};Expected=200},
                @{Name='foreign internal only';Path='Sync/Data';Body=@{InternalTargetIds=@($foreignInternal);LocalItemIds=@()};Expected=404},
                @{Name='mixed internal own first';Path='Sync/Data';Body=@{InternalTargetIds=@($ownInternal,$foreignInternal);LocalItemIds=@()};Expected=404},
                @{Name='mixed internal foreign first';Path='Sync/Data';Body=@{InternalTargetIds=@($foreignInternal,$ownInternal);LocalItemIds=@()};Expected=404},
                @{Name='own external foreign internal';Path='Sync/Data';Body=@{TargetId="native-$owner";InternalTargetIds=@($foreignInternal);LocalItemIds=@()};Expected=404},
                @{Name='own external missing internal';Path='Sync/Data';Body=@{TargetId="native-$owner";InternalTargetIds=@([long]999999999);LocalItemIds=@()};Expected=404}
            )
            foreach ($kind in @('omitted','empty','null','whitespace')) {
                $body=@{UserId=$state[$owner].UserId;ItemIds=@([string]$state[$owner].Items[0].Id);Quality='Original';Profile='Original'}
                if ($kind -eq 'empty') {$body.TargetId=''} elseif ($kind -eq 'null') {$body.TargetId=$null} elseif ($kind -eq 'whitespace') {$body.TargetId=' '}
                $cases+=@{Name="$kind creation target";Path='Sync/Jobs';Body=$body;Expected=404}
            }
            foreach ($case in $cases) {
                $settled=TargetStablePair;$before=$settled[$owner];$otherBefore=$settled[$other]
                $traceBefore=Call 'PersonalChannelsFixture/NativeSyncInputTrace'
                $response=Probe "Sync target variant $owner $($case.Name)" $case.Path $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post $case.Body
                $traceAfter=Call 'PersonalChannelsFixture/NativeSyncInputTrace'
                if ($case.Path -eq 'Sync/Data') {
                    $invoked=$traceAfter.Sequence -eq $traceBefore.Sequence+1
                    $skipped=$traceAfter.Sequence -eq $traceBefore.Sequence
                    $scoped=$traceAfter.HasExplicitTargets -and $traceAfter.InternalTargetIds.Count -eq 1 -and [long]$traceAfter.InternalTargetIds[0] -eq $ownInternal
                    $results.Add(@{Label="Sync target variant $owner $($case.Name) native input";NativeInvoked=$invoked;NativeSkipped=$skipped;ScopedToOwnTarget=($invoked -and $scoped);Baseline=$false})
                    if (($case.Expected -eq 200 -and (-not $invoked -or -not $scoped)) -or ($case.Expected -ne 200 -and -not $skipped)) {$failures++}
                }
                $after=TargetSnapshot $owner;$otherAfter=TargetSnapshot $other
                $newKeys=@($after.JobKeys | Where-Object {$_ -notin $before.JobKeys})+@($otherAfter.JobKeys | Where-Object {$_ -notin $otherBefore.JobKeys})
                foreach ($key in $newKeys) {if ($key -and $key -notin $createdSyncJobs) {$createdSyncJobs.Add([string]$key)}}
                $unchanged=$before.StateDigest -eq $after.StateDigest -and $otherBefore.StateDigest -eq $otherAfter.StateDigest
                $results.Add(@{Label="Sync target variant $owner $($case.Name) native state";Status=$response.Status;ExpectedStatus=$case.Expected;NativeStateUnchanged=$unchanged;CreatedJobs=$newKeys.Count;Baseline=$false})
                if ($response.Status -ne $case.Expected -or -not $unchanged -or $response.Other) {$failures++}
                foreach ($key in $newKeys) {
                    $jobOwner=if ($key -in $after.JobKeys) {$owner} else {$other}
                    Call "Sync/Jobs/$key" $state[$jobOwner].Headers Delete | Out-Null
                }
                if ((TargetSnapshot $owner).JobCount -ne $before.JobCount -or (TargetSnapshot $other).JobCount -ne $otherBefore.JobCount) {throw 'Variant cleanup failed'}
            }
        }
    }
    if ($failures) {throw "Sync target isolation failed for $failures controls"}
}
function ConfigurationBoundary {
    Add-Type -AssemblyName System.Net.Http
    $configPath='Plugins/B2C3D4E5-F6A7-4B5C-9D0E-1F2A3B4C5D6E/Configuration'
    $before=Call $configPath
    $beforeValues=@([string]$before.ApiKey,[string]$before.SavedItems,[string]$before.WatchLaterPlaylist)
    $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(20)
    try {
        foreach ($subject in @('admin','a','b','anonymous')) {
            $headers=@(); if ($subject -eq 'admin') {$headers=$admin} elseif ($subject -ne 'anonymous') {$headers=$state[$subject].Headers}
            foreach ($method in @('GET','POST')) {
                $path=if ($method -eq 'GET') {$configPath} else {'YouTubePlugin/SaveConfiguration'}
                $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($method),"$base/$path")
                if ($headers -is [Collections.IDictionary]) {foreach ($key in $headers.Keys) {$message.Headers.TryAddWithoutValidation($key,[string]$headers[$key]) | Out-Null}}
                # Invalid JSON stops deserialization before any configuration mutation.
                if ($method -eq 'POST') {$message.Content=[Net.Http.StringContent]::new('{',[Text.Encoding]::UTF8,'application/json')}
                try {
                    $http=$client.SendAsync($message).GetAwaiter().GetResult()
                    try {
                        $status=[int]$http.StatusCode
                        $hasKeyField=$false;$hasChannelField=$false
                        if ($method -eq 'GET' -and $status -eq 200) {
                            $parsed=$http.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                            $hasKeyField=$null -ne $parsed.PSObject.Properties['ApiKey']
                            $hasChannelField=$null -ne $parsed.PSObject.Properties['SavedItems']
                            $parsed=$null
                        }
                        $results.Add(@{Label="Configuration $subject $method boundary";Status=$status;HasApiKeyField=$hasKeyField;HasChannelField=$hasChannelField;MalformedSaveBody=($method -eq 'POST');Baseline=$false})
                        if ($subject -eq 'admin') {
                            if (($method -eq 'GET' -and ($status -ne 200 -or -not $hasKeyField -or -not $hasChannelField)) -or ($method -eq 'POST' -and $status -notin @(400,500))) {throw 'Admin configuration route positive control missing'}
                        } elseif ($status -notin @(401,403) -or $hasKeyField -or $hasChannelField) {throw 'Ordinary or anonymous configuration boundary failed'}
                    } finally {$http.Dispose()}
                } finally {$message.Dispose()}
            }
        }
        $after=Call $configPath
        $afterValues=@([string]$after.ApiKey,[string]$after.SavedItems,[string]$after.WatchLaterPlaylist)
        $unchanged=($beforeValues | ConvertTo-Json -Compress) -ceq ($afterValues | ConvertTo-Json -Compress)
        $results.Add(@{Label='Configuration secret and channel readback';Unchanged=$unchanged;Baseline=$false})
        if (-not $unchanged) {throw 'Configuration boundary test changed protected settings'}
    } finally {$client.Dispose();$before=$null;$after=$null;$beforeValues=$null;$afterValues=$null}
}
function NativeVisibilityObservation {
    $guard=Call 'PersonalChannelsFixture/Guard'
    if ($guard.Enabled) {throw 'Visibility observation needs native baseline without privacy enforcement'}
    foreach ($actor in @('a','b')) {
        $other=if ($actor -eq 'a') {'b'} else {'a'}
        $foreign=[string]$state[$other].Items[0].Id
        $control=Call "PersonalChannelsFixture/NativeVisibilityTrace?Reset=true&ItemKey=$foreign&UserKey=$($state[$actor].UserId)"
        $observed=@($control.Trace.Calls | Where-Object ItemKey -EQ $foreign)
        $results.Add(@{Label="Visibility baseline $actor explicit control";Visible=$control.Visible;Standalone=$control.Standalone;ObservedCalls=$observed.Count;Baseline=$true})
        if ($observed.Count -lt 2) {throw 'Visibility observer has no positive native invocation control'}
        foreach ($case in @(
            @{Name='direct metadata';Path="Users/$($state[$actor].UserId)/Items/$foreign";Binary=$false},
            @{Name='playback info';Path="Items/$foreign/PlaybackInfo?UserId=$($state[$actor].UserId)";Binary=$false},
            @{Name='static stream';Path="Videos/$foreign/stream.mp4?Static=true";Binary=$true},
            @{Name='download';Path="Items/$foreign/Download";Binary=$true}
        )) {
            Call 'PersonalChannelsFixture/NativeVisibilityTrace?Reset=true' | Out-Null
            $response=Probe "Visibility baseline $actor $($case.Name) response" $case.Path $state[$actor].Headers "PrivateNativeVideo_$other" 'not-a-marker' $case.Binary
            $response.Baseline=$true
            $trace=Call 'PersonalChannelsFixture/NativeVisibilityTrace'
            $calls=@($trace.Calls | Where-Object ItemKey -EQ $foreign)
            $results.Add(@{Label="Visibility baseline $actor $($case.Name) trace";Status=$response.Status;Bytes=$response.Bytes;PrivateMetadata=$response.Own;VisibilityCalls=$calls.Count;Calls=$calls;Baseline=$true})
            if ($response.Status -ne 200 -or ($case.Binary -and $response.Bytes -lt 1000) -or (-not $case.Binary -and -not $response.Own)) {throw 'Native visibility route lacks successful cross-owner baseline control'}
        }
    }
}
function SharedSyncIsolation {
    if (-not $RequireProtected -or -not $ProbeSync) {throw 'Shared Sync requires protected native Sync setup'}
    $sharedDevice='native-shared-test'
    $aliases=@{}; foreach ($owner in @('a','b')) {$aliases[$owner]=Call "PersonalChannelsFixture/NativeVideoAliases?ItemKey=$($state[$owner].Items[0].Id)"}
    function SharedSnapshot($owner) {Call "PersonalChannelsFixture/NativeJobsSnapshot?UserKey=$($state[$owner].UserId)"}
    function SharedStablePair {
        $previous=@{a=(SharedSnapshot 'a');b=(SharedSnapshot 'b')};$stable=0
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 200;$current=@{a=(SharedSnapshot 'a');b=(SharedSnapshot 'b')}
            if ($current.a.StateDigest -eq $previous.a.StateDigest -and $current.b.StateDigest -eq $previous.b.StateDigest) {$stable++} else {$stable=0}
            $previous=$current;if ($stable -ge 3) {return $current}
        } while ([DateTime]::UtcNow -lt $deadline)
        throw 'Shared native state did not settle'
    }
    foreach ($owner in @('a','b')) {
        $policy=(Call "Users/$($state[$owner].UserId)").Policy
        $policy.EnableAllDevices=[bool]$ProbeBroadSync;$policy.EnabledDevices=@("native-$owner",$sharedDevice)
        Call "Users/$($state[$owner].UserId)/Policy" $admin Post $policy | Out-Null
        $readback=(Call "Users/$($state[$owner].UserId)").Policy
        if ($readback.EnableAllDevices -ne [bool]$ProbeBroadSync -or $sharedDevice -notin $readback.EnabledDevices) {throw 'Shared device policy readback failed'}
        $results.Add(@{Label="Shared Sync $owner device policy";EnableAllDevices=$readback.EnableAllDevices;ExpectedBroad=[bool]$ProbeBroadSync;Baseline=$false})
        $session=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Shared Sync test`", Device=`"Shared isolated test`", DeviceId=`"$sharedDevice`", Version=`"1.0`""} Post @{Username="native-privacy-fixture-$owner";Pw=''}
        if ($session.User.Id -ne $state[$owner].UserId -or $session.User.Policy.IsAdministrator) {throw 'Shared session subject mismatch'}
        $state[$owner].Headers=@{'X-Emby-Token'=$session.AccessToken}
        Call 'Sessions/Capabilities/Full' $state[$owner].Headers Post @{Id=$session.SessionInfo.Id;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@()} | Out-Null
    }
    $failures=0
    foreach ($actor in @('a','b')) {
        $other=if ($actor -eq 'a') {'b'} else {'a'}
        $cacheParity=@{}
        $modes=@('keep own','remove own')
        if ($ProbeConcurrentSync) {$modes+=@('concurrent keep own','concurrent remove own')}
        if ($ProbeBroadSync) {$modes+=@('broad implicit keep own','broad implicit remove own')}
        if ($ProbeSharedReferences) {$modes+=@('own GUID N','own GUID D','foreign numeric','foreign GUID N','foreign GUID D','mixed own first','mixed foreign first','missing numeric','missing GUID')}
        foreach ($mode in $modes) {
            $jobs=@{};$itemKeys=@{}
            foreach ($owner in @('a','b')) {
                $targets=Call "Sync/Targets?UserId=$($state[$owner].UserId)" $state[$owner].Headers
                if ($sharedDevice -notin @($targets | ForEach-Object Id)) {throw 'Shared target not available to both users'}
                $jobTarget=$sharedDevice; if ($mode.StartsWith('broad implicit ')) {$jobTarget="native-$owner"}
                $created=Probe "Shared Sync $actor $mode $owner create" 'Sync/Jobs' $state[$owner].Headers "PrivateNativeVideo_$owner" 'not-a-marker' $false Post @{TargetId=$jobTarget;UserId=$state[$owner].UserId;ItemIds=@([string]$state[$owner].Items[0].Id);Quality='Original';Profile='Original'}
                $jobId=[string]$created.Data.Job.Id
                if (-not $jobId -or $created.Status -ne 200) {throw 'Shared job creation control failed'}
                $jobs[$owner]=$jobId;$createdSyncJobs.Add($jobId)
                $items=Call "Sync/JobItems?JobId=$jobId" $state[$owner].Headers
                if ($items.Items.Count -ne 1) {throw 'Shared job lacks one real native item'}
                $itemKeys[$owner]=[string]$items.Items[0].Id
                if ($ProbeRealSyncFiles) {
                    $deadline=[DateTime]::UtcNow.AddSeconds(30)
                    while ($items.Items[0].Status -ne 'ReadyToTransfer' -and [DateTime]::UtcNow -lt $deadline) {
                        Start-Sleep -Milliseconds 200
                        $items=Call "Sync/JobItems?JobId=$jobId" $state[$owner].Headers
                    }
                    $results.Add(@{Label="Real Sync shared $actor $mode $owner native preparation";NativeStatus=$items.Items[0].Status;Baseline=$false})
                    if ($items.Items[0].Status -ne 'ReadyToTransfer') {throw 'Shared native Sync did not prepare a real file'}
                    VerifyRealSyncFile $owner 'protected' $itemKeys[$owner] " shared $actor $mode"
                    $ready=Probe "Real Sync shared $actor $mode $owner ready metadata" "Sync/Items/Ready?TargetId=$jobTarget" $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$(if ($owner -eq 'a') {'b'} else {'a'})"
                    if ($ready.Status -ne 200 -or -not $ready.Own -or $ready.Other) {throw 'Shared ready metadata lacks an isolated own-file positive control'}
                }
                # Use the ordinary client-reporting API; this is metadata state only.
                # No conversion, output file or license/feature setting is manufactured.
                $transferred=Probe "Shared Sync $actor $mode $owner report transferred" "Sync/JobItems/$($itemKeys[$owner])/Transferred" $state[$owner].Headers 'not-a-marker' 'not-a-marker' $false Post
                $read=Call "Sync/JobItems?JobId=$jobId" $state[$owner].Headers
                $synced=$read.Items.Count -eq 1 -and [string]$read.Items[0].Status -in @('Synced','4')
                $results.Add(@{Label="Shared Sync $actor $mode $owner native synced metadata";Status=$transferred.Status;NativeSynced=$synced;ConvertedFileVerified=$false;Baseline=$false})
                if ($transferred.Status -ne 200 -or -not $synced) {throw 'Shared metadata state control unavailable; no completed-file claim'}
            }
            $settled=SharedStablePair;$before=$settled[$actor];$otherBefore=$settled[$other]
            $local=@()
            switch ($mode) {
                'keep own' {$local=@([string]$aliases[$actor].Numeric)}
                'broad implicit keep own' {$local=@([string]$aliases[$actor].GuidN,[string]$aliases[$other].GuidD)}
                'concurrent keep own' {$local=@([string]$aliases[$actor].GuidN,[string]$aliases[$other].GuidD)}
                'own GUID N' {$local=@([string]$aliases[$actor].GuidN)}
                'own GUID D' {$local=@([string]$aliases[$actor].GuidD)}
                'foreign numeric' {$local=@([string]$aliases[$other].Numeric)}
                'foreign GUID N' {$local=@([string]$aliases[$other].GuidN)}
                'foreign GUID D' {$local=@([string]$aliases[$other].GuidD)}
                'mixed own first' {$local=@([string]$aliases[$actor].Numeric,[string]$aliases[$other].Numeric)}
                'mixed foreign first' {$local=@([string]$aliases[$other].Numeric,[string]$aliases[$actor].Numeric)}
                'missing numeric' {$local=@('999999999')}
                'missing GUID' {$local=@('fffffffffffffffffffffffffffffffe')}
            }
            if ($mode.StartsWith('concurrent ')) {
                Add-Type -AssemblyName System.Net.Http
                $traceBefore=Call 'PersonalChannelsFixture/NativeSyncInputTrace'
                $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(20)
                $pending=[Collections.Generic.List[object]]::new()
                $badStatus=0;$badBody=0;$response=$null
                try {
                    for ($round=0;$round -lt 12;$round++) {
                        foreach ($subject in @($actor,$other)) {
                            $ids=@(); if ($subject -eq $actor) {$ids=$local} else {$ids=@([string]$aliases[$other].GuidD,[string]$aliases[$actor].GuidN)}
                            $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/Sync/Data")
                            foreach ($key in $state[$subject].Headers.Keys) {$message.Headers.TryAddWithoutValidation($key,[string]$state[$subject].Headers[$key]) | Out-Null}
                            $json=ConvertTo-Json -InputObject @{TargetId=$sharedDevice;LocalItemIds=@($ids)} -Compress
                            $message.Content=[Net.Http.StringContent]::new($json,[Text.Encoding]::UTF8,'application/json')
                            $pending.Add(@{Subject=$subject;Ids=@($ids);Message=$message;Task=$client.SendAsync($message)})
                        }
                    }
                    foreach ($entry in $pending) {
                        $http=$entry.Task.GetAwaiter().GetResult()
                        try {
                            $code=[int]$http.StatusCode;$text=$http.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                            if ($code -ne 200) {$badStatus++;continue}
                            $data=$text | ConvertFrom-Json
                            $subject=$entry.Subject
                            $mine=@([string]$aliases[$subject].Numeric,[string]$aliases[$subject].GuidN,[string]$aliases[$subject].GuidD)
                            $removed=@($data.ItemIdsToRemove | ForEach-Object {[string]$_})
                            $allowed=@($entry.Ids)+$mine
                            $stale=@($entry.Ids | Where-Object {$_ -notin $mine})
                            if (@($removed | Where-Object {$_ -notin $allowed}).Count -or @($stale | Where-Object {$_ -notin $removed}).Count) {$badBody++}
                            if ($subject -eq $actor -and $null -eq $response) {$response=@{Status=$code;Data=$data}}
                        } finally {$http.Dispose()}
                    }
                } finally {
                    foreach ($entry in $pending) {$entry.Message.Dispose()}
                    $client.Dispose()
                }
                $traceAfter=Call 'PersonalChannelsFixture/NativeSyncInputTrace'
                $overlaps=[long]$traceAfter.CrossSubjectOverlaps-[long]$traceBefore.CrossSubjectOverlaps
                $calls=[long]$traceAfter.Sequence-[long]$traceBefore.Sequence
                $results.Add(@{Label="Shared Sync $actor $mode native overlap";Requests=$pending.Count;NativeCalls=$calls;CrossSubjectOverlaps=$overlaps;ActiveCallsAfter=$traceAfter.ActiveCalls;BadStatuses=$badStatus;BadBodies=$badBody;Baseline=$false})
                if ($badStatus -or $badBody -or $null -eq $response -or $overlaps -lt 1 -or $calls -ne $pending.Count -or $traceAfter.ActiveCalls -ne 0) {throw 'Concurrent Sync lacked proven overlap or valid isolated responses'}
            } else {
                $payload=@{TargetId=$sharedDevice;LocalItemIds=$local}
                if ($mode.StartsWith('broad implicit ')) {$payload.Remove('TargetId')}
                $response=Probe "Shared Sync $actor $mode data" 'Sync/Data' $state[$actor].Headers "PrivateNativeVideo_$actor" "PrivateNativeVideo_$other" $false Post $payload
                if ($mode.StartsWith('broad implicit ')) {
                    $trace=Call 'PersonalChannelsFixture/NativeSyncInputTrace'
                    $unrestricted=@($trace.InternalTargetIds).Count -eq 0
                    $results.Add(@{Label="Shared Sync $actor $mode unrestricted input";NativeTargetIdsEmpty=$unrestricted;HasExplicitTargets=$trace.HasExplicitTargets;JobTargetA="native-a";JobTargetB="native-b";Baseline=$false})
                    if (-not $unrestricted) {throw 'Broad Sync was narrowed before native manager; no broad-policy proof'}
                }
            }
            $after=SharedSnapshot $actor;$otherAfter=SharedSnapshot $other
            $ownChanged=$before.StateDigest -ne $after.StateDigest;$otherChanged=$otherBefore.StateDigest -ne $otherAfter.StateDigest
            $foreignId=[string]$state[$other].Items[0].Id
            $returned=@($response.Data.ItemIdsToRemove | ForEach-Object {[string]$_})
            $foreignReturned=$foreignId -in $returned
            $allowedReturned=@($local)+@([string]$aliases[$actor].Numeric,[string]$aliases[$actor].GuidN,[string]$aliases[$actor].GuidD)
            $newReferences=@($returned | Where-Object {$_ -notin $allowedReturned})
            $ownAliases=@([string]$aliases[$actor].Numeric,[string]$aliases[$actor].GuidN,[string]$aliases[$actor].GuidD)
            $staleInputs=@($local | Where-Object {$_ -notin $ownAliases})
            $missingStale=@($staleInputs | Where-Object {$_ -notin $returned})
            $inputEcho=$foreignReturned -and $foreignId -in $local
            if ($mode -in @('foreign numeric','foreign GUID N','foreign GUID D','missing numeric','missing GUID')) {
                $normalized=ConvertTo-Json -InputObject $response.Data -Depth 30 -Compress
                foreach ($token in $local) {$normalized=$normalized.Replace([string]$token,'[caller-cache-id]')}
                $cacheParity[$mode]=@{Status=$response.Status;Body=$normalized;OwnChanged=$ownChanged;OtherChanged=$otherChanged}
            }
            $results.Add(@{Label="Shared Sync $actor $mode native state";Status=$response.Status;OwnStateChanged=$ownChanged;OtherStateChanged=$otherChanged;ForeignRemovalIdReturned=$foreignReturned;CallerAlreadyProvidedForeignId=$inputEcho;NewRemovalReferences=$newReferences.Count;MissingStaleRemovalTokens=$missingStale.Count;Baseline=$false})
            Write-Host "Shared Sync $actor $mode : own changed=$ownChanged; foreign changed=$otherChanged; foreign ID=$foreignReturned"
            $expectedOwnChange=$mode -in @('remove own','broad implicit remove own','concurrent remove own','foreign numeric','foreign GUID N','foreign GUID D','missing numeric','missing GUID')
            if ($response.Status -ne 200 -or $otherChanged -or $newReferences.Count -ne 0 -or $missingStale.Count -ne 0 -or $ownChanged -ne $expectedOwnChange) {$failures++}
            foreach ($owner in @('a','b')) {
                if ($jobs[$owner] -in (SharedSnapshot $owner).JobKeys) {Call "Sync/Jobs/$($jobs[$owner])" $state[$owner].Headers Delete | Out-Null}
            }
        }
        if ($ProbeSharedReferences) {
            foreach ($pair in @(@('foreign numeric','missing numeric'),@('foreign GUID N','missing GUID'),@('foreign GUID D','missing GUID'))) {
                $hidden=$cacheParity[$pair[0]];$missing=$cacheParity[$pair[1]]
                $same=$hidden.Status -eq $missing.Status -and $hidden.Body -ceq $missing.Body -and $hidden.OwnChanged -eq $missing.OwnChanged -and $hidden.OtherChanged -eq $missing.OtherChanged
                $results.Add(@{Label="Shared Sync $actor $($pair[0]) missing parity";Status=$hidden.Status;SameNormalizedResponseAndState=$same;Baseline=$false})
                if (-not $same) {$failures++}
            }
        }
    }
    if ($failures) {throw "Shared Sync isolation failed for $failures controls"}
}
function ReadParity {
    if (-not $RequireProtected) {throw 'Read parity requires protected native setup'}
    Add-Type -AssemblyName System.Net.Http
    $client=[Net.Http.HttpClient]::new()
    $client.Timeout=[TimeSpan]::FromSeconds(20)
    function ReadResponse($path,$headers,$method='GET') {
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($method),"$base/$path")
        if ($method -eq 'POST') {$message.Content=[Net.Http.StringContent]::new('{}',[Text.Encoding]::UTF8,'application/json')}
        try {
            foreach ($key in $headers.Keys) {$message.Headers.TryAddWithoutValidation($key,[string]$headers[$key]) | Out-Null}
            $response=$client.SendAsync($message).GetAwaiter().GetResult()
            try {
                $stableHeaders=@{}
                foreach ($header in @('Cache-Control','ETag','Last-Modified','Content-Range','Content-Length','Content-Encoding','Transfer-Encoding')) {
                    $values=$null
                    if ($response.Headers.TryGetValues($header,[ref]$values) -or $response.Content.Headers.TryGetValues($header,[ref]$values)) {$stableHeaders[$header]=[string]::Join(',',@($values))}
                }
                return @{Status=[int]$response.StatusCode;Body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult();ContentType=[string]$response.Content.Headers.ContentType;StableHeaders=($stableHeaders | ConvertTo-Json -Compress)}
            }
            finally {$response.Dispose()}
        } finally {$message.Dispose()}
    }
    $failures=0
    try {
        foreach ($owner in @('a','b')) {
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $ownId=$state[$owner].Items[0].Id;$foreignId=$state[$other].Items[0].Id;$uid=$state[$owner].UserId
            $control=ReadResponse "Users/$uid/Items/$ownId" $state[$owner].Headers
            if ($control.Status -ne 200 -or -not $control.Body.Contains("PrivateNativeVideo_$owner")) {throw 'Read parity owner positive control failed'}
            $results.Add(@{Label="Read parity $owner own control";Status=$control.Status;Own=$true;Other=$false;Baseline=$false})
            $playbackControl=ReadResponse "Items/$ownId/PlaybackInfo?UserId=$uid" $state[$owner].Headers 'POST'
            $playbackData=$playbackControl.Body | ConvertFrom-Json
            if ($playbackControl.Status -ne 200 -or @($playbackData.MediaSources).Count -lt 1) {throw 'POST PlaybackInfo owner control failed'}
            $results.Add(@{Label="Read parity $owner own POST PlaybackInfo";Status=$playbackControl.Status;Own=$true;Other=$false;Baseline=$false})
            $headControl=ReadResponse "Items?Ids=$ownId&UserId=$uid" $state[$owner].Headers 'HEAD'
            if ($headControl.Status -notin @(200,404)) {throw 'Unexpected owner list HEAD status'}
            $results.Add(@{Label="Read parity $owner own list HEAD support";Status=$headControl.Status;Supported=($headControl.Status -eq 200);Other=$false;Baseline=$false})
            $xmlControl=ReadResponse "Items?Ids=$ownId&UserId=$uid&format=xml" $state[$owner].Headers
            if ($xmlControl.Status -ne 200 -or -not $xmlControl.ContentType.Contains('xml') -or -not $xmlControl.Body.Contains("PrivateNativeVideo_$owner")) {throw 'XML owner list control failed'}
            $results.Add(@{Label="Read parity $owner own XML control";Status=$xmlControl.Status;Own=$true;Other=$false;Baseline=$false})
            foreach ($case in @(
                @{Name='direct';Path="Users/$uid/Items/{id}";Hidden=$foreignId},
                @{Name='IDs';Path="Items?Ids={id}&UserId=$uid";Hidden=$foreignId},
                @{Name='mixed IDs';Path="Items?Ids=$ownId,{id}&UserId=$uid";Hidden=$foreignId},
                @{Name='parent';Path="Items?ParentId={id}&Recursive=true&UserId=$uid";Hidden=$state[$other].LibraryId},
                @{Name='PlaybackInfo';Path="Items/{id}/PlaybackInfo?UserId=$uid";Hidden=$foreignId},
                @{Name='stream HEAD';Path='Videos/{id}/stream.mp4?Static=true';Hidden=$foreignId;Method='HEAD'},
                @{Name='download HEAD';Path='Items/{id}/Download';Hidden=$foreignId;Method='HEAD'},
                @{Name='direct HEAD';Path="Users/$uid/Items/{id}";Hidden=$foreignId;Method='HEAD'},
                @{Name='stream GET';Path='Videos/{id}/stream.mp4?Static=true';Hidden=$foreignId},
                @{Name='download GET';Path='Items/{id}/Download';Hidden=$foreignId},
                @{Name='mixed IDs page 1';Path="Items?Ids=$ownId,{id}&UserId=$uid&StartIndex=0&Limit=1";Hidden=$foreignId;ExpectedCount=1;ExpectedTotal=1},
                @{Name='mixed IDs page 2';Path="Items?Ids=$ownId,{id}&UserId=$uid&StartIndex=1&Limit=1";Hidden=$foreignId;ExpectedCount=0;ExpectedTotal=1},
                @{Name='user IDs';Path="Users/$uid/Items?Ids={id}";Hidden=$foreignId;ExpectedCount=0;ExpectedTotal=0},
                @{Name='lowercase IDs';Path="Items?ids={id}&UserId=$uid";Hidden=$foreignId;ExpectedCount=0;ExpectedTotal=0},
                @{Name='lowercase PlaybackInfo';Path="items/{id}/playbackinfo?UserId=$uid";Hidden=$foreignId},
                @{Name='PlaybackInfo POST';Path="Items/{id}/PlaybackInfo?UserId=$uid";Hidden=$foreignId;Method='POST'},
                @{Name='IDs HEAD';Path="Items?Ids={id}&UserId=$uid";Hidden=$foreignId;Method='HEAD'},
                @{Name='mixed IDs HEAD';Path="Items?Ids=$ownId,{id}&UserId=$uid";Hidden=$foreignId;Method='HEAD'},
                @{Name='parent HEAD';Path="Items?ParentId={id}&UserId=$uid&Recursive=true";Hidden=$state[$other].LibraryId;Method='HEAD'},
                @{Name='XML mixed page 1';Path="Items?Ids=$ownId,{id}&UserId=$uid&StartIndex=0&Limit=1&format=xml";Hidden=$foreignId;ExpectedCount=1;ExpectedTotal=1;XML=$true},
                @{Name='XML mixed page 2';Path="Items?Ids=$ownId,{id}&UserId=$uid&StartIndex=1&Limit=1&format=xml";Hidden=$foreignId;ExpectedCount=0;ExpectedTotal=1;XML=$true}
            )) {
                $method=if ($case.Method) {$case.Method} else {'GET'}
                $hidden=ReadResponse $case.Path.Replace('{id}',[string]$case.Hidden) $state[$owner].Headers $method
                $missing=ReadResponse $case.Path.Replace('{id}','999999999') $state[$owner].Headers $method
                $hiddenBody=$hidden.Body.Replace([string]$case.Hidden,'[probe-id]')
                $missingBody=$missing.Body.Replace('999999999','[probe-id]')
                $same=$hidden.Status -eq $missing.Status -and $hiddenBody -eq $missingBody -and $hidden.ContentType -eq $missing.ContentType -and $hidden.StableHeaders -eq $missing.StableHeaders
                $leak=$hidden.Body.Contains("PrivateNativeVideo_$other") -or $hidden.Body.Contains("Private Native Fixture $other")
                $results.Add(@{Label="Read parity $owner $($case.Name)";HiddenStatus=$hidden.Status;MissingStatus=$missing.Status;HiddenContentType=$hidden.ContentType;MissingContentType=$missing.ContentType;SameResponse=$same;Other=$leak;Baseline=$false;HiddenBody=$hiddenBody;MissingBody=$missingBody;HiddenStableHeaders=$hidden.StableHeaders;MissingStableHeaders=$missing.StableHeaders})
                if ($case.Name -in @('IDs','parent','mixed IDs') -or $case.ContainsKey('ExpectedCount')) {
                    if ($case.XML) {
                        if (-not $hidden.ContentType.Contains('xml')) {throw 'XML case did not return XML'}
                        $document=[xml]$hidden.Body
                        $items=$document.DocumentElement.SelectSingleNode("*[local-name()='Items']")
                        $totalNode=$document.DocumentElement.SelectSingleNode("*[local-name()='TotalRecordCount']")
                        $data=@{Items=@($items.ChildNodes | ForEach-Object {@{Id=$_.SelectSingleNode("*[local-name()='Id']").InnerText}});TotalRecordCount=[int]$totalNode.InnerText}
                    } else {$data=$hidden.Body | ConvertFrom-Json}
                    $count=if ($case.ContainsKey('ExpectedCount')) {[int]$case.ExpectedCount} elseif ($case.Name -eq 'mixed IDs') {1} else {0}
                    $total=if ($case.ContainsKey('ExpectedTotal')) {[int]$case.ExpectedTotal} else {$count}
                    if ($hidden.Status -ne 200 -or $data.Items.Count -ne $count -or $data.TotalRecordCount -ne $total -or ($count -gt 0 -and [string]$data.Items[0].Id -ne [string]$ownId)) {throw 'Read parity list result/count owner control failed'}
                }
                Write-Host "Read parity $owner $($case.Name) : hidden=$($hidden.Status); missing=$($missing.Status); same=$same; private=$leak"
                if (-not $same -or $leak) {$failures++}
            }
        }
    } finally {$client.Dispose()}
    if ($failures) {throw "Read parity failed for $failures controls"}
}
function SyncPhase($phase) {
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner]
        if ($phase -eq 'baseline') {
            Call 'Sessions/Capabilities/Full' $current.Headers Post @{Id=$current.SessionId;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@()} | Out-Null
            $targets=Probe "Sync baseline $owner targets" "Sync/Targets?UserId=$($current.UserId)" $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other"
            $target=@($targets.Data | Where-Object {$_.Id -eq "native-$owner"})[0]
            if (-not $target.Id) {throw 'No active Sync target: offline file privacy cannot be verified'}
            $current.SyncTargetId=$target.Id
            $nativeXmlStatus=200
            try {$xmlResponse=Invoke-WebRequest -Uri "$base/Sync/Options?UserId=$($current.UserId)&ItemIds=$($current.Items[0].Id)&format=xml" -Headers $current.Headers -UseBasicParsing -TimeoutSec 20}
            catch {if (-not $_.Exception.Response) {throw 'Native XML options failed without HTTP response'};$nativeXmlStatus=[int]$_.Exception.Response.StatusCode}
            $current.SyncOptionsXmlStatus=$nativeXmlStatus
            $results.Add(@{Label="Sync baseline $owner options XML support";Status=$nativeXmlStatus;Supported=($nativeXmlStatus -eq 200);Baseline=$true})
            $job=Probe "Sync baseline $owner create" 'Sync/Jobs' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @{TargetId=$target.Id;ItemIds=@([string]$current.Items[0].Id);Name="PrivateNativeVideo_${owner}_sync";UserId=$current.UserId;Quality='Original';Profile='Original';Downloaded=$false}
            $jobId=if ($job.Data.Job.Id) {$job.Data.Job.Id} else {$job.Data.Id}
            if (-not $jobId) {throw "Sync job positive control failed: HTTP $($job.Status); no job ID"}
            $current.SyncJobId=[string]$jobId
            $createdSyncJobs.Add([string]$jobId)
        }
    }
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner];$foreign=$state[$other]
        foreach ($entry in @(
            @('own job',"Sync/Jobs/$($current.SyncJobId)"),
            @('foreign job',"Sync/Jobs/$($foreign.SyncJobId)"),
            @('jobs',"Sync/Jobs?UserId=$($current.UserId)"),
            @('spoofed jobs',"Sync/Jobs?UserId=$($foreign.UserId)"),
            @('own job items',"Sync/JobItems?JobId=$($current.SyncJobId)&AddMetadata=true"),
            @('foreign job items',"Sync/JobItems?JobId=$($foreign.SyncJobId)&AddMetadata=true"))) {
            Probe "Sync $phase $owner $($entry[0])" $entry[1] $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" | Out-Null
        }
    }
}
function BulkSync($phase) {
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner];$foreign=$state[$other]
        foreach ($entry in @(@('own ready',$current.SyncTargetId),@('foreign ready',$foreign.SyncTargetId))) {
            Probe "Sync $phase $owner $($entry[0])" "Sync/Items/Ready?TargetId=$($entry[1])" $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" | Out-Null
        }
        foreach ($entry in @(@('own data',$current.SyncTargetId,$current.SyncJobItemId),@('foreign data',$foreign.SyncTargetId,$foreign.SyncJobItemId))) {
            Probe "Sync $phase $owner $($entry[0])" 'Sync/Data' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @{TargetId=$entry[1];LocalItemIds=@([string]$entry[2])} | Out-Null
        }
        Probe "Sync $phase $owner own status stub" "Sync/$($current.Items[0].Id)/Status?TargetId=$($current.SyncTargetId)&Progress=12&Status=Transferring" $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post | Out-Null
        Probe "Sync $phase $owner foreign status stub" "Sync/$($foreign.Items[0].Id)/Status?TargetId=$($foreign.SyncTargetId)&Progress=77&Status=Synced" $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post | Out-Null
        Probe "Sync $phase $owner missing status stub" 'Sync/999999999/Status?Progress=12&Status=Transferring' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post | Out-Null
    }
    if ($phase -eq 'protected') {
        foreach ($owner in @('a','b')) {
            $own=@($results | Where-Object {$_.Label -eq "Sync protected $owner own status stub"})[0]
            $hidden=@($results | Where-Object {$_.Label -eq "Sync protected $owner foreign status stub"})[0]
            $missing=@($results | Where-Object {$_.Label -eq "Sync protected $owner missing status stub"})[0]
            if ($own.Status -ne 200 -or $hidden.Status -ne $missing.Status -or (ConvertTo-Json -InputObject $hidden.Data -Depth 5 -Compress) -ne (ConvertTo-Json -InputObject $missing.Data -Depth 5 -Compress)) {throw 'Sync status reveals hidden object existence'}
        }
    }
}
function BulkCancellation() {
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner];$foreign=$state[$other]
        $sourceId=[string]$current.Items[1].Id
        foreach ($kind in @('Cancel','TargetPostDelete','TargetDelete','CancelAll','TargetPostDeleteAll','TargetDeleteAll')) {
            $referenceKind=if ($kind.EndsWith('All')) {'empty list'} else {'video'}
            foreach ($role in @('control','attack')) {
                $created=Call 'Sync/Jobs' $current.Headers Post @{TargetId=$current.SyncTargetId;ItemIds=@($sourceId);UserId=$current.UserId;Quality='Original';Profile='Original';Name="PrivateNativeVideo_${owner}_cancel_$kind"}
                $jobId=[string]$created.Job.Id
                if (-not $jobId) {throw 'Cancellation fixture job creation failed'}
                $createdSyncJobs.Add($jobId)
                $before=Call "Sync/JobItems?JobId=$jobId" $current.Headers
                if ($before.Items.Count -ne 1 -or $before.Items[0].ItemId -ne $sourceId) {throw 'Cancellation source readback failed'}
                $ids=if ($referenceKind -eq 'empty list') {''} elseif ($referenceKind -eq 'video') {$sourceId} else {[string]$before.Items[0].Id}
                $headers=if ($role -eq 'control') {$current.Headers} else {$foreign.Headers}
                foreach ($attemptNumber in 1..2) {
                    $path=if ($kind.StartsWith('Cancel')) {'Sync/Items/Cancel'} elseif ($kind.StartsWith('TargetPostDelete')) {"Sync/$($current.SyncTargetId)/Items/Delete"} else {"Sync/$($current.SyncTargetId)/Items?ItemIds=$ids"}
                    $method=if ($kind.StartsWith('TargetDelete')) {'Delete'} else {'Post'}
                    $body=if ($method -eq 'Post') {@{TargetId=$current.SyncTargetId;ItemIds=$ids}} else {$null}
                    $result=Probe "Cancellation $kind $owner $role $referenceKind" $path $headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false $method $body
                    try {$after=Call "Sync/JobItems?JobId=$jobId" $current.Headers}
                    catch {
                        if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) {throw}
                        $jobs=Call "Sync/Jobs?UserId=$($current.UserId)" $current.Headers
                        if (@($jobs.Items | Where-Object {$_.Id -eq $jobId}).Count) {throw 'Job item read failed while owner job still exists'}
                        $after=@{Items=@();TotalRecordCount=0;JobMissing=$true}
                    }
                    $changed=((ConvertTo-Json -InputObject $before -Depth 15 -Compress) -ne (ConvertTo-Json -InputObject $after -Depth 15 -Compress))
                    if ($role -eq 'control' -and -not $changed -and $attemptNumber -eq 1 -and $referenceKind -ne 'empty list') {$referenceKind='job item';$ids=[string]$before.Items[0].Id;continue}
                    break
                }
                $results.Add(@{Label="Cancellation $kind $owner $role readback";Status=$result.Status;Other=($role -eq 'attack' -and $changed);ReferenceKind=$referenceKind;CountBefore=$before.Items.Count;CountAfter=$after.Items.Count})
                Write-Output "Cancellation $kind $owner $role : HTTP $($result.Status); reference=$referenceKind; item count $($before.Items.Count) -> $($after.Items.Count)"
                if ($role -eq 'control') {
                    if ($referenceKind -eq 'empty list') {
                        if ($changed) {throw 'Empty cancellation list changed job state'}
                    } elseif ($result.Status -notin @(200,204) -or $after.Items.Count -ne 0) {throw 'Bulk cancellation owner positive control failed'}
                }
                if ($role -eq 'attack' -and ($changed -or ($referenceKind -ne 'empty list' -and $result.Status -ne 404))) {throw 'Foreign bulk cancellation changed owner data or was not denied'}
            }
        }
    }
}
function OfflineActions($phase) {
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner];$foreign=$state[$other]
        $itemId=[string]$current.Items[0].Id
        $date=[DateTimeOffset]::UtcNow
        $ownAction=@{Id=[guid]::NewGuid().ToString('N');ServerId=$info.Id;UserId=$current.UserId;ItemId=$itemId;Type='PlayedItem';Played=$true;PositionTicks=60000000;Date=$date.ToString('o')}
        $own=Probe "Offline $phase $owner own played" 'Sync/OfflineActions' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @($ownAction)
        $before=Call "Users/$($current.UserId)/Items/${itemId}?Fields=UserDataLastPlayedDate" $current.Headers
        $results.Add(@{Label="Offline $phase $owner owner state";Baseline=($phase -eq 'baseline');Data=$before.UserData})
        if ($own.Status -ne 200 -or -not $before.UserData.Played) {throw 'Offline action own positive control failed'}
        $attempt=$ownAction.Clone();$attempt.Id=[guid]::NewGuid().ToString('N');$attempt.PositionTicks=0;$attempt.Date=$date.AddSeconds(1).ToString('o')
        $attack=Probe "Offline $phase $other foreign played" 'Sync/OfflineActions' $foreign.Headers "PrivateNativeVideo_$other" "PrivateNativeVideo_$owner" $false Post @($attempt)
        $after=Call "Users/$($current.UserId)/Items/${itemId}?Fields=UserDataLastPlayedDate" $current.Headers
        $changed=($after.UserData.Played -ne $before.UserData.Played -or $after.UserData.LastPlayedDate -ne $before.UserData.LastPlayedDate)
        $results.Add(@{Label="Offline $phase $other mutation readback";Baseline=($phase -eq 'baseline');Status=$attack.Status;Other=$changed;OwnerPlayedBefore=$before.UserData.Played;OwnerPlayedAfter=$after.UserData.Played;OwnerPlayedDateBefore=$before.UserData.LastPlayedDate;OwnerPlayedDateAfter=$after.UserData.LastPlayedDate})
        Write-Output "Offline $phase $other cross-owner state changed: $changed"
        if ($phase -eq 'protected') {
            if ($attack.Status -ne 404 -or $changed) {throw 'Offline foreign action was not rejected without side effects'}
            $allowed=$ownAction.Clone();$allowed.Id=[guid]::NewGuid().ToString('N');$allowed.Date=$date.AddSeconds(2).ToString('o')
            $hidden=$ownAction.Clone();$hidden.Id=[guid]::NewGuid().ToString('N');$hidden.ItemId=[string]$foreign.Items[0].Id;$hidden.Date=$date.AddSeconds(3).ToString('o')
            $mixed=Probe "Offline protected $owner mixed batch" 'Sync/OfflineActions' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $false Post @($allowed,$hidden)
            $afterMixed=Call "Users/$($current.UserId)/Items/${itemId}?Fields=UserDataLastPlayedDate" $current.Headers
            $mixedChanged=($afterMixed.UserData.LastPlayedDate -ne $after.UserData.LastPlayedDate -or $afterMixed.UserData.Played -ne $after.UserData.Played)
            $results.Add(@{Label="Offline protected $owner mixed batch readback";Other=$mixedChanged;Status=$mixed.Status;OwnerPlayedDateBefore=$after.UserData.LastPlayedDate;OwnerPlayedDateAfter=$afterMixed.UserData.LastPlayedDate})
            if ($mixed.Status -ne 404 -or $mixedChanged) {throw 'Mixed offline batch was partially applied before denial'}
        }
    }
}
function SyncFiles($phase) {
    if ($ProbeRealSyncFiles -and -not $ProbeSync) {throw 'Real Sync files require Sync setup'}
    if ($phase -eq 'baseline') {
        $tasks=Call 'ScheduledTasks'
        $taskInventory=@($tasks | Select-Object Id,Name,Key,State)
        $taskInventory | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/sync-tasks.json') -Encoding UTF8
        $syncTasks=@($tasks | Where-Object {$_.Key -eq 'SyncPrepare'})
        Write-Output ('Sync processor candidates: '+(($syncTasks | ForEach-Object {$_.Name+' ['+$_.Key+']'}) -join ', '))
        foreach ($task in $syncTasks) {
            Call "ScheduledTasks/Running/$($task.Id)" $admin Post | Out-Null
            $deadline=[DateTime]::UtcNow.AddSeconds(15)
            do {Start-Sleep -Milliseconds 200;$taskState=Call "ScheduledTasks/$($task.Id)"} while ($taskState.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
            $results.Add(@{Label='Sync processor '+$task.Name;Baseline=$true;Data=$taskState.LastExecutionResult})
        }
    }
    foreach ($owner in @('a','b')) {
        $current=$state[$owner]
        $ownItems=Call "Sync/JobItems?JobId=$($current.SyncJobId)&AddMetadata=true" $current.Headers
        if ($ownItems.Items.Count -ne 1 -or $ownItems.Items[0].ItemId -ne $current.Items[0].Id) {throw 'Own Sync job item positive control failed'}
        $current.SyncJobItemId=[string]$ownItems.Items[0].Id
        if ($ProbeRealSyncFiles -and $phase -eq 'baseline') {
            $deadline=[DateTime]::UtcNow.AddSeconds(30)
            while ($ownItems.Items[0].Status -ne 'ReadyToTransfer' -and [DateTime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 200
                $ownItems=Call "Sync/JobItems?JobId=$($current.SyncJobId)&AddMetadata=true" $current.Headers
            }
            $results.Add(@{Label="Real Sync $phase $owner native preparation";NativeStatus=$ownItems.Items[0].Status;Baseline=$true})
            if ($ownItems.Items[0].Status -ne 'ReadyToTransfer') {throw 'Native Sync did not prepare a real file'}
        }
        if ($phase -eq 'baseline' -and $fixtureInstalled) {$results.Add(@{Label="Sync feature checks $owner";Baseline=$true;Data=(Call 'PersonalChannelsFixture/Surface').SyncSecurity.FeatureChecks})}
    }
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner];$foreign=$state[$other]
        Probe "Sync $phase $owner jobs without user" 'Sync/Jobs' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" | Out-Null
        Probe "Sync $phase $owner jobs first page" 'Sync/Jobs?StartIndex=0&Limit=1' $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" | Out-Null
        foreach ($entry in @(@('own file',$current.SyncJobItemId,$current.Headers),@('foreign file',$foreign.SyncJobItemId,$current.Headers),@('anonymous file',$current.SyncJobItemId,@{}))) {
            Probe "Sync $phase $owner $($entry[0])" "Sync/JobItems/$($entry[1])/File" $entry[2] "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" $true | Out-Null
        }
        Probe "Sync $phase $owner foreign additional files" "Sync/JobItems/$($foreign.SyncJobItemId)/AdditionalFiles" $current.Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other" | Out-Null
        if ($ProbeRealSyncFiles) {VerifyRealSyncFile $owner $phase}
    }
    if ($phase -eq 'protected') {
        foreach ($owner in @('a','b')) {
            $own=@($results | Where-Object {$_.Label -eq "Sync protected $owner own job"})[0]
            $page=@($results | Where-Object {$_.Label -eq "Sync protected $owner jobs first page"})[0]
            $foreign=@($results | Where-Object {$_.Label -eq "Sync protected $owner foreign job"})[0]
            if ($own.Status -ne 200 -or -not $own.Own -or $own.Other) {throw 'Own Sync job read failed'}
            if ($page.Status -ne 200 -or $page.Data.TotalRecordCount -ne 1 -or $page.Data.Items.Count -ne 1 -or -not $page.Own -or $page.Other) {throw 'Sync filtering before pagination failed'}
            if ($foreign.Status -ne 404) {throw 'Direct foreign Sync job was not denied'}
            $before=Call "Sync/Jobs/$($state[$owner].SyncJobId)" $state[$owner].Headers
            $ownUpdate=Probe "Sync protected $owner own update" "Sync/Jobs/$($before.Id)" $state[$owner].Headers "PrivateNativeVideo_$owner" 'not-a-marker' $false Post $before
            if ($ownUpdate.Status -ne 200 -and $ownUpdate.Status -ne 204) {throw 'Own Sync update positive control failed'}
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $attempt=$before | ConvertTo-Json -Depth 15 | ConvertFrom-Json
            $attempt.Name='Cross-owner change must be rejected'
            $crossUpdate=Probe "Sync protected $other foreign update" "Sync/Jobs/$($before.Id)" $state[$other].Headers 'not-a-marker' 'not-a-marker' $false Post $attempt
            $crossDelete=Probe "Sync protected $other foreign delete" "Sync/Jobs/$($before.Id)" $state[$other].Headers 'not-a-marker' 'not-a-marker' $false Delete
            $after=Call "Sync/Jobs/$($before.Id)" $state[$owner].Headers
            if ($crossUpdate.Status -ne 404 -or $crossDelete.Status -ne 404 -or $after.Name -ne $before.Name -or $after.ItemId -ne $before.ItemId -or $after.UserId -ne $before.UserId) {throw 'Denied Sync mutation changed another owner job'}
        }
    }}
function VerifyRealSyncFile($owner,$phase,$jobItemId=$state[$owner].SyncJobItemId,$scope='') {
    $current=$state[$owner]
    $other=if ($owner -eq 'a') {'b'} else {'a'}
    $path="Sync/JobItems/$jobItemId/File"
    $expectedHash=(Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash
    $expectedBytes=(Get-Item -LiteralPath $sample).Length
    foreach ($actor in @('owner','foreign','anonymous')) {
        $headers=if ($actor -eq 'owner') {$current.Headers} elseif ($actor -eq 'foreign') {$state[$other].Headers} else {@{}}
        $row=Probe "Real Sync $phase$scope $owner file by $actor" $path $headers 'no-marker' 'no-marker' $true
        $row.Baseline=$phase -eq 'baseline'
        $row.SourceMatch=$row.Status -eq 200 -and $row.Bytes -eq $expectedBytes -and $row.Sha256 -eq $expectedHash
        if ($actor -eq 'owner' -and -not $row.SourceMatch) {throw 'Own real Sync file differs from the synthetic source'}
        if ($phase -eq 'baseline' -and $actor -eq 'foreign' -and -not $row.SourceMatch) {throw 'Real-file baseline lacks the foreign-access positive control'}
        if ($phase -eq 'protected' -and $actor -eq 'foreign' -and ($row.Status -ne 404 -or $row.Bytes -ne 0)) {throw 'Foreign real Sync file is not blocked'}
        if ($phase -eq 'protected' -and $actor -eq 'anonymous' -and ($row.Status -notin @(401,403,404) -or $row.Bytes -ne 0)) {throw 'Anonymous real Sync file is not blocked'}
    }
}
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=30}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 20}
    Invoke-RestMethod @args
}
function Probe($label,$path,$headers,$ownMarker,$forbiddenMarker,$binary=$false,$method='Get',$body=$null) {
    $status=200;$content=$null;$bytes=0;$sha256=$null
    try {
        if ($binary) {
            $response=Invoke-WebRequest -Uri "$base/$path" -Headers $headers -Method $method -UseBasicParsing -TimeoutSec 30
            $bytes=$response.RawContentLength
            $response.RawContentStream.Position=0
            $digest=[Security.Cryptography.SHA256]::Create()
            try {$sha256=[BitConverter]::ToString($digest.ComputeHash($response.RawContentStream)).Replace('-','')} finally {$digest.Dispose()}
        }
        else {$content=Call $path $headers $method $body}
    } catch {
        if (-not $_.Exception.Response) {throw 'Request failed without HTTP response'}
        $status=[int]$_.Exception.Response.StatusCode
        if (-not $binary) {
            $reader=[IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            try {$content=@{Error=$reader.ReadToEnd();Details=$_.ErrorDetails.Message}} finally {$reader.Dispose()}
        }
    }
    $json=if ($null -eq $content) {''} else {ConvertTo-Json -InputObject $content -Depth 30 -Compress}
    $row=@{Label=$label;Status=$status;Own=$json.Contains($ownMarker);Other=$json.Contains($forbiddenMarker);Bytes=$bytes;Sha256=$sha256;Data=$content;Baseline=$label.StartsWith('Sync baseline ')}
    $results.Add($row)
    Write-Host "$label : HTTP $status; own=$($row.Own); other=$($row.Other); bytes=$bytes"
    return $row
}
function SoapProbe($phase,$owner,$objectId,$flag,$headers,$start=0,$limit=100) {
    $body='<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>'+[Security.SecurityElement]::Escape([string]$objectId)+'</ObjectID><BrowseFlag>'+ $flag +'</BrowseFlag><Filter>*</Filter><StartingIndex>'+ $start +'</StartingIndex><RequestedCount>'+ $limit +'</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>'
    $requestHeaders=@{SOAPAction='"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"'}
    foreach ($key in $headers.Keys) {$requestHeaders[$key]=$headers[$key]}
    $status=200;$text=''
    try {$response=Invoke-WebRequest -Uri "$base/Dlna/$($info.Id)/contentdirectory/control" -Method Post -Headers $requestHeaders -ContentType 'text/xml; charset=utf-8' -Body $body -UseBasicParsing -TimeoutSec 20;$text=[string]$response.Content}
    catch {if (-not $_.Exception.Response) {throw 'SOAP request failed without response'};$status=[int]$_.Exception.Response.StatusCode}
    $other=if ($owner -eq 'a') {'b'} else {'a'}
    $safeText=[regex]::Replace($text,'(?i)(api_key|token|X-Emby-Token)(=|%3[dD])[^&\s<"'']+','$1$2[redacted]')
    $decoded=[Net.WebUtility]::HtmlDecode([Net.WebUtility]::HtmlDecode($text))
    $issued=@([regex]::Matches($decoded,'(?i)[?&](?:api_key|X-Emby-Token)=([^&\s<"'']+)') | ForEach-Object { [Uri]::UnescapeDataString($_.Groups[1].Value) } | Select-Object -Unique)
    $subjects=@()
    $resources=@()
    $script:lastDlnaResourceUris=@()
    if ($RequireProtected) {
        foreach ($credential in $issued) {
            try {
                $identity=Call 'PersonalChannelsFixture/Subject' @{'X-Emby-Token'=$credential}
                $adminStatus=200
                try {Call 'System/Logs' @{'X-Emby-Token'=$credential} | Out-Null} catch {if (-not $_.Exception.Response) {throw 'Credential privilege request failed without response'};$adminStatus=[int]$_.Exception.Response.StatusCode}
                $subjects+=@{UserId=$identity.UserId;IsAdministrator=$identity.IsAdministrator;MatchesCaller=($identity.UserId -eq $state[$owner].UserId);PrivilegeEndpoint='System/Logs';PrivilegeEndpointStatus=$adminStatus}
            }
            catch {if (-not $_.Exception.Response) {throw 'Issued DLNA credential test failed without HTTP response'};$subjects+=@{Status=[int]$_.Exception.Response.StatusCode;MatchesCaller=$false}}
        }
    }
    if ($phase.StartsWith('protected') -and $text.Contains('BrowseResponse')) {
        $envelope=[xml]$text
        $resultNode=$envelope.SelectSingleNode("//*[local-name()='Result']")
        if ($resultNode -and $resultNode.InnerText) {
            $didl=[xml]$resultNode.InnerText
            foreach ($node in $didl.SelectNodes("//*[local-name()='res']")) {
                $uri=[uri]$node.InnerText
                $script:lastDlnaResourceUris+=@($uri)
                if ($uri.Host -ne '127.0.0.1' -or $uri.Port -ne 18096) {throw 'Unexpected DLNA resource origin'}
                $resourceStatus=200;$resourceBytes=0
                try {$media=Invoke-WebRequest -Uri $uri.AbsoluteUri -UseBasicParsing -TimeoutSec 20;$resourceBytes=$media.RawContentLength}
                catch {if (-not $_.Exception.Response) {throw 'DLNA resource request failed without response'};$resourceStatus=[int]$_.Exception.Response.StatusCode}
                $resources+=@{Status=$resourceStatus;Bytes=$resourceBytes}
            }
        }
    }
    $total=$null;$returned=$null
    if ($text.Contains('BrowseResponse')) {$envelope=[xml]$text;$total=[int]$envelope.SelectSingleNode("//*[local-name()='TotalMatches']").InnerText;$returned=[int]$envelope.SelectSingleNode("//*[local-name()='NumberReturned']").InnerText}
    $row=@{Label="DLNA $phase $owner $flag $objectId page=$start/$limit";Status=$status;Own=$text.Contains("PrivateNativeVideo_$owner") -or $text.Contains("Private Native Fixture $owner");Other=$text.Contains("PrivateNativeVideo_$other") -or $text.Contains("Private Native Fixture $other");Anonymous=($headers.Count -eq 0);Baseline=($phase -eq 'baseline');SoapResponse=$text.Contains('BrowseResponse');Total=$total;Returned=$returned;IssuedCredentialCount=$issued.Count;IssuedCredentialSubjects=$subjects;ResourceResults=$resources;Data=$safeText}
    if ($phase -eq 'protected' -and $row.Own -and $flag -eq 'BrowseDirectChildren' -and $objectId -eq $state[$owner].LibraryId -and $limit -eq 100) {
        if ($resources.Count -ne 2 -or @($resources | Where-Object {$_.Status -ne 200 -or $_.Bytes -lt 1000}).Count) {throw 'Own DLNA media links are not playable'}
    }
    $results.Add($row)
    Write-Host "$($row.Label) : HTTP $status; SOAP=$($row.SoapResponse); own=$($row.Own); other=$($row.Other)"
    if ($phase -eq 'protected' -and $headers.Count -ne 0 -and $flag -eq 'BrowseDirectChildren' -and ($objectId -eq 0 -or $objectId -eq $state[$owner].LibraryId)) {
        $envelope=[xml]$text;$didl=[xml]$envelope.SelectSingleNode("//*[local-name()='Result']").InnerText
        $ids=@($didl.DocumentElement.ChildNodes | Where-Object NodeType -eq Element | ForEach-Object {$_.GetAttribute('id')})
        if ($limit -eq 100) {
            if ($status -ne 200 -or -not $row.Own -or $total -ne $returned -or $returned -ne $ids.Count) {throw 'Full SOAP root positive control failed'}
            $soapRootControls["${owner}:$objectId"]=@{Total=$total;Ids=$ids}
        } else {
            $control=$soapRootControls["${owner}:$objectId"]
            $expectedIds=@($control.Ids | Select-Object -Skip $start -First $limit)
            if ($status -ne 200 -or $total -ne $control.Total -or $returned -ne $expectedIds.Count -or ($ids -join ',') -ne ($expectedIds -join ',')) {throw 'SOAP owner pagination or total count failed'}
        }
    }
}
function DlnaPhase($phase) {
    if (-not $info.Id) {throw 'Server UUID missing for SOAP test'}
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        SoapProbe $phase $owner 0 'BrowseDirectChildren' $state[$owner].Headers
        SoapProbe $phase $owner 0 'BrowseDirectChildren' $state[$owner].Headers 0 1
        SoapProbe $phase $owner 0 'BrowseDirectChildren' $state[$owner].Headers 1 1
        SoapProbe $phase $owner 0 'BrowseDirectChildren' $state[$owner].Headers 3 1
        SoapProbe $phase $owner $state[$owner].LibraryId 'BrowseDirectChildren' $state[$owner].Headers
        SoapProbe $phase $owner $state[$owner].LibraryId 'BrowseDirectChildren' $state[$owner].Headers 0 1
        SoapProbe $phase $owner $state[$owner].LibraryId 'BrowseDirectChildren' $state[$owner].Headers 1 1
        SoapProbe $phase $owner $state[$owner].LibraryId 'BrowseDirectChildren' $state[$owner].Headers 2 1
        SoapProbe $phase $owner $state[$owner].Items[0].Id 'BrowseMetadata' $state[$owner].Headers
        SoapProbe $phase $owner $state[$other].LibraryId 'BrowseDirectChildren' $state[$owner].Headers
        SoapProbe $phase $owner $state[$other].Items[0].Id 'BrowseMetadata' $state[$owner].Headers
        SoapProbe $phase $owner 999999999 'BrowseMetadata' $state[$owner].Headers
    }
    SoapProbe $phase 'a' $state['a'].LibraryId 'BrowseDirectChildren' @{}
    if ($phase -eq 'protected') {
        foreach ($owner in @('a','b')) {
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $prefix="DLNA protected $owner BrowseMetadata "
            $hidden=@($results | Where-Object {$_.Label -eq ($prefix+$state[$other].Items[0].Id+' page=0/100')})[0]
            $missing=@($results | Where-Object {$_.Label -eq ($prefix+'999999999 page=0/100')})[0]
            $own=@($results | Where-Object {$_.Label -eq ($prefix+$state[$owner].Items[0].Id+' page=0/100')})[0]
            if (-not $hidden -or -not $missing -or $hidden.Status -ne $missing.Status -or $hidden.Data -ne $missing.Data) {throw 'Hidden SOAP object differs from a missing object'}
            if (-not $own -or $own.Status -ne 200 -or -not $own.SoapResponse -or -not $own.Own -or $own.Total -ne 1) {throw 'Own SOAP metadata positive control failed'}
        }
    }
}
try {
    if (Test-Path (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')) {throw 'Native test requires privacy fixture uninstalled'}
    if ($RequireProtected) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
        $fixtureInstalled=$true
    }
    $sample=Join-Path $PSScriptRoot 'bin/native-sample.mp4'
    $createdFiles.Add($sample)
    & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel error -f lavfi -i 'color=c=blue:s=160x90:r=25:d=6' -f lavfi -i 'anullsrc=r=44100:cl=stereo' -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac -y $sample
    if ($LASTEXITCODE -ne 0) {throw 'Synthetic native media generation failed'}
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    if ($ProbeSync -and $fixtureInstalled) {Call 'PersonalChannelsFixture/Surface' | Out-Null}
    $state=@{}
    foreach ($owner in @('a','b')) {
        $name="Private Native Fixture $owner"
        $folder=Join-Path $PSScriptRoot "bin/native-$owner"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        foreach ($number in 1..2) {
            $stem=Join-Path $folder "PrivateNativeVideo_${owner}_$number"
            Copy-Item -LiteralPath $sample -Destination ($stem+'.mp4')
            $createdFiles.Add($stem+'.mp4')
            [IO.File]::WriteAllText($stem+'.nfo',"<movie><title>PrivateNativeVideo_${owner}_$number</title><genre>PrivateNativeGenre_$owner</genre><genre>SharedNativeGenre</genre><studio>PrivateNativeStudio_$owner</studio><tag>PrivateNativeTag_$owner</tag></movie>")
            $createdFiles.Add($stem+'.nfo')
        }
        $existing=Call 'Library/VirtualFolders/Query'
        if (@($existing.Items | Where-Object Name -eq $name).Count) {throw 'Test library already exists'}
        Call 'Library/VirtualFolders' $admin Post @{Name=$name;CollectionType='homevideos';Paths=@($folder);RefreshLibrary=$false;LibraryOptions=@{EnableRealtimeMonitor=$false;EnableChapterImageExtraction=$false;ExtractChapterImagesDuringLibraryScan=$false;DownloadImagesInAdvance=$false;SaveLocalMetadata=$false;TypeOptions=@(@{Type='Video';MetadataFetchers=@();ImageFetchers=@()})}} | Out-Null
        $libraries=Call 'Library/VirtualFolders/Query'
        $library=@($libraries.Items | Where-Object Name -eq $name)[0]
        if (-not $library.ItemId) {throw 'Library ID missing'}
        $createdLibraries.Add($library.ItemId)
        $user=Call 'Users/New' $admin Post @{Name="native-privacy-fixture-$owner"}
        $createdUsers.Add($user.Id)
        $policy=$user.Policy
        if (-not $library.Guid) {throw 'Library GUID missing'}
        $policy.EnableAllFolders=$false;$policy.EnabledFolders=@($library.Guid)
        $policy.EnableAllChannels=$false;$policy.EnabledChannels=@()
        $policy.EnableContentDownloading=$true;$policy.EnableRemoteControlOfOtherUsers=$true
        if ($ProbeStrictUserPolicy) {
            $policy.EnableRemoteControlOfOtherUsers=$false
            if (-not $policy.PSObject.Properties['EnableSharedDeviceControl']) {throw 'Strict native policy lacks EnableSharedDeviceControl'}
            $policy.EnableSharedDeviceControl=$false
        }
        Call "Users/$($user.Id)/Policy" $admin Post $policy | Out-Null
        $readback=(Call "Users/$($user.Id)").Policy
        if ($readback.IsAdministrator) {throw 'Native test subject unexpectedly has administrator access'}
        if ($ProbeStrictUserPolicy) {
            if ($readback.EnableRemoteControlOfOtherUsers -or $readback.EnableSharedDeviceControl) {throw 'Strict native policy failed readback'}
            $results.Add(@{Label="Strict native policy $owner";IsAdministrator=$readback.IsAdministrator;EnableRemoteControlOfOtherUsers=$readback.EnableRemoteControlOfOtherUsers;EnableSharedDeviceControl=$readback.EnableSharedDeviceControl;Baseline=(-not $RequireProtected)})
        }
        if ($readback.EnableAllFolders -or $readback.EnabledFolders.Count -ne 1 -or $readback.EnabledFolders[0] -ne $library.Guid) {throw 'Library policy readback failed'}
        $subjects.Add(@{Owner=$owner;UserId=$user.Id;IsAdministrator=$readback.IsAdministrator;EnableAllFolders=$readback.EnableAllFolders;EnabledFolders=$readback.EnabledFolders;LibraryId=$library.ItemId;LibraryGuid=$library.Guid})
        $session=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Native libraries test`", Device=`"Isolated test`", DeviceId=`"native-$owner`", Version=`"1.0`""} Post @{Username=$user.Name;Pw=''}
        if ($session.User.Id -ne $user.Id -or $session.User.Policy.IsAdministrator) {throw 'Native session subject validation failed'}
        $state[$owner]=@{UserId=$user.Id;Headers=@{'X-Emby-Token'=$session.AccessToken};LibraryId=$library.ItemId;SessionId=$session.SessionInfo.Id}
        Call "Items/$($library.ItemId)/Refresh?Recursive=true&MetadataRefreshMode=FullRefresh&ImageRefreshMode=ValidationOnly" $admin Post | Out-Null
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(90)
    do {
        $ready=$true
        foreach ($owner in @('a','b')) {
            $items=Call "Items?ParentId=$($state[$owner].LibraryId)&Recursive=true&IncludeItemTypes=Video&Fields=Genres,Studios,Tags,MediaSources"
            $state[$owner].Items=@($items.Items)
            if ($state[$owner].Items.Count -ne 2) {$ready=$false}
        }
        if (-not $ready) {Start-Sleep -Milliseconds 200}
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    if (-not $ready) {throw 'Native library scan did not produce two videos per owner'}
    if ($ProbeDlna) {
        $originalDlna=Call 'System/Configuration/dlna'
        $dlna=$originalDlna | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $dlna.EnableServer=$true;$dlna.EnablePlayTo=$false
        Call 'System/Configuration/dlna' $admin Post $dlna | Out-Null
        if (-not (Call 'System/Configuration/dlna').EnableServer) {throw 'DLNA enable readback failed'}
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do {try {$description=Invoke-WebRequest "$base/Dlna/$($info.Id)/description.xml" -UseBasicParsing -TimeoutSec 2;break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    }
    if ($ProbeConfiguration) {ConfigurationBoundary}
    if ($ProbeVisibility) {NativeVisibilityObservation}
    if ($ProbeDlna) {DlnaPhase 'baseline'}
    if ($ProbeSync) {SyncPhase 'baseline';SyncFiles 'baseline';BulkSync 'baseline';OfflineActions 'baseline'}
    if ($RequireProtected) {
        $mapping=@{}
        foreach ($owner in @('a','b')) {$mapping[$state[$owner].LibraryId]=$state[$owner].UserId}
        $firstBoot=Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$mapping}
        foreach ($owner in @('a','b')) {
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $ownVideo=$state[$owner].Items[0];$foreignVideo=$state[$other].Items[0]
            $own=Probe "$owner Before restart own item" "Users/$($state[$owner].UserId)/Items/$($ownVideo.Id)" $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other"
            $cross=Probe "$owner Before restart cross item" "Users/$($state[$owner].UserId)/Items/$($foreignVideo.Id)" $state[$owner].Headers "PrivateNativeVideo_$owner" "PrivateNativeVideo_$other"
            if ($own.Status -ne 200 -or -not $own.Own -or $cross.Status -ne 404) {throw 'Before restart ownership control failed'}
        }
        & $control -Stop
        & $control
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
        if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong restarted server'}
        $secondBoot=Call 'PersonalChannelsFixture/Guard'
        if (-not $secondBoot.Ready -or -not $secondBoot.Enabled -or $firstBoot.BootId -eq $secondBoot.BootId) {throw 'Saved native ownership did not survive a verified restart'}
        Write-Output 'PASS: Saved ownership restored in a new server process'
    }
    if ($ProbeDlna -and $RequireProtected) {DlnaPhase 'protected'}
    if ($ProbeSync -and $RequireProtected) {SyncPhase 'protected';SyncFiles 'protected';BulkSync 'protected';OfflineActions 'protected';BulkCancellation}
    foreach ($owner in @('a','b')) {
        $other=if ($owner -eq 'a') {'b'} else {'a'}
        $current=$state[$owner];$foreign=$state[$other]
        $ownMarker="PrivateNativeVideo_$owner";$foreignMarker="PrivateNativeVideo_$other"
        $video=$current.Items[0];$cross=$foreign.Items[0]
        $own=Probe "$owner Own item" "Users/$($current.UserId)/Items/$($video.Id)" $current.Headers $ownMarker $foreignMarker
        if ($own.Status -ne 200 -or -not $own.Own) {throw 'Native owner positive control failed'}
        $visible=Call "Items?UserId=$($current.UserId)&Recursive=true&SearchTerm=PrivateNativeVideo&SortBy=SortName" $current.Headers
        if ($visible.Items.Count -ne 2 -or $visible.TotalRecordCount -ne 2) {throw 'Native owner search positive control failed'}
        $paths=[ordered]@{
            'Global search'="Items?UserId=$($current.UserId)&Recursive=true&SearchTerm=PrivateNativeVideo&SortBy=SortName"
            'Global search without user'='Items?Recursive=true&SearchTerm=PrivateNativeVideo&SortBy=SortName'
            'Page 1'="Items?UserId=$($current.UserId)&Recursive=true&SearchTerm=PrivateNativeVideo&SortBy=SortName&StartIndex=0&Limit=1"
            'Page 2'="Items?UserId=$($current.UserId)&Recursive=true&SearchTerm=PrivateNativeVideo&SortBy=SortName&StartIndex=1&Limit=1"
            'Latest'="Users/$($current.UserId)/Items/Latest?IncludeItemTypes=Video&GroupItems=false&Limit=10"
            'Views'="Users/$($current.UserId)/Views"
            'Virtual folders'='Library/VirtualFolders/Query'
            'Virtual folders array'='Library/VirtualFolders'
            'Media folders'="Library/MediaFolders?UserId=$($current.UserId)"
            'Virtual folders first page'='Library/VirtualFolders/Query?StartIndex=0&Limit=1'
            'Virtual folders second page'='Library/VirtualFolders/Query?StartIndex=1&Limit=1'
            'Cross direct'="Users/$($current.UserId)/Items/$($cross.Id)"
            'Cross direct spoof owner'="Users/$($foreign.UserId)/Items/$($cross.Id)"
            'Cross item IDs'="Items?Ids=$($cross.Id)&UserId=$($current.UserId)"
            'Cross parent'="Items?ParentId=$($foreign.LibraryId)&UserId=$($current.UserId)&Recursive=true"
            'Cross PlaybackInfo'="Items/$($cross.Id)/PlaybackInfo?UserId=$($current.UserId)"
            'Cross PlaybackInfo spoof owner'="Items/$($cross.Id)/PlaybackInfo?UserId=$($foreign.UserId)"
            'Genres'="Genres?UserId=$($current.UserId)"
            'Genres without user'='Genres'
            'Studios'="Studios?UserId=$($current.UserId)"
            'Studios without user'='Studios'
            'Tags'="Tags?UserId=$($current.UserId)"
            'Tags without user'='Tags'
        }
        foreach ($label in $paths.Keys) {
            $marker=if ($label.StartsWith('Genre')) {"PrivateNativeGenre_$other"} elseif ($label.StartsWith('Studio')) {"PrivateNativeStudio_$other"} elseif ($label.StartsWith('Tag')) {"PrivateNativeTag_$other"} elseif ($label -in @('Views','Media folders') -or $label.StartsWith('Virtual')) {"Private Native Fixture $other"} else {$foreignMarker}
            $positiveMarker=if ($label.StartsWith('Genre')) {"PrivateNativeGenre_$owner"} elseif ($label.StartsWith('Studio')) {"PrivateNativeStudio_$owner"} elseif ($label.StartsWith('Tag')) {"PrivateNativeTag_$owner"} elseif ($label -in @('Views','Media folders') -or $label.StartsWith('Virtual')) {"Private Native Fixture $owner"} else {$ownMarker}
            $observation=Probe "$owner $label" $paths[$label] $current.Headers $positiveMarker $marker
            if ($label -in @('Page 1','Page 2') -and ($observation.Status -ne 200 -or $observation.Data.Items.Count -ne 1 -or $observation.Data.TotalRecordCount -ne 2 -or -not $observation.Own)) {throw 'Native owner pagination positive control failed'}
            if ($RequireProtected -and $label -in @('Cross item IDs','Cross parent')) {
                if ($observation.Status -ne 200 -or $observation.Data.Items.Count -ne 0 -or $observation.Data.TotalRecordCount -ne 0 -or $observation.Other -or $observation.Own) {throw 'Expected empty cross-owner list with zero count'}
            } elseif ($RequireProtected -and $label.StartsWith('Cross') -and $observation.Status -ne 404) {throw 'Expected explicit denial for cross-owner request'}
            if ($RequireProtected -and $label -in @('Views','Genres','Genres without user','Studios','Studios without user','Tags','Tags without user','Latest','Virtual folders array','Media folders') -and ($observation.Status -ne 200 -or -not $observation.Own -or $observation.Other)) {throw 'Native own overview positive control failed'}
            if ($RequireProtected -and $label -in @('Virtual folders','Virtual folders first page') -and ($observation.Status -ne 200 -or -not $observation.Own -or $observation.Other -or $observation.Data.Items.Count -ne 1 -or $observation.Data.TotalRecordCount -ne 1)) {throw 'Native virtual folder pagination positive control failed'}
            if ($RequireProtected -and $label -eq 'Virtual folders second page' -and ($observation.Status -ne 200 -or $observation.Data.Items.Count -ne 0 -or $observation.Data.TotalRecordCount -ne 1)) {throw 'Native virtual folder end pagination failed'}
        }
        $ownBytes=Probe "$owner Own stream" "Videos/$($video.Id)/stream.mp4?Static=true" $current.Headers $ownMarker $foreignMarker $true
        if ($ownBytes.Status -ne 200 -or $ownBytes.Bytes -lt 1000) {throw 'Native owner playback positive control failed'}
        Probe "$owner Cross stream" "Videos/$($cross.Id)/stream.mp4?Static=true" $current.Headers $ownMarker $foreignMarker $true | Out-Null
        Probe "$owner Cross download" "Items/$($cross.Id)/Download" $current.Headers $ownMarker $foreignMarker $true | Out-Null
    }
    if ($ProbeNewRoot) {
        if (-not $RequireProtected) {throw 'New root test requires privacy fixture'}
        $folder=Join-Path $PSScriptRoot 'bin/native-c'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $file=Join-Path $folder 'LibraryInitial_c_1.mp4'
        Copy-Item -LiteralPath $sample -Destination $file
        $createdFiles.Add($file)
        Call 'Library/VirtualFolders' $admin Post @{Name='Private Native Fixture c';CollectionType='homevideos';Paths=@($folder);RefreshLibrary=$true;LibraryOptions=@{EnableRealtimeMonitor=$false;TypeOptions=@(@{Type='Video';MetadataFetchers=@();ImageFetchers=@()})}} | Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(90)
        $registered=$false
        do {
            $newRoot=Call 'PersonalChannelsFixture/NativeRootProbe'
            if ($newRoot.RootKey -and -not $registered) {$createdLibraries.Add($newRoot.RootKey);$registered=$true}
            if (@($newRoot.VideoKeys).Count -eq 1) {break}
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        if (@($newRoot.VideoKeys).Count -ne 1) {throw 'New private root scan did not produce video'}
        foreach ($owner in @('a','b')) {
            $row=Probe "$owner Unassigned private root" "Users/$($state[$owner].UserId)/Items/$($newRoot.VideoKeys[0])" $state[$owner].Headers "PrivateNativeVideo_$owner" 'LibraryInitial_c'
            if ($row.Status -ne 404) {throw 'Unassigned private root is accessible before owner registration'}
            foreach ($path in @("Items/$($newRoot.VideoKeys[0])/PlaybackInfo","Videos/$($newRoot.VideoKeys[0])/stream.mp4?Static=true","Items/$($newRoot.VideoKeys[0])/Download")) {
                $denial=Probe "$owner Unassigned private media" $path $state[$owner].Headers "PrivateNativeVideo_$owner" 'LibraryInitial_c'
                if ($denial.Status -ne 404) {throw 'Unassigned private media endpoint did not deny access'}
            }
            $list=Probe "$owner Unassigned private search" 'Items?Recursive=true&SearchTerm=PrivateNativeVideo&SortBy=SortName' $state[$owner].Headers "PrivateNativeVideo_$owner" 'LibraryInitial_c'
            if ($list.Status -ne 200 -or $list.Other -or $list.Data.TotalRecordCount -ne 2) {throw 'Unassigned private video affects visible search'}
        }
        if ($ProbeDlna) {
            foreach ($owner in @('a','b')) {
                SoapProbe 'protected-new-root-unassigned' $owner 0 'BrowseDirectChildren' $state[$owner].Headers
                $row=$results[$results.Count-1]
                if (-not $row.SoapResponse -or $row.Total -ne $soapRootControls["${owner}:0"].Total -or $row.Data.Contains('Private Native Fixture c')) {throw 'Unassigned root changes DLNA listing'}
                SoapProbe 'protected-new-root-unassigned' $owner $newRoot.RootKey 'BrowseDirectChildren' $state[$owner].Headers
                $row=$results[$results.Count-1]
                if ($row.SoapResponse -or $row.Data.Contains('LibraryInitial_c')) {throw 'Unassigned root is accessible through DLNA'}
                SoapProbe 'protected-new-root-unassigned' $owner $newRoot.VideoKeys[0] 'BrowseMetadata' $state[$owner].Headers
                $hidden=$results[$results.Count-1]
                SoapProbe 'protected-new-root-unassigned' $owner 999999999 'BrowseMetadata' $state[$owner].Headers
                $missing=$results[$results.Count-1]
                if ($hidden.SoapResponse -or $hidden.Status -ne $missing.Status -or $hidden.Data -ne $missing.Data) {throw 'DLNA reveals unassigned private video existence'}
            }
        }
        if ($ProbeNativeSocket) {NativeSocketProbe 'Unassigned' $newRoot.VideoKeys[0] ''}
        $mapping[$newRoot.RootKey]=$state.a.UserId
        Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$mapping} | Out-Null
        $policy=(Call "Users/$($state.a.UserId)").Policy
        $policy.EnabledFolders=@($policy.EnabledFolders)+@($newRoot.RootGuid)
        Call "Users/$($state.a.UserId)/Policy" $admin Post $policy | Out-Null
        if ((Call "Users/$($state.a.UserId)").Policy.EnabledFolders -notcontains $newRoot.RootGuid) {throw 'New root policy readback failed'}
        $own=Probe 'a Assigned new private root' "Users/$($state.a.UserId)/Items/$($newRoot.VideoKeys[0])" $state.a.Headers 'LibraryInitial_c' 'PrivateNativeVideo_b'
        $cross=Probe 'b Assigned new private root' "Users/$($state.b.UserId)/Items/$($newRoot.VideoKeys[0])" $state.b.Headers 'PrivateNativeVideo_b' 'LibraryInitial_c'
        if ($own.Status -ne 200 -or -not $own.Own -or $cross.Status -ne 404) {throw 'New root assigned ownership control failed'}
        if ($ProbeDlna) {
            SoapProbe 'protected-new-root-assigned' 'a' $newRoot.VideoKeys[0] 'BrowseMetadata' $state.a.Headers
            $row=$results[$results.Count-1]
            if (-not $row.SoapResponse -or -not $row.Data.Contains('LibraryInitial_c') -or $row.ResourceResults.Count -ne 1 -or $row.ResourceResults[0].Status -ne 200 -or $row.ResourceResults[0].Bytes -lt 1000) {throw 'New root owner DLNA playback positive control failed'}
            $oldDlnaUris=@($script:lastDlnaResourceUris)
            SoapProbe 'protected-new-root-assigned' 'b' $newRoot.VideoKeys[0] 'BrowseMetadata' $state.b.Headers
            if ($results[$results.Count-1].SoapResponse) {throw 'Foreign user can access assigned root via DLNA'}
        }
        if ($ProbeNativeSocket) {NativeSocketProbe 'Assigned' $newRoot.VideoKeys[0] 'a'}
        $mapping[$newRoot.RootKey]=$state.b.UserId
        Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$mapping} | Out-Null
        $policy=(Call "Users/$($state.b.UserId)").Policy
        $policy.EnabledFolders=@($policy.EnabledFolders)+@($newRoot.RootGuid)
        Call "Users/$($state.b.UserId)/Policy" $admin Post $policy | Out-Null
        if ((Call "Users/$($state.b.UserId)").Policy.EnabledFolders -notcontains $newRoot.RootGuid) {throw 'Transferred root policy readback failed'}
        # Retain the former owner's folder permission to verify the independent ownership boundary.
        foreach ($phase in @('Transferred','Transferred after restart')) {
            if ($phase -eq 'Transferred after restart') {
                $before=Call 'PersonalChannelsFixture/Guard'
                & $control -Stop
                & $control
                $deadline=[DateTime]::UtcNow.AddSeconds(30)
                do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
                if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong transfer restart server'}
                $after=Call 'PersonalChannelsFixture/Guard'
                if (-not $after.Ready -or -not $after.Enabled -or $before.BootId -eq $after.BootId) {throw 'Transfer restart ownership state invalid'}
            }
            if ($ProbeNativeSocket) {NativeSocketProbe $phase $newRoot.VideoKeys[0] 'b'}
            $old=Probe "a $phase former owner" "Users/$($state.a.UserId)/Items/$($newRoot.VideoKeys[0])" $state.a.Headers 'PrivateNativeVideo_a' 'LibraryInitial_c'
            $new=Probe "b $phase new owner" "Users/$($state.b.UserId)/Items/$($newRoot.VideoKeys[0])" $state.b.Headers 'LibraryInitial_c' 'PrivateNativeVideo_a'
            $oldMedia=Probe "a $phase former owner stream" "Videos/$($newRoot.VideoKeys[0])/stream.mp4?Static=true" $state.a.Headers 'PrivateNativeVideo_a' 'LibraryInitial_c' $true
            $newMedia=Probe "b $phase new owner stream" "Videos/$($newRoot.VideoKeys[0])/stream.mp4?Static=true" $state.b.Headers 'LibraryInitial_c' 'PrivateNativeVideo_a' $true
            if ($old.Status -ne 404 -or $oldMedia.Status -ne 404 -or $new.Status -ne 200 -or -not $new.Own -or $newMedia.Status -ne 200 -or $newMedia.Bytes -lt 1000) {throw 'Transferred ownership positive/negative control failed'}
            if ($ProbeDlna) {
                foreach ($oldUri in $oldDlnaUris) {
                    $status=200
                    try {Invoke-WebRequest -Uri $oldUri.AbsoluteUri -UseBasicParsing -TimeoutSec 20 | Out-Null}
                    catch {if (-not $_.Exception.Response) {throw 'Cached former-owner DLNA URL request failed without response'};$status=[int]$_.Exception.Response.StatusCode}
                    $results.Add(@{Label="DLNA $phase cached former-owner URL";Status=$status;Own=$false;Other=($status -eq 200);Baseline=$false})
                    if ($status -ne 404) {throw 'Cached DLNA media URL survives ownership transfer'}
                }
                SoapProbe 'protected-new-root-transferred' 'a' $newRoot.VideoKeys[0] 'BrowseMetadata' $state.a.Headers
                if ($results[$results.Count-1].SoapResponse) {throw 'Former owner retains DLNA access'}
                SoapProbe 'protected-new-root-transferred' 'b' $newRoot.VideoKeys[0] 'BrowseMetadata' $state.b.Headers
                $row=$results[$results.Count-1]
                if (-not $row.SoapResponse -or -not $row.Data.Contains('LibraryInitial_c') -or $row.ResourceResults.Count -ne 1 -or $row.ResourceResults[0].Status -ne 200 -or $row.ResourceResults[0].Bytes -lt 1000) {throw 'Transferred owner DLNA positive control failed'}
            }
        }
    }
    if ($ProbeNewRoot) {
        $file=Join-Path $folder 'LibraryScanAddition_c_2.mp4'
        Copy-Item -LiteralPath $sample -Destination $file
        $createdFiles.Add($file)
        $tasks=Call 'ScheduledTasks'
        $scan=@($tasks | Where-Object {$_.Key -eq 'RefreshLibrary' -or $_.Name -eq 'Scan media library'})
        if ($scan.Count -ne 1) {throw 'Unique library scan task missing'}
        $scanStart=[DateTime]::UtcNow
        if ($ProbeNativeSocket) {NaturalSocketScan $scan[0].Id}
        else {Call "ScheduledTasks/Running/$($scan[0].Id)" $admin Post | Out-Null}
        $deadline=[DateTime]::UtcNow.AddSeconds(90)
        do {
            Start-Sleep -Milliseconds 200
            $observed=Call 'PersonalChannelsFixture/NativeRootProbe'
            $newKeys=@($observed.VideoKeys | Where-Object {$_ -notin $newRoot.VideoKeys})
        } while ($newKeys.Count -ne 1 -and [DateTime]::UtcNow -lt $deadline)
        if ($newKeys.Count -ne 1) {throw 'Incremental scan did not produce the additional video'}
        $own=Probe 'b Incrementally scanned own video' "Users/$($state.b.UserId)/Items/$($newKeys[0])" $state.b.Headers 'LibraryScanAddition_c_2' 'PrivateNativeVideo_a'
        $cross=Probe 'a Incrementally scanned foreign video' "Users/$($state.a.UserId)/Items/$($newKeys[0])" $state.a.Headers 'PrivateNativeVideo_a' 'LibraryScanAddition_c_2'
        if ($ProbeNativeSocket) {NativeSocketProbe 'Incremental' $newKeys[0] 'b'}
        if ($cross.Status -ne 404) {throw 'Incrementally scanned private video leaks'}
        if ($own.Status -ne 200 -or -not $own.Own) {throw 'Incrementally scanned video is inaccessible to its owner'}
        $scanState=Call "ScheduledTasks/$($scan[0].Id)"
        do {if ($scanState.State -eq 'Running') {Start-Sleep -Milliseconds 200;$scanState=Call "ScheduledTasks/$($scan[0].Id)"}} while ($scanState.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
        if ($scanState.State -eq 'Running' -or [DateTime]$scanState.LastExecutionResult.StartTimeUtc -lt $scanStart.AddSeconds(-2)) {throw 'Incremental scan completion not verified'}
        $ownMedia=Probe 'b Incrementally scanned own stream' "Videos/$($newKeys[0])/stream.mp4?Static=true" $state.b.Headers 'LibraryScanAddition_c_2' 'PrivateNativeVideo_a' $true
        if ($ownMedia.Status -ne 200 -or $ownMedia.Bytes -lt 1000) {throw 'Incremental owner playback failed'}
        $crossMedia=Probe 'a Incrementally scanned foreign stream' "Videos/$($newKeys[0])/stream.mp4?Static=true" $state.a.Headers 'PrivateNativeVideo_a' 'LibraryScanAddition_c_2' $true
        if ($crossMedia.Status -ne 404) {throw 'Incremental foreign playback leaks'}
        foreach ($owner in @('a','b')) {
            $expected=if ($owner -eq 'a') {2} else {4}
            $list=Probe "$owner Incremental video search" 'Items?Recursive=true&IncludeItemTypes=Video&SearchTerm=&SortBy=SortName' $state[$owner].Headers "PrivateNativeVideo_$owner" $(if ($owner -eq 'a') {'LibraryScanAddition_c_2'} else {'PrivateNativeVideo_a'})
            if ($list.Status -ne 200 -or $list.Other -or $list.Data.TotalRecordCount -ne $expected -or $list.Data.Items.Count -ne $expected) {throw 'Incremental search visibility/count failed'}
        }
        if ($ProbeDlna) {
            SoapProbe 'protected-incremental' 'a' $newKeys[0] 'BrowseMetadata' $state.a.Headers
            if ($results[$results.Count-1].SoapResponse) {throw 'Incremental foreign DLNA metadata leaks'}
            SoapProbe 'protected-incremental' 'b' $newKeys[0] 'BrowseMetadata' $state.b.Headers
            $row=$results[$results.Count-1]
            if (-not $row.SoapResponse -or -not $row.Data.Contains('LibraryScanAddition_c_2') -or $row.ResourceResults.Count -ne 1 -or $row.ResourceResults[0].Status -ne 200 -or $row.ResourceResults[0].Bytes -lt 1000) {throw 'Incremental owner DLNA playback fails'}
        }
    }
    if ($ProbeNativeSocket -and $ProbeNewRoot) {
        NaturalSocketScan $scan[0].Id 'Removed' $newKeys[0] $file
        foreach ($owner in @('a','b')) {
            $row=Probe "$owner Deleted private video lookup" "Users/$($state[$owner].UserId)/Items/$($newKeys[0])" $state[$owner].Headers "PrivateNativeVideo_$owner" 'LibraryScanAddition_c_2'
            if ($row.Status -ne 404) {throw 'Deleted private video lookup is not missing'}
        }
    }
    if ($ProbeDeletedSync) {
        if (-not $RequireProtected -or -not $ProbeNewRoot -or -not $ProbeSync -or $ProbeNativeSocket) {throw 'Deleted Sync test requires protected/new-root/sync and separate socket deletion disabled'}
        $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Native libraries test", Device="Isolated test", DeviceId="native-b", Version="1.0"'} Post @{Username='native-privacy-fixture-b';Pw=''}
        if ($session.User.Id -ne $state.b.UserId -or $session.User.Policy.IsAdministrator) {throw 'Deleted Sync owner authentication mismatch'}
        $state.b.Headers=@{'X-Emby-Token'=$session.AccessToken};$state.b.SessionId=$session.SessionInfo.Id
        Call 'Sessions/Capabilities/Full' $state.b.Headers Post @{Id=$state.b.SessionId;SupportsSync=$true;PlayableMediaTypes=@('Video');SupportedCommands=@()} | Out-Null
        $jobMarker=if ($ProbeMultiSourceSync) {'Private Native Fixture c'} else {'LibraryScanAddition_c_2'}
        $jobSources=if ($ProbeMultiSourceSync) {@([string]$newKeys[0],[string]$newRoot.VideoKeys[0])} else {@([string]$newKeys[0])}
        $requestedSources=if ($ProbeMultiSourceSync) {@([string]$newRoot.RootKey)} else {$jobSources}
        $results.Add(@{Label='Deleted source Sync requested sources';RequestItemKeys=$requestedSources;MultiSourceRequested=[bool]$ProbeMultiSourceSync;SourceKeys=$jobSources;RequestedName=$jobMarker;Baseline=$false})
        if ($ProbeMultiSourceSync) {
            $sourceControl=Probe 'Multi-source source lookup' ("Items?Ids="+($jobSources -join ',')) $state.b.Headers 'LibraryInitial_c_1' 'PrivateNativeVideo_a'
            if ($sourceControl.Status -ne 200 -or $sourceControl.Data.Items.Count -ne 2) {throw 'Multi-source source lookup positive control failed'}
        }

        $jobOverviewBefore=@{}
        if ($ProbeMultiSourceSync) {
            foreach ($owner in @('a','b')) {
                $overview=Call 'Sync/Jobs' $state[$owner].Headers
                $jobOverviewBefore[$owner]=@{Total=$overview.TotalRecordCount;Ids=@($overview.Items | ForEach-Object {[string]$_.Id})}
            }
        }
        $created=Probe 'Deleted source Sync owner create' 'Sync/Jobs' $state.b.Headers $jobMarker 'PrivateNativeVideo_a' $false Post @{TargetId='native-b';ItemIds=$requestedSources;UserId=$state.b.UserId;Name=$jobMarker;Quality='Original';Profile='Original'}
        $deletedJobId=if ($created.Data.Job.Id) {[string]$created.Data.Job.Id} else {[string]$created.Data.Id}
        if ($created.Status -ne 200 -or -not $deletedJobId) {throw 'Deleted source Sync create positive control failed'}

        $createdSyncJobs.Add($deletedJobId)
        if ($ProbeMultiSourceSync -and $created.Data.Job.ItemCount -ne 2) {throw 'Folder Sync job did not contain both source videos'}
        $native=Call "PersonalChannelsFixture/NativeSyncJobProbe?JobKey=$deletedJobId"
        if (-not $native.Exists -or -not $native.SyntheticNameVerified) {throw 'Native deletion job positive control failed'}
        $own=Probe 'Deleted source Sync before deletion owner' "Sync/Jobs/$deletedJobId" $state.b.Headers $jobMarker 'PrivateNativeVideo_a'
        $cross=Probe 'Deleted source Sync before deletion foreign' "Sync/Jobs/$deletedJobId" $state.a.Headers 'PrivateNativeVideo_a' $jobMarker
        if ($own.Status -ne 200 -or -not $own.Own -or $cross.Status -ne 404) {throw 'Deleted source Sync initial control failed'}
        $jobItems=Probe 'Deleted source Sync before deletion job items' "Sync/JobItems?JobId=$deletedJobId" $state.b.Headers 'Library' 'PrivateNativeVideo_a'
        if ($jobItems.Status -ne 200 -or $jobItems.Data.Items.Count -ne $jobSources.Count) {throw 'Deleted source Sync source count positive control failed'}
        $deletedJobItemId=@($jobItems.Data.Items | Where-Object {[string]$_.ItemId -eq [string]$newKeys[0]})[0].Id
        if (-not $deletedJobItemId) {throw 'Deleted source Sync job item identity missing'}
        $target=[IO.Path]::GetFullPath($file)
        $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin/native-c'))+[IO.Path]::DirectorySeparatorChar
        if (-not $target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target) -ne 'LibraryScanAddition_c_2.mp4') {throw 'Unsafe deleted Sync source path'}
        Remove-Item -LiteralPath $target
        Call "ScheduledTasks/Running/$($scan[0].Id)" $admin Post | Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do {Start-Sleep -Milliseconds 200;$observed=Call 'PersonalChannelsFixture/NativeRootProbe'} while ($newKeys[0] -in $observed.VideoKeys -and [DateTime]::UtcNow -lt $deadline)
        if ($newKeys[0] -in $observed.VideoKeys) {throw 'Deleted Sync source remains in library'}
        $own=Probe 'Deleted source Sync after deletion owner' "Sync/Jobs/$deletedJobId" $state.b.Headers $jobMarker 'PrivateNativeVideo_a'
        $cross=Probe 'Deleted source Sync after deletion foreign' "Sync/Jobs/$deletedJobId" $state.a.Headers 'PrivateNativeVideo_a' $jobMarker
        if ($own.Status -notin @(200,404) -or ($own.Status -eq 200 -and -not $own.Own) -or $cross.Status -ne 404) {throw 'Deleted source Sync immediate ownership control failed'}
        $retained=$own.Status -eq 200
        if ($ProbeMultiSourceSync) {
            if (-not $retained) {throw 'Multi-source Sync job removed despite surviving private source'}
            foreach ($owner in @('a','b')) {
                $expected=[int]$jobOverviewBefore[$owner].Total+$(if ($owner -eq 'b') {1} else {0})
                foreach ($path in @('Sync/Jobs',"Sync/Jobs?UserId=$($state[$owner].UserId)")) {
                    $overview=Probe "Multi-source after deletion $owner overview" $path $state[$owner].Headers $(if ($owner -eq 'b') {$jobMarker} else {'PrivateNativeVideo_a'}) $(if ($owner -eq 'a') {$jobMarker} else {'PrivateNativeVideo_a'})
                    $listed=@($overview.Data.Items | ForEach-Object {[string]$_.Id}) -contains $deletedJobId
                    if ($overview.Status -ne 200 -or $overview.Data.TotalRecordCount -ne $expected -or $listed -ne ($owner -eq 'b') -or $overview.Other) {throw 'Multi-source job overview visibility/count fails'}
                }
            }
            $items=Probe 'Multi-source after deletion owner items' "Sync/JobItems?JobId=$deletedJobId" $state.b.Headers 'LibraryInitial_c_1' 'PrivateNativeVideo_a'
            $foreign=Probe 'Multi-source after deletion foreign items' "Sync/JobItems?JobId=$deletedJobId" $state.a.Headers 'PrivateNativeVideo_a' $jobMarker
            if ($items.Status -ne 200 -or $items.Data.Items.Count -ne 1 -or [string]$items.Data.Items[0].ItemId -ne [string]$newRoot.VideoKeys[0] -or $foreign.Status -ne 404) {throw 'Multi-source remaining items control failed'}
        }
        $native=Call "PersonalChannelsFixture/NativeSyncJobProbe?JobKey=$deletedJobId"
        $results.Add(@{Label='Deleted source Sync raw state after deletion';ExistsInNativeManager=$native.Exists;Baseline=$false})
        if ($native.Exists -ne $retained) {throw 'Guarded job visibility does not match native deletion state'}
        $before=Call 'PersonalChannelsFixture/Guard'
        & $control -Stop
        & $control
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
        if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong deleted Sync restart server'}
        $after=Call 'PersonalChannelsFixture/Guard'
        if (-not $after.Enabled -or -not $after.Ready -or $after.BootId -eq $before.BootId) {throw 'Deleted Sync restart not verified'}
        $own=Probe 'Deleted source Sync after restart owner' "Sync/Jobs/$deletedJobId" $state.b.Headers $jobMarker 'PrivateNativeVideo_a'
        $cross=Probe 'Deleted source Sync after restart foreign' "Sync/Jobs/$deletedJobId" $state.a.Headers 'PrivateNativeVideo_a' $jobMarker
        $native=Call "PersonalChannelsFixture/NativeSyncJobProbe?JobKey=$deletedJobId"
        if ($native.Exists -ne $retained) {throw 'Native job retention changed unexpectedly after restart'}
        if ($ProbeMultiSourceSync) {
            foreach ($owner in @('a','b')) {
                $expected=[int]$jobOverviewBefore[$owner].Total+$(if ($owner -eq 'b') {1} else {0})
                foreach ($path in @('Sync/Jobs',"Sync/Jobs?UserId=$($state[$owner].UserId)")) {
                    $overview=Probe "Multi-source after restart $owner overview" $path $state[$owner].Headers $(if ($owner -eq 'b') {$jobMarker} else {'PrivateNativeVideo_a'}) $(if ($owner -eq 'a') {$jobMarker} else {'PrivateNativeVideo_a'})
                    $listed=@($overview.Data.Items | ForEach-Object {[string]$_.Id}) -contains $deletedJobId
                    if ($overview.Status -ne 200 -or $overview.Data.TotalRecordCount -ne $expected -or $listed -ne ($owner -eq 'b') -or $overview.Other) {throw 'Multi-source job overview visibility/count fails'}
                }
            }
            $items=Probe 'Multi-source after restart owner items' "Sync/JobItems?JobId=$deletedJobId" $state.b.Headers 'LibraryInitial_c_1' 'PrivateNativeVideo_a'
            $foreign=Probe 'Multi-source after restart foreign items' "Sync/JobItems?JobId=$deletedJobId" $state.a.Headers 'PrivateNativeVideo_a' $jobMarker
            if ($items.Status -ne 200 -or $items.Data.Items.Count -ne 1 -or [string]$items.Data.Items[0].ItemId -ne [string]$newRoot.VideoKeys[0] -or $foreign.Status -ne 404) {throw 'Multi-source remaining items restart control failed'}
            foreach ($owner in @('a','b')) {
                $missing=Probe "$owner Deleted Sync job item file after restart" "Sync/JobItems/$deletedJobItemId/File" $state[$owner].Headers "PrivateNativeVideo_$owner" 'LibraryScanAddition_c_2'
                if ($missing.Status -ne 404) {throw 'Removed job item is accessible after restart'}
            }
        }
        $results.Add(@{Label='Deleted source Sync raw state after restart';ExistsInNativeManager=$native.Exists;Baseline=$false})
        $results.Add(@{Label='Deleted source Sync retention';RetainedAfterDeletion=$retained;OwnerStatusAfterRestart=$own.Status;ForeignStatusAfterRestart=$cross.Status;Baseline=$false})
        if (($retained -and ($own.Status -ne 200 -or -not $own.Own)) -or (-not $retained -and $own.Status -ne 404) -or $cross.Status -ne 404) {throw 'Deleted source Sync privacy after restart failed'}
    }
    if ($ProbeMixedSync) {MixedSyncCreation}
    if ($ProbeReadParity) {ReadParity}
    if ($ProbeSyncTargets) {SyncTargetIsolation}
    if ($ProbeSharedSync) {SharedSyncIsolation}
    $leaks=@($results | Where-Object {-not $_.Baseline -and ($_.Other -or ($_.Anonymous -and $_.Own) -or ($_.IssuedCredentialSubjects -and @($_.IssuedCredentialSubjects | Where-Object {-not $_.MatchesCaller -or $_.PrivilegeEndpointStatus -eq 200}).Count) -or ($_.Label -match 'Cross (stream|download)' -and $_.Status -eq 200))})
    Write-Output "Native library observations: $($results.Count); leaking responses: $($leaks.Count)"
    if ($RequireProtected -and $leaks.Count) {throw 'Native library isolation failed'}
    if ($ProbeDlna -and -not @($results | Where-Object {$_.Baseline -and $_.SoapResponse -and $_.Own -and $_.Status -eq 200}).Count) {throw 'DLNA had no positive baseline; these SOAP denials do not prove privacy'}
}
catch {Write-Output ('Native test failure: '+$_.Exception.Message);throw}
finally {
    $report=if ($RequireProtected) {'native-library-protected'} else {'native-library'}
    if ($ProbeDlna) {$report+='-dlna'}
    if ($ProbeSync) {$report+='-sync'}
    if ($ProbeNewRoot) {$report+='-new-root'}
    if ($ProbeNativeSocket) {$report+='-socket'}
    if ($ProbeDeletedSync) {$report+='-deleted-sync'}
    if ($ProbeMultiSourceSync) {$report+='-multi-source'}
    if ($ProbeMixedSync) {$report+='-mixed-create'}
    if ($ProbeReadParity) {$report+='-read-parity'}
    if ($ProbeSyncTargets) {$report+='-targets'}
    if ($ProbeDevicePolicy) {$report+='-device-policy'}
    if ($ProbeTargetVariants) {$report+='-variants'}
    if ($ProbeSharedSync) {$report+='-shared'}
    if ($ProbeSharedReferences) {$report+='-references'}
    if ($ProbeConcurrentSync) {$report+='-concurrent'}
    if ($ProbeBroadSync) {$report+='-broad'}
    if ($ProbeVisibility) {$report+='-visibility'}
    if ($ProbeConfiguration) {$report+='-configuration'}
    if ($ProbeRealSyncFiles) {$report+='-real-files'}
    if ($ProbeStrictUserPolicy) {$report+='-strict-policy'}
    $results | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/$report-results.json") -Encoding UTF8
    $subjects | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/$report-setup.json") -Encoding UTF8
    if ($started) {
        try {
            if ($originalDlna) {
                Call 'System/Configuration/dlna' $admin Post $originalDlna | Out-Null
                if (((Call 'System/Configuration/dlna') | ConvertTo-Json -Depth 10 -Compress) -ne ($originalDlna | ConvertTo-Json -Depth 10 -Compress)) {throw 'DLNA restoration readback failed'}
            }
            if ($fixtureInstalled) {
                # Remove only the isolated fixture, then restart without its test boundary
                # so the administrative cleanup can delete both owners' synthetic roots.
                & $control -Stop
                foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json.guard.json')) {
                    $target=[IO.Path]::GetFullPath((Join-Path $root $relative))
                    if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe fixture cleanup path'}
                    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
                }
                $fixtureInstalled=$false
                & $control
                $deadline=[DateTime]::UtcNow.AddSeconds(30)
                do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
                if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong cleanup server'}
            }
            $existingJobIds=@((Call 'Sync/Jobs').Items | ForEach-Object {[string]$_.Id})
            foreach ($id in $createdSyncJobs) {if ($id -in $existingJobIds) {Call "Sync/Jobs/$id" $admin Delete | Out-Null}}
            if ($createdSyncJobs.Count) {
                $remainingJobs=Call 'Sync/Jobs'
                if (@($remainingJobs.Items | Where-Object {$_.Id -in $createdSyncJobs}).Count) {throw 'Sync job cleanup readback failed'}
            }
            foreach ($id in $createdUsers) {Call "Users/$id" $admin Delete | Out-Null}
            foreach ($id in $createdLibraries) {Call 'Library/VirtualFolders/Delete' $admin Post @{Id=$id} | Out-Null}
            $remainingUsers=(Call 'Users/Query').Items
            $remainingLibraries=(Call 'Library/VirtualFolders/Query').Items
            if (@($remainingUsers | Where-Object {$_.Id -in $createdUsers}).Count -or @($remainingLibraries | Where-Object {$_.ItemId -in $createdLibraries}).Count) {throw 'Native test cleanup readback failed'}
        } finally {& $control -Stop}
    }
    foreach ($file in $createdFiles) {
        $target=[IO.Path]::GetFullPath($file)
        if (-not $target.StartsWith([IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin'))+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe cleanup path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
