$timing='PersonalChannelsFixture/NativeReferenceWriteGate'
Call $timing $admin Post @{OwnerUserId=$subjects.a.UserId;Video=$true;AfterCheck=($Mode -eq 'Lease')}|Out-Null
$message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,"$base/$(StreamPath 'a')")
foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
$message.Headers.TryAddWithoutValidation('X-Isolated-Reference-Gate','before-write')|Out-Null
$pending=$client.SendAsync($message)
$deleteMessage=$null;$deletionPending=$null
try{
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    do{$pause=Call $timing;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
    if(-not $pause.Active -or $pending.IsCompleted -or $pause.TimedOut){throw 'Actual video writer pause unavailable'}
    $rows.Add(@{Label='D actual video writer paused';AfterCheck=$pause.AfterCheck;HttpPending=$true;ResultContract=$pause.ResultContract})
    if($Mode -eq 'Lease'){
        $sourcePath=$subjects.a.SourcePath;$sourceBytes=[IO.File]::ReadAllBytes($sourcePath);$sourceTime=[IO.File]::GetLastWriteTimeUtc($sourcePath)
        try{
            [IO.File]::WriteAllBytes($sourcePath,[IO.File]::ReadAllBytes($subjects.b.SourcePath))
            $rows.Add(@{Label='D original file overwrite after writer authorization';WriteSucceeded=$true})
        }catch [IO.IOException]{
            $rows.Add(@{Label='D original file overwrite after writer authorization';WriteSucceeded=$false;WindowsSharingLock=$true})
        }finally{
            if((Get-FileHash -LiteralPath $sourcePath).Hash -ne (Hash $sourceBytes)){[IO.File]::WriteAllBytes($sourcePath,$sourceBytes)}
            if([IO.File]::GetLastWriteTimeUtc($sourcePath) -ne $sourceTime){[IO.File]::SetLastWriteTimeUtc($sourcePath,$sourceTime)}
        }
        $deleteMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/YouTubePlugin/MyProfile/Delete")
        foreach($key in $subjects.a.Headers.Keys){$deleteMessage.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
        $deleteMessage.Content=[Net.Http.StringContent]::new((@{ExpectedRevision=$subjects.a.Profile.Revision}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
        $deletionPending=$client.SendAsync($deleteMessage)
        $deadline=[DateTime]::UtcNow.AddSeconds(5)
        do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if($lease.Waiting -ge 1){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
        $pass=$lease.Held -and $lease.Waiting -ge 1 -and -not $deletionPending.IsCompleted -and -not $pending.IsCompleted
        $rows.Add(@{Label='D deletion waiting on actual video owner lease';Held=$lease.Held;Waiting=$lease.Waiting;IsolationPass=$pass})
        if(-not $pass){throw 'Deletion failed to wait on video lease'}
        $saved=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=$subjects.b.Profile.Revision;Channels=@('UC'+('a'*22))}
        $rows.Add(@{Label='D independent B mutation while A waits';RevisionAdvanced=$saved.Revision -gt $subjects.b.Profile.Revision})
        $subjects.b.Profile=$saved
    }else{
        $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
        if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'Deletion readback failed'}
        $rows.Add(@{Label='D deletion persisted before writer check';Deleted=$true;HttpPending=(-not $pending.IsCompleted)})
    }
    OwnStreams 'D independent B during A writer pause' 'b'
}finally{Call $timing $admin Post @{Release=$true}|Out-Null}
try{
    $response=$pending.GetAwaiter().GetResult()
    try{
        $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $names=@($response.Headers|ForEach-Object {$_.Key})+@($response.Content.Headers|ForEach-Object {$_.Key})
        $entity=@($names|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
        $matches=(Hash $bytes) -eq $subjects.a.SourceHash
        $pass=if($Mode -eq 'Lease'){[int]$response.StatusCode -eq 200 -and $matches}else{[int]$response.StatusCode -eq 404 -and $entity.Count -eq 0 -and [Text.Encoding]::UTF8.GetString($bytes) -eq 'Items not found.'}
        $rows.Add(@{Label='D paused actual video response';Status=[int]$response.StatusCode;Bytes=$bytes.Length;MatchesA=$matches;EntityHeaderCount=$entity.Count;IsolationPass=$pass})
        if(-not $pass){throw 'Unexpected authorized/revoked video response'}
    }finally{$response.Dispose()}
    if($deletionPending){
        $response=$deletionPending.GetAwaiter().GetResult()
        try{
            $deleted=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
            $lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)"
            $pass=[int]$response.StatusCode -eq 200 -and $deleted.State -eq 'Deleted' -and (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -eq 'Deleted' -and -not $lease.Held -and $lease.Waiting -eq 0
            $rows.Add(@{Label='D queued deletion saved after video finished';IsolationPass=$pass;Held=$lease.Held;Waiting=$lease.Waiting})
            if(-not $pass){throw 'Queued deletion readback failed'}
        }finally{$response.Dispose()}
    }
    DDenied 'D profile deletion after writer'
}finally{$message.Dispose();if($deleteMessage){$deleteMessage.Dispose()}}
