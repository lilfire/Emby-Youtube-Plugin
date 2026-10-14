param([switch]$RequireIsolation)
$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$root=Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated'
$auth=Get-Content (Join-Path $root 'test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$journal=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$rows=[Collections.Generic.List[object]]::new()
$subjects=@{}
function Call($path,$headers,$body=$null) {
    $args=@{Uri=$base+$path;Headers=$headers;Method='Post';ContentType='application/json';TimeoutSec=20;UseBasicParsing=$true}
    if ($null -ne $body) {$args.Body=$body|ConvertTo-Json -Depth 12}
    try {$r=Invoke-WebRequest @args;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch {
        if (-not $_.Exception.Response) {throw}
        $text=[string]$_.ErrorDetails.Message
        if (-not $text) { $reader=[IO.StreamReader]::new($_.Exception.Response.GetResponseStream()); try {$text=$reader.ReadToEnd()} finally {$reader.Dispose()} }
        return @{Status=[int]$_.Exception.Response.StatusCode;Text=$text}
    }
}
try {
    $info=Invoke-RestMethod ($base+'System/Info/Public')
    $guard=Invoke-RestMethod ($base+'PersonalChannelsFixture/Guard') -Headers $admin
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Ready -or -not $guard.Enabled -or -not $journal.SetupReady) {throw 'Wrong isolated fixture'}
    foreach ($owner in @('a','b')) {
        $user=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $library=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Live stream test`", Device=`"Isolated`", DeviceId=`"live-fixture-$owner`", Version=`"1.0`""} @{Username=$user.Name;Pw=''}
        if ($login.Status -ne 200) {throw 'Fixture login failed'}
        $session=$login.Text|ConvertFrom-Json
        if ($session.User.Id -ne $user.UserId -or $session.User.Policy.IsAdministrator) {throw 'Wrong synthetic subject'}
        $subjects[$owner]=@{Headers=@{'X-Emby-Token'=$session.AccessToken};UserId=$user.UserId;VideoId=$library.VideoId}
    }
    foreach ($owner in @('a','b')) {
        $own=$subjects[$owner];$other=if ($owner -eq 'a') {'b'} else {'a'}
        $play=Call "Items/$($own.VideoId)/PlaybackInfo" $own.Headers @{UserId=$own.UserId;DeviceId="live-fixture-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        if ($play.Status -ne 200) {throw 'No own playback info'}
        $playInfo=$play.Text|ConvertFrom-Json
        # Ordinary local-file PlaybackInfo does not request dynamic sources.
        # Use the admin fixture to prepare the native manager's wrapped token.
        $source=@(Invoke-RestMethod ($base+"PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($own.VideoId)") -Headers $admin)
        if ($source.Count -ne 1 -or -not $source[0].OpenToken -or -not $playInfo.PlaySessionId) {throw 'No native wrapped fixture open token'}
        $body=@{ItemId=[long]$own.VideoId;UserId=$own.UserId;OpenToken=$source[0].OpenToken;PlaySessionId=$playInfo.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $open=Call 'LiveStreams/Open' $own.Headers $body
        $rows.Add(@{Owner=$owner;Actor=$owner;Operation='Open';Status=$open.Status})
        if ($open.Status -ne 200) {
            $diagnostics=[regex]::Matches($open.Text,'[A-Za-z]+Exception|[A-Za-z]+ is required|not found|not supported|Invalid [A-Za-z ]{1,40}')|ForEach-Object Value|Select-Object -Unique
            Write-Output ($diagnostics -join ', ')
            throw 'Own native stream open failed'
        }
        $opened=$open.Text|ConvertFrom-Json
        $liveId=$opened.MediaSource.LiveStreamId
        if (-not $liveId) {throw 'No actual native LiveStreamId'}
        $own.LiveStreamId=$liveId;$own.PlaySessionId=$playInfo.PlaySessionId
        foreach ($actor in @($owner,$other,'anonymous')) {
            $headers=if ($actor -eq 'anonymous') {@{}} else {$subjects[$actor].Headers}
            $r=Call 'LiveStreams/MediaInfo' $headers @{LiveStreamId=$liveId}
            $rows.Add(@{Owner=$owner;Actor=$actor;Operation='MediaInfo';Status=$r.Status;HasPrivateName=$r.Text.Contains("PrivateNativeVideo_${owner}_client");HasPrivatePath=$r.Text.Contains('native-client');HasPrivateSourceId=$r.Text.Contains("fixture-live-source-$($own.VideoId)")})
            if ($actor -eq $owner -and ($r.Status -ne 200 -or -not $r.Text.Contains("PrivateNativeVideo_${owner}_client"))) {throw 'Own positive metadata control failed'}
            $expectedDenied=if ($actor -eq 'anonymous') {401} else {404}
            if ($RequireIsolation -and $actor -ne $owner -and $r.Status -ne $expectedDenied) {throw 'Private stream metadata was not denied'}
        }
        $foreignOpen=Call 'LiveStreams/Open' $subjects[$other].Headers $body
        $rows.Add(@{Owner=$owner;Actor=$other;Operation='Open foreign ItemId';Status=$foreignOpen.Status})
        if ($RequireIsolation) {
            if ($foreignOpen.Status -ne 404) {throw 'Foreign item open not denied'}
            $spoof=Call ("LiveStreams/MediaInfo?UserId="+$own.UserId) $subjects[$other].Headers @{LiveStreamId=$liveId}
            $rows.Add(@{Owner=$owner;Actor=$other;Operation='MediaInfo spoofed UserId';Status=$spoof.Status})
            if ($spoof.Status -ne 404) {throw 'Spoofed user gained stream access'}
            $foreignClose=Call 'LiveStreams/Close' $subjects[$other].Headers @{LiveStreamId=$liveId;PlaySessionId=$own.PlaySessionId}
            $rows.Add(@{Owner=$owner;Actor=$other;Operation='Close foreign known PlaySessionId';Status=$foreignClose.Status})
            if ($foreignClose.Status -ne 404) {throw 'Foreign close not denied'}
            $after=Call 'LiveStreams/MediaInfo' $own.Headers @{LiveStreamId=$liveId}
            $rows.Add(@{Owner=$owner;Actor=$owner;Operation='MediaInfo after foreign Close';Status=$after.Status;HasPrivateName=$after.Text.Contains("PrivateNativeVideo_${owner}_client")})
            if ($after.Status -ne 200 -or -not $after.Text.Contains("PrivateNativeVideo_${owner}_client")) {throw 'Foreign close changed owner availability'}
        }
        $closed=Call 'LiveStreams/Close' $own.Headers @{LiveStreamId=$liveId;PlaySessionId=$own.PlaySessionId}
        $rows.Add(@{Owner=$owner;Actor=$owner;Operation='Close';Status=$closed.Status})
        if ($closed.Status -ne 204) {throw 'Own close failed'}
    }
    $leaks=@($rows|Where-Object {$_.Actor -ne $_.Owner -and ($_.HasPrivateName -or $_.HasPrivatePath -or $_.HasPrivateSourceId)})
    $name=if ($RequireIsolation) {'native-live-stream-protected-results.json'} else {'native-live-stream-access-results.json'}
    @{Scope='Synthetic local provider through native Open/MediaInfo/Close; not current YouTube playback';ServerVersion=$info.Version;GuardReady=$guard.Ready;Completed=$true;RequiredIsolation=$RequireIsolation.IsPresent;TestIsolationPassed=($leaks.Count -eq 0);LeakCount=$leaks.Count;Observations=$rows} | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    Write-Output ("Native live stream test completed; observations="+$rows.Count+"; leaking metadata responses="+$leaks.Count)
} catch {
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $PSScriptRoot 'bin/native-live-stream-access-incomplete.json') -Encoding UTF8
    throw
}
