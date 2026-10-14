param([switch]$RequireNoMutation)
$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$journal=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$subjects=@{}
$rows=[Collections.Generic.List[object]]::new()
function Call($path,$headers,$body) {
    try {$r=Invoke-WebRequest ($base+$path) -Method Post -Headers $headers -ContentType application/json -Body ($body|ConvertTo-Json -Depth 10) -TimeoutSec 20 -UseBasicParsing; return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch {if (-not $_.Exception.Response){throw}; return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Activity {Invoke-RestMethod ($base+'PersonalChannelsFixture/NativeFixtureStreamActivity') -Headers $admin}
function Count($snapshot,$group,$owner) {
    $value=$snapshot.$group.PSObject.Properties["PrivateNativeVideo_${owner}_client"].Value
    if ($null -eq $value) {return 0};return [int]$value
}
try {
    $info=Invoke-RestMethod ($base+'System/Info/Public')
    $guard=Invoke-RestMethod ($base+'PersonalChannelsFixture/Guard') -Headers $admin
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Ready -or -not $guard.Enabled -or -not $journal.SetupReady) {throw 'Wrong fixture'}
    $initial=Activity
    if ((Count $initial NativeOpenStreams a) -ne 0 -or (Count $initial NativeOpenStreams b) -ne 0) {throw 'Mixed token test needs no preexisting fixture streams'}
    foreach ($owner in @('a','b')) {
        $user=@($journal.Users|Where-Object Owner -eq $owner)[0];$library=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Mixed token test`", Device=`"Isolated`", DeviceId=`"mixed-token-$owner`", Version=`"1.0`""} @{Username=$user.Name;Pw=''}
        if ($login.Status -ne 200) {throw 'Login failed'}
        $session=$login.Text|ConvertFrom-Json
        if ($session.User.Id -ne $user.UserId -or $session.User.Policy.IsAdministrator) {throw 'Wrong subject'}
        $headers=@{'X-Emby-Token'=$session.AccessToken}
        $play=Call "Items/$($library.VideoId)/PlaybackInfo" $headers @{UserId=$user.UserId;DeviceId="mixed-token-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        if ($play.Status -ne 200) {throw 'Own playback info failed'}
        $playInfo=$play.Text|ConvertFrom-Json
        $source=@(Invoke-RestMethod ($base+"PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($library.VideoId)") -Headers $admin)
        if ($source.Count -ne 1 -or -not $source[0].OpenToken -or -not $playInfo.PlaySessionId) {throw 'No native positive source'}
        $subject=@{Headers=$headers;UserId=$user.UserId;VideoId=$library.VideoId;OpenToken=$source[0].OpenToken;PlaySessionId=$playInfo.PlaySessionId}
        $open=Call 'LiveStreams/Open' $headers @{ItemId=[long]$subject.VideoId;UserId=$subject.UserId;OpenToken=$subject.OpenToken;PlaySessionId=$subject.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $rows.Add(@{Actor=$owner;Operation='Own native Open';Status=$open.Status})
        if ($open.Status -ne 200) {throw 'Own stream open failed'}
        $subject.LiveStreamId=($open.Text|ConvertFrom-Json).MediaSource.LiveStreamId
        if (-not $subject.LiveStreamId) {throw 'No real native stream reference'}
        $subjects[$owner]=$subject
    }
    $positive=Activity
    if ((Count $positive NativeOpenStreams a) -ne 1 -or (Count $positive NativeOpenStreams b) -ne 1) {throw 'Native table positive control failed'}
    foreach ($actor in @('a','b')) {
        $other=if ($actor -eq 'a') {'b'} else {'a'};$own=$subjects[$actor];$foreign=$subjects[$other]
        $before=Activity
        $mixed=Call 'LiveStreams/Open' $own.Headers @{ItemId=[long]$own.VideoId;UserId=$own.UserId;OpenToken=$foreign.OpenToken;PlaySessionId=$own.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $after=Activity
        $rows.Add(@{Actor=$actor;SourceOwner=$other;Operation='Own ItemId foreign OpenToken';Status=$mixed.Status;
            HasForeignPrivateMarker=$mixed.Text.Contains("PrivateNativeVideo_${other}_client");
            ForeignNativeStreamsBefore=(Count $before NativeOpenStreams $other);ForeignNativeStreamsAfter=(Count $after NativeOpenStreams $other);
            ForeignProviderOpenDelta=((Count $after ProviderOpenCalls $other)-(Count $before ProviderOpenCalls $other));
            ForeignProviderCloseDelta=((Count $after ProviderCloseCalls $other)-(Count $before ProviderCloseCalls $other))})
        if ($RequireNoMutation -and ($mixed.Status -ne 404 -or (Count $after NativeOpenStreams $other) -ne (Count $before NativeOpenStreams $other) -or (Count $after ProviderOpenCalls $other) -ne (Count $before ProviderOpenCalls $other))) {throw 'Foreign source mutated despite required precheck'}
        foreach ($owner in @('a','b')) {
            $subject=$subjects[$owner]
            $metadata=Call 'LiveStreams/MediaInfo' $subject.Headers @{LiveStreamId=$subject.LiveStreamId}
            $correct=$metadata.Text.Contains("PrivateNativeVideo_${owner}_client")
            $rows.Add(@{Actor=$owner;Operation="Own metadata after $actor mixed Open";Status=$metadata.Status;HasCorrectPrivateMarker=$correct})
            if ($metadata.Status -ne 200 -or -not $correct) {throw 'Existing owner stream changed'}
        }
    }
    foreach ($owner in @('a','b')) {
        $subject=$subjects[$owner]
        $close=Call 'LiveStreams/Close' $subject.Headers @{LiveStreamId=$subject.LiveStreamId;PlaySessionId=$subject.PlaySessionId}
        $rows.Add(@{Actor=$owner;Operation='Own native Close';Status=$close.Status})
        if ($close.Status -ne 204) {throw 'Own close failed'}
    }
    $mutations=@($rows|Where-Object {$_.Operation -eq 'Own ItemId foreign OpenToken' -and ($_.ForeignNativeStreamsAfter -ne $_.ForeignNativeStreamsBefore -or $_.ForeignProviderOpenDelta -ne 0)})
    $name=if ($RequireNoMutation) {'native-mixed-open-token-prechecked-results.json'} else {'native-mixed-open-token-results.json'}
    @{Completed=$true;Scope='Synthetic local provider, native Open and actual native stream table; no YouTube or media bytes';GuardReady=$guard.Ready;RequireNoMutation=$RequireNoMutation.IsPresent;NoForeignMutation=($mutations.Count -eq 0);MutationCases=$mutations.Count;PositiveNativeTable=$positive;RemainingNativeTable=(Activity);Observations=$rows}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    Write-Output ("Mixed OpenToken test completed; observations="+$rows.Count+"; foreign mutation cases="+$mutations.Count)
} catch {
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot 'bin/native-mixed-open-token-incomplete.json') -Encoding UTF8
    throw
}
