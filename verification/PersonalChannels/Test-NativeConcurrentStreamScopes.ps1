$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$state=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$subjects=@{};$rows=[Collections.Generic.List[object]]::new();$jobs=@();$pool=$null
function Call($path,$headers,$body){Invoke-RestMethod ($base+$path) -Method Post -Headers $headers -ContentType application/json -Body ($body|ConvertTo-Json -Depth 10) -TimeoutSec 30}
$worker={
    param($base,$owner,$subject,$foreign,$number)
    $ErrorActionPreference='Stop';$result=[Collections.Generic.List[object]]::new()
    function WorkerRequest($path,$headers,$body){
        try{$r=Invoke-WebRequest ($base+$path) -Method Post -Headers $headers -ContentType application/json -Body ($body|ConvertTo-Json -Depth 10) -TimeoutSec 30 -UseBasicParsing;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
        catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
    }
    function Save($operation,$r,$expected,$marker=$null){
        $right=if($marker){$r.Text.Contains($marker)}else{$false}
        $result.Add(@{Owner=$owner;Worker=$number;Operation=$operation;Status=$r.Status;HasOwnMarker=$right;ContainsPrivateA=$r.Text.Contains('PrivateNativeVideo_a_client');ContainsPrivateB=$r.Text.Contains('PrivateNativeVideo_b_client')})
        if($r.Status -ne $expected -or ($marker -and -not $right)){throw 'Concurrent native positive/negative control failed'}
    }
    $open=WorkerRequest 'LiveStreams/Open' $subject.Headers @{ItemId=[long]$subject.VideoId;UserId=$subject.UserId;OpenToken=$subject.OpenToken;PlaySessionId=$subject.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    Save 'Own Open' $open 200
    $live=($open.Text|ConvertFrom-Json).MediaSource.LiveStreamId
    if(-not $live){throw 'No native stream reference'}
    $metadata=WorkerRequest 'LiveStreams/MediaInfo' $subject.Headers @{LiveStreamId=$live}
    Save 'Own MediaInfo' $metadata 200 "PrivateNativeVideo_${owner}_client"
    $hidden=WorkerRequest 'LiveStreams/MediaInfo' $foreign.Headers @{LiveStreamId=$live}
    Save 'Foreign MediaInfo' $hidden 404
    if($hidden.Text.Contains("PrivateNativeVideo_${owner}_client")){throw 'Concurrent metadata leaked'}
    $closeForeign=WorkerRequest 'LiveStreams/Close' $foreign.Headers @{LiveStreamId=$live;PlaySessionId=$subject.PlaySessionId}
    Save 'Foreign Close' $closeForeign 404
    $after=WorkerRequest 'LiveStreams/MediaInfo' $subject.Headers @{LiveStreamId=$live}
    Save 'Own MediaInfo after foreign Close' $after 200 "PrivateNativeVideo_${owner}_client"
    $close=WorkerRequest 'LiveStreams/Close' $subject.Headers @{LiveStreamId=$live;PlaySessionId=$subject.PlaySessionId}
    Save 'Own Close' $close 204
    return $result.ToArray()
}
try{
    $info=Invoke-RestMethod ($base+'System/Info/Public');$guard=Invoke-RestMethod ($base+'PersonalChannelsFixture/Guard') -Headers $admin
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Ready -or -not $guard.Enabled -or -not $state.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Concurrent scope test`", Device=`"Isolated`", DeviceId=`"scope-$owner`", Version=`"1.0`""} @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong subject'}
        $headers=@{'X-Emby-Token'=$login.AccessToken}
        $play=Call "Items/$($l.VideoId)/PlaybackInfo" $headers @{UserId=$u.UserId;DeviceId="scope-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $source=@(Invoke-RestMethod ($base+"PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($l.VideoId)") -Headers $admin)
        if($source.Count -ne 1 -or -not $source[0].OpenToken -or -not $play.PlaySessionId){throw 'No own native source'}
        $subjects[$owner]=@{Headers=$headers;UserId=$u.UserId;VideoId=$l.VideoId;PlaySessionId=$play.PlaySessionId;OpenToken=$source[0].OpenToken}
    }
    Call 'PersonalChannelsFixture/NativeFixtureStreamProbe' $admin @{DelayMs=1500}|Out-Null
    $pool=[RunspaceFactory]::CreateRunspacePool(1,6);$pool.Open()
    foreach($number in 1..6){
        $owner=if($number%2){'a'}else{'b'};$other=if($owner -eq 'a'){'b'}else{'a'}
        $ps=[PowerShell]::Create();$ps.RunspacePool=$pool
        $ps.AddScript($worker.ToString()).AddArgument($base).AddArgument($owner).AddArgument($subjects[$owner]).AddArgument($subjects[$other]).AddArgument($number)|Out-Null
        $jobs+=@(@{PowerShell=$ps;Handle=$ps.BeginInvoke()})
    }
    foreach($job in $jobs){$output=$job.PowerShell.EndInvoke($job.Handle);if($job.PowerShell.HadErrors){throw 'Concurrent worker failed'};foreach($row in $output){$rows.Add($row)}}
    $activity=Invoke-RestMethod ($base+'PersonalChannelsFixture/NativeFixtureStreamActivity') -Headers $admin
    $probe=$activity.Probe
    if($rows.Count -ne 36 -or $probe.NativeOpenCalls -ne 6 -or $probe.CrossSubjectOverlapEvents -lt 1 -or $probe.MaximumActive -lt 2 -or $probe.DistinctSubjects -ne 2 -or $probe.ActiveCalls -ne 0){throw 'No verified cross-subject native overlap'}
    if(@($activity.NativeOpenStreams.PSObject.Properties).Count -ne 0){throw 'Concurrent streams were not closed'}
    @{Completed=$true;Scope='Six HTTP workers, async native Open tasks and delayed synthetic local source; no media bytes';Observations=$rows;Activity=$activity}|ConvertTo-Json -Depth 9|Set-Content (Join-Path $PSScriptRoot 'bin/native-concurrent-stream-scopes-results.json') -Encoding UTF8
    Write-Output ("Concurrent scope test completed; observations="+$rows.Count+"; cross-subject overlap events="+$probe.CrossSubjectOverlapEvents+"; maximum active native Open tasks="+$probe.MaximumActive)
    Call 'PersonalChannelsFixture/NativeFixtureStreamProbe' $admin @{DelayMs=0}|Out-Null
}catch{
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot 'bin/native-concurrent-stream-scopes-incomplete.json') -Encoding UTF8
    throw
}finally{foreach($job in $jobs){$job.PowerShell.Dispose()};if($pool){$pool.Dispose()}}
