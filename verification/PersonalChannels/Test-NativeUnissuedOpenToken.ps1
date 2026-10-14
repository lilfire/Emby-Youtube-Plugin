param([switch]$RequireIsolation)
$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$state=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$subjects=@{};$rows=[Collections.Generic.List[object]]::new()
function Call($path,$headers,$body) {
    try{$r=Invoke-WebRequest ($base+$path) -Method Post -Headers $headers -ContentType application/json -Body ($body|ConvertTo-Json -Depth 10) -TimeoutSec 20 -UseBasicParsing;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Activity {Invoke-RestMethod ($base+'PersonalChannelsFixture/NativeFixtureStreamActivity') -Headers $admin}
function Count($snapshot,$group,$owner){$v=$snapshot.$group.PSObject.Properties["PrivateNativeVideo_${owner}_client"].Value;if($null -eq $v){return 0};return [int]$v}
function Prepare($owner){$source=@(Invoke-RestMethod ($base+"PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($subjects[$owner].VideoId)") -Headers $admin);if($source.Count -ne 1 -or -not $source[0].OpenToken){throw 'No native source'};return [string]$source[0].OpenToken}
function Positive($owner,$token) {
    $s=$subjects[$owner]
    $open=Call 'LiveStreams/Open' $s.Headers @{ItemId=[long]$s.VideoId;UserId=$s.UserId;OpenToken=$token;PlaySessionId=$s.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    $rows.Add(@{Actor=$owner;Operation='Own Open';Status=$open.Status});if($open.Status -ne 200){throw 'Own open failed'}
    $live=($open.Text|ConvertFrom-Json).MediaSource.LiveStreamId
    $meta=Call 'LiveStreams/MediaInfo' $s.Headers @{LiveStreamId=$live};$right=$meta.Text.Contains("PrivateNativeVideo_${owner}_client")
    $rows.Add(@{Actor=$owner;Operation='Own MediaInfo';Status=$meta.Status;HasCorrectMarker=$right});if($meta.Status -ne 200 -or -not $right){throw 'Own metadata failed'}
    $close=Call 'LiveStreams/Close' $s.Headers @{LiveStreamId=$live;PlaySessionId=$s.PlaySessionId}
    $rows.Add(@{Actor=$owner;Operation='Own Close';Status=$close.Status});if($close.Status -ne 204){throw 'Own close failed'}
}
try{
    $info=Invoke-RestMethod ($base+'System/Info/Public');$guard=Invoke-RestMethod ($base+'PersonalChannelsFixture/Guard') -Headers $admin
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Enabled -or -not $guard.Ready -or -not $state.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Unissued token test`", Device=`"Isolated`", DeviceId=`"unissued-$owner`", Version=`"1.0`""} @{Username=$u.Name;Pw=''}
        if($login.Status -ne 200){throw 'Login failed'};$session=$login.Text|ConvertFrom-Json
        if($session.User.Id -ne $u.UserId -or $session.User.Policy.IsAdministrator){throw 'Wrong subject'}
        $headers=@{'X-Emby-Token'=$session.AccessToken}
        $play=Call "Items/$($l.VideoId)/PlaybackInfo" $headers @{UserId=$u.UserId;DeviceId="unissued-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        if($play.Status -ne 200){throw 'Own playback info failed'}
        $subjects[$owner]=@{UserId=$u.UserId;VideoId=[string]$l.VideoId;Headers=$headers;PlaySessionId=($play.Text|ConvertFrom-Json).PlaySessionId}
    }
    $tokenA=Prepare a
    if(-not $tokenA.EndsWith($subjects.a.VideoId,[StringComparison]::Ordinal)){throw 'Unexpected native token structure'}
    $constructed=$tokenA.Substring(0,$tokenA.Length-$subjects.a.VideoId.Length)+$subjects.b.VideoId
    $ledgerText=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/data/data/personal-channels-fixture.json.open-token-owners.json') -Raw
    $ledger=$ledgerText|ConvertFrom-Json;$sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($constructed))).Replace('-','')}finally{$sha.Dispose()}
    $unregistered=$null -eq $ledger.Owners.PSObject.Properties[$hash]
    if(-not $unregistered){throw 'Constructed token was already issued'}
    Positive a $tokenA
    $start=Activity;if((Count $start ProviderOpenCalls b) -ne 0 -or (Count $start NativeOpenStreams b) -ne 0){throw 'B opened before unissued attack'}
    foreach($mode in @('own-private-item','no-item')){
        $before=Activity
        $body=@{UserId=$subjects.a.UserId;OpenToken=$constructed;PlaySessionId=$subjects.a.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        if($mode -eq 'own-private-item'){$body.ItemId=[long]$subjects.a.VideoId}
        $r=Call 'LiveStreams/Open' $subjects.a.Headers $body;$after=Activity
        $gateDelta=(Count $after SourceDeniedOpenCalls b)-(Count $before SourceDeniedOpenCalls b)
        $rows.Add(@{Actor='a';Operation=$mode;Status=$r.Status;HasPrivateBMarker=$r.Text.Contains('PrivateNativeVideo_b_client');BNativeBefore=(Count $before NativeOpenStreams b);BNativeAfter=(Count $after NativeOpenStreams b);BProviderOpenDelta=((Count $after ProviderOpenCalls b)-(Count $before ProviderOpenCalls b));SourceGateDenialDelta=$gateDelta})
        if($RequireIsolation -and ($r.Status -ne 404 -or (Count $after NativeOpenStreams b) -ne (Count $before NativeOpenStreams b) -or (Count $after ProviderOpenCalls b) -ne (Count $before ProviderOpenCalls b))){throw 'Constructed foreign source opened or mutated'}
        if($RequireIsolation -and $mode -eq 'no-item' -and $gateDelta -ne 1){throw 'Source authorization gate was not observed'}
    }
    # Only now issue B's source and prove the constructed value names a real source.
    $issuedB=Prepare b;$same=$issuedB -eq $constructed
    if(-not $same){throw 'Constructed token is not the actual native B reference'}
    Positive b $constructed
    $mutations=@($rows|Where-Object {$_.Actor -eq 'a' -and $_.Operation -in @('own-private-item','no-item') -and ($_.BNativeAfter -ne $_.BNativeBefore -or $_.BProviderOpenDelta -ne 0)})
    $name=if($RequireIsolation){'native-unissued-open-token-source-guard-results.json'}else{'native-unissued-open-token-results.json'}
    @{Completed=$true;Scope='Constructed never-issued native synthetic source reference; no media bytes';RequireIsolation=$RequireIsolation.IsPresent;GuardReady=$guard.Ready;TokenAbsentFromLedgerBefore=$unregistered;NoBProviderOpenBeforeAttack=$true;ConstructedEqualsLaterIssuedToken=$same;MutationCases=$mutations.Count;NoForeignMutation=($mutations.Count -eq 0);Observations=$rows;FinalNativeTable=(Activity)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    Write-Output ("Unissued token test completed; observations="+$rows.Count+"; mutation cases="+$mutations.Count)
}catch{
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot 'bin/native-unissued-open-token-incomplete.json') -Encoding UTF8
    throw
}
