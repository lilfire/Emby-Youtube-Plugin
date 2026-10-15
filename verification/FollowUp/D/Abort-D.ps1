# A real native writer under TCP receive backpressure. No timing hook or
# fabricated stream adapter. Extend only the disposable synthetic A MP4.
$file=[IO.File]::Open($subjects.a.SourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$file.SetLength(64MB)}finally{$file.Dispose()}
$subjects.a.SourceHash=(Get-FileHash -LiteralPath $subjects.a.SourcePath).Hash
$socket=[Net.Sockets.TcpClient]::new();$socket.ReceiveBufferSize=4096
$deleteMessage=$null;$deletionPending=$null
try{
    $socket.Connect('127.0.0.1',18096)
    $stream=$socket.GetStream();$stream.ReadTimeout=5000;$stream.WriteTimeout=5000
    $request="GET /emby/$(StreamPath 'a') HTTP/1.1`r`nHost: 127.0.0.1:18096`r`nX-Emby-Token: $($subjects.a.Headers['X-Emby-Token'])`r`nConnection: close`r`n`r`n"
    $wire=[Text.Encoding]::ASCII.GetBytes($request);$stream.Write($wire,0,$wire.Length)
    $header=[Collections.Generic.List[byte]]::new()
    do{
        $value=$stream.ReadByte();if($value -lt 0){throw 'Large native transfer closed before headers'}
        $header.Add([byte]$value)
        if($header.Count -gt 16384){throw 'Unexpected native HTTP header size'}
        $n=$header.Count
    }while($n -lt 4 -or $header[$n-4] -ne 13 -or $header[$n-3] -ne 10 -or $header[$n-2] -ne 13 -or $header[$n-1] -ne 10)
    $text=[Text.Encoding]::ASCII.GetString($header.ToArray())
    $status200=$text -match '^HTTP/1\.[01] 200 '
    $size64=$text -match '(?im)^Content-Length: 67108864\s*$'
    # Consume and verify the first actual bytes, then stop reading.
    $prefix=[byte[]]::new(128);$read=0
    while($read -lt 128){$n=$stream.Read($prefix,$read,128-$read);if($n -eq 0){throw 'Missing authorized video prefix'};$read+=$n}
    $original=[IO.File]::ReadAllBytes($subjects.a.SourcePath)
    $prefixMatches=(Hash $prefix) -eq (Hash ([byte[]]$original[0..127]))
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if($lease.Held){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
    $rows.Add(@{Label='D real large TCP transfer established';Status200=$status200;Declared64MiB=$size64;PrefixHashPass=$prefixMatches;OwnerLeaseHeld=$lease.Held;ApplicationBytesConsumed=$read})
    if(-not $status200 -or -not $size64 -or -not $prefixMatches -or -not $lease.Held){throw 'Real backpressure owner control unavailable'}
    $deleteMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/YouTubePlugin/MyProfile/Delete")
    foreach($key in $subjects.a.Headers.Keys){$deleteMessage.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
    $deleteMessage.Content=[Net.Http.StringContent]::new((@{ExpectedRevision=$subjects.a.Profile.Revision}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
    $deletionPending=$client.SendAsync($deleteMessage)
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if($lease.Waiting -ge 1){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
    $rows.Add(@{Label='D deletion waits behind real unread video';Held=$lease.Held;Waiting=$lease.Waiting;DeletePending=(-not $deletionPending.IsCompleted)})
    if(-not $lease.Held -or $lease.Waiting -lt 1 -or $deletionPending.IsCompleted){throw 'Real transfer deletion did not wait'}
    OwnStreams 'D real unread transfer independent B' 'b'
    $saved=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=$subjects.b.Profile.Revision;Channels=@('UC'+('a'*22))}
    $rows.Add(@{Label='D B profile saves during real video backpressure';RevisionAdvanced=$saved.Revision -gt $subjects.b.Profile.Revision})
    $subjects.b.Profile=$saved
    $aborted=[DateTime]::UtcNow
    $socket.Dispose()
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($subjects.a.UserId)";if(-not $lease.Held -and $lease.Waiting -eq 0){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
    $released=-not $lease.Held -and $lease.Waiting -eq 0
    $rows.Add(@{Label='D real client abort releases video lease';Released=$released;ObservedMilliseconds=[int]([DateTime]::UtcNow-$aborted).TotalMilliseconds;DeleteCompleted=$deletionPending.IsCompleted})
    if(-not $released){throw 'Native client abort did not release owner lease within observation window'}
    $response=$deletionPending.GetAwaiter().GetResult()
    try{
        $deleted=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
        $readback=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers
        $rows.Add(@{Label='D queued deletion persisted after real client abort';Status=[int]$response.StatusCode;Deleted=$deleted.State -eq 'Deleted' -and $readback.State -eq 'Deleted'})
        if([int]$response.StatusCode -ne 200 -or $readback.State -ne 'Deleted'){throw 'Real aborted transfer deletion readback failed'}
    }finally{$response.Dispose()}
    DResult 'D deleted A new static request after real abort' (StreamPath 'a') $subjects.a.Headers|Out-Null
    OwnStreams 'D real abort independent B after deletion' 'b'
}finally{$socket.Dispose();if($deleteMessage){$deleteMessage.Dispose()}}
