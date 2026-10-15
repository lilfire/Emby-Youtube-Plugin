# Runs inside the existing production fixture. No replacement access adapter.
function DResult($label,$path,$headers,$method='Get',$expectedOwner=$null){
    try{$r=Request $path $headers $method}
    catch{
        if($_.Exception.ToString() -notmatch 'canceled|cancelled|TaskCanceled'){throw}
        $rows.Add(@{Label=$label;Method=$method;TransportTimeout=$true;Support='no completed response; unverified'})
        return @{Status=0;Bytes=[byte[]]@();Text='';HeaderNames=@()}
    }
    $entity=@($r.HeaderNames|Where-Object {$_ -in @('Content-Disposition','Content-Range','ETag','Last-Modified','Accept-Ranges')})
    $text=[Text.Encoding]::UTF8.GetString($r.Bytes)
    $aMatch=(Hash $r.Bytes) -eq $subjects.a.SourceHash
    $bMatch=(Hash $r.Bytes) -eq $subjects.b.SourceHash
    $safe=$r.Status -in @(401,403,404) -and $entity.Count -eq 0 -and -not $aMatch -and -not $bMatch -and -not $r.PrivateAHeader -and -not $r.PrivateBHeader -and -not $text.Contains('PrivateNativeVideo_')
    $row=@{Label=$label;Method=$method;Status=$r.Status;Bytes=$r.Bytes.Length;EntityHeaderCount=$entity.Count;ContentRange=$r.ContentRange;MatchesA=$aMatch;MatchesB=$bMatch;Playlist=$text.StartsWith('#EXTM3U');ReferencesA=$text.Contains([string]$subjects.a.VideoId);PrivateName=($text.Contains('PrivateNativeVideo_') -or $r.PrivateAHeader -or $r.PrivateBHeader)}
    if($expectedOwner){$row.OwnerHashPass=$r.Status -eq 200 -and $(if($expectedOwner -eq 'a'){$aMatch}else{$bMatch})}
    else{$row.IsolationPass=$safe}
    $rows.Add($row)
    return $r
}
function DDenied($label){
    foreach($variant in @('Get','Head','Range','Conditional','IfRange')){
        $h=$subjects.a.Headers.Clone()
        if($variant -in @('Range','IfRange')){$h.Range='bytes=0-127'}
        if($variant -eq 'Conditional'){$h['If-None-Match']=$subjects.a.ETag}
        if($variant -eq 'IfRange'){$h['If-Range']=$subjects.a.ETag}
        DResult "$label old A $variant" (StreamPath 'a') $h $(if($variant -eq 'Head'){'Head'}else{'Get'})|Out-Null
    }
    foreach($template in @('Audio/{id}/stream.mp4?Static=true','Videos/{id}/master.m3u8?VideoCodec=h264&AudioCodec=aac')){
        DResult "$label B foreign $template" ($template.Replace('{id}',[string]$subjects.a.VideoId)) $subjects.b.Headers|Out-Null
    }
    OwnStreams "$label independent B" 'b'
}
if($Mode -notin @('Transport','Public','Content','Hls')){
    DResult 'D initial audio A owner control' "Audio/$($subjects.a.VideoId)/stream.mp4?Static=true" $subjects.a.Headers Get 'a'|Out-Null
    DResult 'D initial audio B foreign control' "Audio/$($subjects.a.VideoId)/stream.mp4?Static=true" $subjects.b.Headers|Out-Null
}
if($Mode -in @('Transport','Public')){
    $client.Dispose();$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(5)
    $paths=@(
        'Videos/{id}/stream.mp4?Static=true','Videos/{id}/stream?Static=true','Videos/{id}/original',
        'Videos/{id}/stream.mp4?Static=false&VideoCodec=h264&AudioCodec=aac',
        'Videos/{id}/master.m3u8?VideoCodec=h264&AudioCodec=aac','Videos/{id}/main.m3u8?VideoCodec=h264&AudioCodec=aac',
        'Videos/{id}/live.m3u8','Videos/{id}/hls1/main/0.ts','Videos/{id}/hls/main/0.ts',
        'Audio/{id}/stream.mp4?Static=true','Audio/{id}/stream?Static=true','Audio/{id}/original',
        'Audio/{id}/universal?Container=mp3','Audio/{id}/master.m3u8','Audio/{id}/main.m3u8','Audio/{id}/live.m3u8',
        'Audio/{id}/hls1/main/0.ts','Audio/{id}/hls/main/0.ts')
    foreach($template in $paths){
        foreach($actor in @('a','b','anonymous')){
            $h=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
            $path=$template.Replace('{id}',[string]$subjects.a.VideoId)
            $r=DResult "D route $actor $template" $path $h
            $last=$rows[$rows.Count-1]
            if($actor -eq 'a' -or ($Mode -eq 'Public' -and $actor -eq 'b')){
                $last.Remove('IsolationPass');$last.PositiveBytes=$r.Status -in @(200,206) -and $r.Bytes.Length -gt 0
                $last.OwnerContent=$last.MatchesA
                $last.Support=if($last.PositiveBytes){'observed delivery; inspect format'}else{'owner transport unavailable'}
            }
        }
    }
    $sourceBytes=[IO.File]::ReadAllBytes($subjects.a.SourcePath);$length=$sourceBytes.Length
    foreach($case in @(
        @{Name='middle';Range='bytes=128-255';Start=128;Count=128},
        @{Name='suffix';Range='bytes=-128';Start=$length-128;Count=128},
        @{Name='open';Range="bytes=$($length-128)-";Start=$length-128;Count=128},
        @{Name='multiple';Range='bytes=0-15,32-47'},
        @{Name='unsatisfiable';Range="bytes=$($length+10)-"},
        @{Name='reversed';Range='bytes=127-0'},
        @{Name='malformed';Range='bytes=invalid'},
        @{Name='ifrange-match';Range='bytes=0-127';IfRange=$subjects.a.ETag},
        @{Name='ifrange-stale';Range='bytes=0-127';IfRange='"stale-d-validator"'})){
        foreach($actor in @('a','b')){
            $h=$subjects[$actor].Headers.Clone();$h.Range=$case.Range
            if($case.IfRange){$h['If-Range']=$case.IfRange}
            $r=DResult "D HTTP $actor $($case.Name)" (StreamPath 'a') $h
            if($actor -eq 'a'){
                $last=$rows[$rows.Count-1];$last.Remove('IsolationPass')
                if($case.Count){$slice=[byte[]]$sourceBytes[$case.Start..($case.Start+$case.Count-1)];$last.RangeBytesPass=$r.Status -eq 206 -and (Hash $r.Bytes) -eq (Hash $slice)}
                else{$last.NativeSemantics='recorded, no assumed RFC compatibility'}
            }elseif($Mode -eq 'Public'){$rows[$rows.Count-1].Remove('IsolationPass')}
        }
    }
    if($Mode -eq 'Public'){
        DResult 'D public A to B full control' (StreamPath 'a') $subjects.b.Headers Get 'a'|Out-Null
        DResult 'D public regression private B to A negative control' (StreamPath 'b') $subjects.a.Headers|Out-Null
    }
}
if($Mode -in @('Channel','Key')){
    $input=@{ExpectedRevision=$subjects.a.Profile.Revision;Channels=@('UC'+('a'*22))}
    if($Mode -eq 'Channel'){$input.Channels=@('UC'+('c'*22))}else{$input.ApiKey='synthetic-d-key-not-a-google-secret'}
    $saved=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers Post $input
    $readback=Call 'YouTubePlugin/MyProfile' $subjects.a.Headers
    $rows.Add(@{Label="D $Mode mutation persisted";RevisionAdvanced=$readback.Revision -gt $subjects.a.Profile.Revision;ChannelReadback=($readback.Channels -join ',') -eq ($input.Channels -join ',');KeyRevision=$readback.KeyRevision;HasApiKey=$readback.HasApiKey})
    DDenied "D $Mode change"
}
if($Mode -eq 'Accounts'){
    $policy=(Call "Users/$($subjects.a.UserId)").Policy
    $policy.IsDisabled=$true
    Call "Users/$($subjects.a.UserId)/Policy" $admin Post $policy|Out-Null
    if(-not (Call "Users/$($subjects.a.UserId)").Policy.IsDisabled){throw 'Disabled account readback failed'}
    DDenied 'D disabled account'
    $policy.IsDisabled=$false
    Call "Users/$($subjects.a.UserId)/Policy" $admin Post $policy|Out-Null
    $u=@($fixture.Users|Where-Object Owner -eq 'a')[0]
    $login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="D", Device="Isolated", DeviceId="d-enabled-a", Version="1"'} Post @{Username=$u.Name;Pw=''}
    if($login.User.Id -ne $subjects.a.UserId){throw 'Enabled identity mismatch'}
    $subjects.a.Headers=@{'X-Emby-Token'=$login.AccessToken}
    OwnStreams 'D enabled account control' 'a'
    $r=Request ('Auth/Keys/'+$subjects.a.Headers['X-Emby-Token']) $admin Delete
    if($r.Status -notin @(200,204)){throw 'Token revoke failed'}
    DDenied 'D token revoked'
    $u=@($fixture.Users|Where-Object Owner -eq 'a')[0]
    $login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="D", Device="Isolated", DeviceId="d-new-a", Version="1"'} Post @{Username=$u.Name;Pw=''}
    if($login.User.Id -ne $subjects.a.UserId){throw 'Reauthentication owner mismatch'}
    $subjects.a.Headers=@{'X-Emby-Token'=$login.AccessToken}
    OwnStreams 'D new session same owner control' 'a'
    Call "Users/$($subjects.a.UserId)" $admin Delete|Out-Null
    if(@((Call 'Users')|Where-Object Id -eq $subjects.a.UserId).Count){throw 'Deleted account readback failed'}
    DDenied 'D account deleted'
}
if($Mode -eq 'Content'){
    # Controlled local replacement; restore bytes and metadata even on failure.
    $path=$subjects.a.SourcePath;$original=[IO.File]::ReadAllBytes($path);$time=[IO.File]::GetLastWriteTimeUtc($path)
    try{
        [IO.File]::WriteAllBytes($path,[IO.File]::ReadAllBytes($subjects.b.SourcePath));[IO.File]::SetLastWriteTimeUtc($path,$time)
        if((Get-FileHash $path).Hash -ne $subjects.b.SourceHash){throw 'Replacement not read back'}
        $r=DResult 'D approved A path replaced with B bytes' (StreamPath 'a') $subjects.a.Headers Get 'a'
        DResult 'D replaced path foreign control' (StreamPath 'a') $subjects.b.Headers|Out-Null
        OwnStreams 'D replaced path independent B' 'b'
    }finally{[IO.File]::WriteAllBytes($path,$original);[IO.File]::SetLastWriteTimeUtc($path,$time)}
    OwnStreams 'D restored A source' 'a'
}
if($Mode -in @('Lease','BeforeWrite')){
    . (Join-Path $dChapter 'Lease-D.ps1')
}
if($Mode -eq 'Hls'){
    . (Join-Path $dChapter 'Hls-D.ps1')
}
if($Mode -eq 'Boundary'){
    . (Join-Path $dChapter 'Boundary-D.ps1')
}
if($Mode -eq 'Abort'){
    . (Join-Path $dChapter 'Abort-D.ps1')
}
