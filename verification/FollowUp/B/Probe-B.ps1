# Runs in the production fixture scope. Raw bodies and credentials stay in memory.
function BHash($bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function BObserve($phase,$actor,$owner,$operation,$r,$expectedAllowed,$hash=''){
    $marker=$r.Text.Contains("PrivateNativeVideo_${owner}_client")
    $matches=$hash -and (BHash $r.Bytes) -eq $hash
    $pass=if($expectedAllowed){$r.Status -in @(200,204) -and $(if($hash){$matches}else{$marker})}else{$r.Status -in @(401,403,404) -and -not $marker -and -not $matches}
    $rows.Add(@{Label="$phase $actor $operation source $owner";Kind='B';Phase=$phase;Actor=$actor;Owner=$owner;Operation=$operation;Status=$r.Status;
      ExpectedAllowed=[bool]$expectedAllowed;PrivateMarker=$marker;PayloadBytes=$r.Bytes.Length;MatchesOutput=[bool]$matches;IsolationPass=[bool]$pass;
      EntityHeaders=@($r.HeaderNames|Where-Object{$_ -in @('ETag','Content-Disposition','Content-Range','Last-Modified')})})
    return $pass
}
function BSetup{
    $script:BJobs=@();$script:BStreams=@{};$script:BOutputs=@()
    $surface=Call 'PersonalChannelsFixture/Surface'
    $surface|ConvertTo-Json -Depth 18|Set-Content (Join-Path $env:PERSONAL_YOUTUBE_B_OUTPUT 'surface.json') -Encoding UTF8
    $audit=Call 'PersonalChannelsFixture/ApiAudit'
    $audit|ConvertTo-Json -Depth 18|Set-Content (Join-Path $env:PERSONAL_YOUTUBE_B_OUTPUT 'api-audit.json') -Encoding UTF8
    $journalPath=Join-Path $PSScriptRoot '../../PersonalChannels/bin/native-client-state.json'
    $journal=Get-Content $journalPath -Raw|ConvertFrom-Json
    $journal|Add-Member NoteProperty SyncJobs @() -Force
    foreach($owner in @('a','b')){
        $u=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"B Sync investigation`", Device=`"Isolated`", DeviceId=`"followup-b-$owner`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong B identity'}
        $subjects[$owner].Headers=@{'X-Emby-Token'=$login.AccessToken}
        Call 'Sessions/Capabilities/Full' $subjects[$owner].Headers Post @{Id=$login.SessionInfo.Id;SupportsSync=$true;PlayableMediaTypes=@('Video');DeviceProfile=@{Name='B MPEG4';DirectPlayProfiles=@();TranscodingProfiles=@(@{Container='mp4';Type='Video';VideoCodec='mpeg4';AudioCodec='aac';Context='Static';Protocol='http'})}}|Out-Null
        foreach($quality in @('Original','Custom')){
            $created=Request 'Sync/Jobs' $subjects[$owner].Headers Post @{TargetId="followup-b-$owner";ItemIds=@($subjects[$owner].References[1]);UserId=$u.UserId;Quality=$quality;Profile='General';Bitrate=100000;Container='mp4';VideoCodec='mpeg4';AudioCodec='aac'}
            $rows.Add(@{Label="Active $owner create $quality own Sync";Status=$created.Status;Kind='BCreation'})
            if($created.Status -ne 200){continue}
            $result=$created.Text|ConvertFrom-Json;$job=if($result.Job){$result.Job}else{$result}
            if(-not $job.Id -or $job.Name -ne "PrivateNativeVideo_${owner}_client"){throw 'Unexpected native job'}
            $journal.SyncJobs+=@(@{JobId=[string]$job.Id;Name=$job.Name})
            $journal|ConvertTo-Json -Depth 12|Set-Content $journalPath -Encoding UTF8
            $script:BJobs+=@(@{Owner=$owner;Quality=$quality;Id=[string]$job.Id})
        }
        $play=Call "Items/$($subjects[$owner].References[1])/PlaybackInfo" $subjects[$owner].Headers Post @{UserId=$u.UserId;IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $source=@(Call "PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($subjects[$owner].References[1])")[0]
        $body=@{ItemId=[long]$subjects[$owner].References[1];UserId=$u.UserId;OpenToken=$source.OpenToken;PlaySessionId=$play.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $opened=Request 'LiveStreams/Open' $subjects[$owner].Headers Post $body
        $ok=BObserve Active $owner $owner 'Open own live stream' $opened $true
        if(-not $ok){throw 'Own live Open positive missing'}
        $live=($opened.Text|ConvertFrom-Json).MediaSource
        $script:BStreams[$owner]=@{LiveId=$live.LiveStreamId;Session=$play.PlaySessionId;Body=$body;SourceId=$live.Id}
    }
    if($script:BJobs.Count){
        $task=@((Call 'ScheduledTasks')|Where-Object Key -eq 'SyncPrepare')[0]
        Call "ScheduledTasks/Running/$($task.Id)" $admin Post|Out-Null
        foreach($job in $script:BJobs){
            $deadline=[DateTime]::UtcNow.AddSeconds(45)
            do{
                $items=Call "Sync/JobItems?JobId=$($job.Id)" $subjects[$job.Owner].Headers
                $item=@($items.Items)[0]
                if($item.Status -in @('ReadyToTransfer','Failed')){break}
                Start-Sleep -Milliseconds 200
            }while([DateTime]::UtcNow -lt $deadline)
            $job.ItemId=[string]$item.Id;$job.Status=[string]$item.Status
            $rows.Add(@{Label="Native $($job.Owner) $($job.Quality) preparation";Kind='BPreparation';Status=$job.Status;HasOutput=[bool](Test-Path -LiteralPath $item.OutputPath)})
            if($item.Status -ne 'ReadyToTransfer'){continue}
            $job.Hash=(Get-FileHash -LiteralPath $item.OutputPath).Hash
            if($job.Quality -eq 'Custom'){
                $script:BOutputs+=@(@{Path=$item.OutputPath;Hash=$job.Hash})
                ConvertTo-Json -InputObject @($script:BOutputs) -Depth 4|Set-Content (Join-Path $env:PERSONAL_YOUTUBE_B_OUTPUT 'outputs.json') -Encoding UTF8
                $probe=& (Join-Path $root 'server/system/ffprobe.exe') -v error -show_entries stream=codec_name,codec_type -show_entries format=duration -of json $item.OutputPath
                if($LASTEXITCODE -ne 0){throw 'ffprobe failed'}
                $media=($probe -join "`n")|ConvertFrom-Json
                $rows.Add(@{Label="Native $($job.Owner) converted bytes";Kind='BConverted';Codec=@($media.streams|Where-Object codec_type -eq 'video')[0].codec_name;Duration=$media.format.duration;Hash=$job.Hash;Bytes=(Get-Item -LiteralPath $item.OutputPath).Length})
            }
        }
    }
    foreach($actor in @('a','b')){
        $other=if($actor -eq 'a'){'b'}else{'a'}
        $r=Request 'Sync/Jobs' $subjects[$actor].Headers Post @{TargetId="followup-b-$actor";ItemIds=@($subjects[$other].References[1]);UserId=$subjects[$other].UserId;Quality='Original'}
        $createdForeign=$false
        if($r.Status -eq 200){
            $value=$r.Text|ConvertFrom-Json;$job=if($value.Job){$value.Job}else{$value}
            if($job.Id -and $job.Name -eq "PrivateNativeVideo_${other}_client"){
                $createdForeign=$true;$journal.SyncJobs+=@(@{JobId=[string]$job.Id;Name=$job.Name})
                $journal|ConvertTo-Json -Depth 12|Set-Content $journalPath -Encoding UTF8
            }else{throw 'Unexpected foreign job identity; preserve fixture journal'}
        }
        $rows.Add(@{Label="Active $actor foreign Sync source and forged UserId";Kind='BForeignCreation';Status=$r.Status;NativeJobCreated=$createdForeign;IsolationPass=$r.Status -in @(401,403,404) -and -not $createdForeign})
    }
    BSocket
    BSoap
}
function BSocket{
    $sockets=@{};$stamp=[guid]::NewGuid().ToString('N')
    try{
        foreach($owner in @('a','b')){
            $socket=[Net.WebSockets.ClientWebSocket]::new();$sockets[$owner]=$socket
            $cts=[Threading.CancellationTokenSource]::new(4000)
            try{$socket.ConnectAsync([uri]($base.Replace('http:','ws:')+'/embywebsocket?api_key='+[uri]::EscapeDataString($subjects[$owner].Headers['X-Emby-Token'])+'&deviceId=followup-b-'+$owner),$cts.Token).GetAwaiter().GetResult()|Out-Null}finally{$cts.Dispose()}
        }
        Call 'PersonalChannelsFixture/NotifyNative' $admin Post @{UserA=$subjects.a.UserId;UserB=$subjects.b.UserId;Stamp=$stamp}|Out-Null
        foreach($owner in @('a','b')){
            $cts=[Threading.CancellationTokenSource]::new(4000);$found=$false
            try{
                $buffer=New-Object byte[] 65536
                while(-not $cts.IsCancellationRequested -and -not $found){
                    $memory=[IO.MemoryStream]::new()
                    try{do{$frame=$sockets[$owner].ReceiveAsync([ArraySegment[byte]]::new($buffer),$cts.Token).GetAwaiter().GetResult();$memory.Write($buffer,0,$frame.Count)}while(-not $frame.EndOfMessage)
                        $message=[Text.Encoding]::UTF8.GetString($memory.ToArray())|ConvertFrom-Json
                    }finally{$memory.Dispose()}
                    if($message.MessageType -eq 'LibraryChanged' -and $message.Data.FixtureControlStamp -eq $stamp){
                        $found=$true;$other=if($owner -eq 'a'){'b'}else{'a'}
                        $text=$message.Data|ConvertTo-Json -Depth 8
                        $own=$text.Contains([string]$subjects[$owner].References[1]);$foreign=$text.Contains([string]$subjects[$other].References[1])
                        $rows.Add(@{Label="Active WebSocket LibraryChanged $owner";Kind='BNotification';OwnId=$own;ForeignId=$foreign;PositiveControl=$found;IsolationPass=$own -and -not $foreign;Scope='Controlled native SendMessageToUserSessions; not automatic notifier'})
                    }
                }
            }catch{if(-not $cts.IsCancellationRequested){throw}}finally{$cts.Dispose()}
            if(-not $found){throw 'WebSocket positive control missing'}
        }
    }finally{foreach($socket in $sockets.Values){$socket.Abort();$socket.Dispose()}}
}
function BSoap{
    $info=Call 'System/Info/Public'
    foreach($actor in @('a','b','anonymous')){foreach($owner in @('a','b')){
        $headers=@{SOAPAction='"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"'}
        if($actor -ne 'anonymous'){$headers['X-Emby-Token']=$subjects[$actor].Headers['X-Emby-Token']}
        $body='<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>'+[string]$subjects[$owner].References[1]+'</ObjectID><BrowseFlag>BrowseMetadata</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>100</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>'
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/Dlna/$($info.Id)/contentdirectory/control")
        foreach($key in $headers.Keys){$message.Headers.TryAddWithoutValidation($key,$headers[$key])|Out-Null}
        $message.Content=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'text/xml');$response=$null
        try{$response=$client.SendAsync($message).GetAwaiter().GetResult();$text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $marker=$text.Contains("PrivateNativeVideo_${owner}_client")
            $rows.Add(@{Label="Active DLNA $actor source $owner";Kind='BDlna';Actor=$actor;Owner=$owner;Status=[int]$response.StatusCode;PrivateMarker=$marker;BrowseResponse=$text.Contains('BrowseResponse');PositiveControl=$actor -eq $owner -and $marker;IsolationPass=$null;Scope='Missing paired positive proof; native SOAP BrowseMetadata; issued credentials never saved'})
        }finally{if($response){$response.Dispose()};$message.Dispose()}
    }}
}
function Invoke-AProbe($phase,$aActive){
    if($phase -eq 'Active'){BSetup}
    foreach($job in $script:BJobs){
        foreach($actor in @('a','b','anonymous')){
            $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
            $allowed=$actor -eq $job.Owner -and ($job.Owner -ne 'a' -or $aActive -or $PublicMetadataA)
            foreach($entry in @(@{Operation="Sync $($job.Quality) job";Path="Sync/Jobs/$($job.Id)"},@{Operation="Sync $($job.Quality) items";Path="Sync/JobItems?JobId=$($job.Id)"},@{Operation="Sync $($job.Quality) file";Path="Sync/JobItems/$($job.ItemId)/File"})){
                $r=Request $entry.Path $headers
                $hash=if($entry.Operation.EndsWith('file')){$job.Hash}else{''}
                BObserve $phase $actor $job.Owner $entry.Operation $r $allowed $hash|Out-Null
            }
            $r=Request "Sync/Items/Ready?TargetId=followup-b-$($job.Owner)" $headers
            BObserve $phase $actor $job.Owner 'Ready target' $r $allowed|Out-Null
        }
    }
    foreach($owner in @('a','b')){
        $stream=$script:BStreams[$owner]
        foreach($actor in @('a','b')){
            $body=@{};foreach($key in $stream.Body.Keys){$body[$key]=$stream.Body[$key]}
            $body.PlaySessionId=[guid]::NewGuid().ToString('N')
            $allowed=$actor -eq $owner -and ($owner -ne 'a' -or $aActive -or $PublicMetadataA)
            $r=Request 'LiveStreams/Open' $subjects[$actor].Headers Post $body
            BObserve $phase $actor $owner 'Retained OpenToken forged owner claim' $r $allowed|Out-Null
            if($r.Status -eq 200){
                $opened=($r.Text|ConvertFrom-Json).MediaSource
                Request 'LiveStreams/Close' $admin Post @{LiveStreamId=$opened.LiveStreamId;PlaySessionId=$body.PlaySessionId}|Out-Null
            }
        }
        foreach($actor in @('a','b','anonymous')){
            $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
            $allowed=$actor -eq $owner -and ($owner -ne 'a' -or $aActive -or $PublicMetadataA) -and $phase -ne 'Restarted'
            $r=Request 'LiveStreams/MediaInfo' $headers Post @{LiveStreamId=$stream.LiveId}
            BObserve $phase $actor $owner 'Retained live MediaInfo' $r $allowed|Out-Null
            if($phase -ne 'Restarted'){
                $r=Request "Videos/$($subjects[$owner].References[1])/stream.mp4?Static=true&LiveStreamId=$([uri]::EscapeDataString($stream.LiveId))&MediaSourceId=$([uri]::EscapeDataString($stream.SourceId))" $headers
                $lib=@($fixture.Libraries|Where-Object Owner -eq $owner)[0]
                $hash=(Get-FileHash (Join-Path $lib.Folder "PrivateNativeVideo_${owner}_client.mp4")).Hash
                BObserve $phase $actor $owner 'Retained live static bytes' $r $allowed $hash|Out-Null
            }
        }
        if($phase -eq 'Deleted'){
            $other=if($owner -eq 'a'){'b'}else{'a'}
            $r=Request 'LiveStreams/Close' $subjects[$other].Headers Post @{LiveStreamId=$stream.LiveId;PlaySessionId=$stream.Session}
            $after=Request 'LiveStreams/MediaInfo' $subjects[$owner].Headers Post @{LiveStreamId=$stream.LiveId}
            $rows.Add(@{Label="Deleted $other foreign Close $owner";Kind='BClose';Status=$r.Status;OwnerAfterStatus=$after.Status;OwnerStillHasMetadata=$after.Text.Contains("PrivateNativeVideo_${owner}_client");IsolationPass=$r.Status -in @(401,403,404)})
        }
    }
    if($phase -eq 'Restarted'){
        foreach($job in @($script:BJobs|Where-Object{$_.Owner -eq 'a' -and $_.Quality -eq 'Custom'})){
            $record=@($script:BOutputs|Where-Object Hash -eq $job.Hash)[0]
            $deleted=Request "Sync/Jobs/$($job.Id)" $admin Delete
            $readback=Request "Sync/Jobs/$($job.Id)" $admin
            $exists=Test-Path -LiteralPath $record.Path
            $rows.Add(@{Label='Native converted job deletion physical readback';Kind='BOrphan';DeleteStatus=$deleted.Status;JobReadbackStatus=$readback.Status;OutputStillExists=$exists;HashUnchanged=if($exists){(Get-FileHash -LiteralPath $record.Path).Hash -eq $record.Hash}else{$null}})
        }
    }
}
