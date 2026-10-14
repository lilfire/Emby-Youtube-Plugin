param([switch]$RequireIsolation)
$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$journal=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$control=Join-Path $PSScriptRoot '../EmbyFixture/Start-IsolatedServer.ps1'
$subjects=@{}
$rows=[Collections.Generic.List[object]]::new()
function Call($path,$headers,$body) {
    try {$r=Invoke-WebRequest ($base+$path) -Method Post -Headers $headers -ContentType application/json -Body ($body|ConvertTo-Json -Depth 10) -TimeoutSec 20 -UseBasicParsing;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch {if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Guard {Invoke-RestMethod ($base+'PersonalChannelsFixture/Guard') -Headers $admin}
function Activity {Invoke-RestMethod ($base+'PersonalChannelsFixture/NativeFixtureStreamActivity') -Headers $admin}
function Count($snapshot,$group,$owner) {$value=$snapshot.$group.PSObject.Properties["PrivateNativeVideo_${owner}_client"].Value;if($null -eq $value){return 0};return [int]$value}
function CheckLedger {
    $path=Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/data/data/personal-channels-fixture.json.open-token-owners.json'
    $text=Get-Content -LiteralPath $path -Raw;$ledger=$text|ConvertFrom-Json
    if($ledger.Version -ne 1){throw 'Wrong ledger version'}
    foreach($owner in @('a','b')) {
        $token=$subjects[$owner].OldToken
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($token))).Replace('-','')}finally{$sha.Dispose()}
        if($ledger.Owners.PSObject.Properties[$key].Value -ne $subjects[$owner].UserId -or $text.Contains($token)){throw 'Ledger is not hash-to-stable-owner or contains raw token'}
    }
    return $true
}
function RefreshPlayback($owner) {
    $s=$subjects[$owner]
    $r=Call "Items/$($s.VideoId)/PlaybackInfo" $s.Headers @{UserId=$s.UserId;DeviceId="stale-token-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    if($r.Status -ne 200){throw 'Own playback info failed'}
    $s.PlaySessionId=($r.Text|ConvertFrom-Json).PlaySessionId
    if(-not $s.PlaySessionId){throw 'Missing native play session'}
}
function Prepare($owner) {
    $r=@(Invoke-RestMethod ($base+"PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($subjects[$owner].VideoId)") -Headers $admin)
    if($r.Count -ne 1 -or -not $r[0].OpenToken){throw 'No native token'}
    return [string]$r[0].OpenToken
}
function OwnPositive($phase,$owner,$token) {
    $s=$subjects[$owner]
    $open=Call 'LiveStreams/Open' $s.Headers @{ItemId=[long]$s.VideoId;UserId=$s.UserId;OpenToken=$token;PlaySessionId=$s.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Own Open';Status=$open.Status})
    if($open.Status -ne 200){throw 'Own positive open failed'}
    $live=($open.Text|ConvertFrom-Json).MediaSource.LiveStreamId
    if(-not $live){throw 'No actual native live stream'}
    $meta=Call 'LiveStreams/MediaInfo' $s.Headers @{LiveStreamId=$live}
    $right=$meta.Text.Contains("PrivateNativeVideo_${owner}_client")
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Own MediaInfo';Status=$meta.Status;HasCorrectMarker=$right})
    if($meta.Status -ne 200 -or -not $right){throw 'Own positive metadata failed'}
    $close=Call 'LiveStreams/Close' $s.Headers @{LiveStreamId=$live;PlaySessionId=$s.PlaySessionId}
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Own Close';Status=$close.Status})
    if($close.Status -ne 204){throw 'Own positive close failed'}
}
try {
    $info=Invoke-RestMethod ($base+'System/Info/Public');$beforeGuard=Guard
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $beforeGuard.Ready -or -not $beforeGuard.Enabled -or -not $journal.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')) {
        $u=@($journal.Users|Where-Object Owner -eq $owner)[0];$l=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Stale token test`", Device=`"Isolated`", DeviceId=`"stale-token-$owner`", Version=`"1.0`""} @{Username=$u.Name;Pw=''}
        if($login.Status -ne 200){throw 'Login failed'}
        $session=$login.Text|ConvertFrom-Json
        if($session.User.Id -ne $u.UserId -or $session.User.Policy.IsAdministrator){throw 'Wrong subject'}
        $subjects[$owner]=@{Headers=@{'X-Emby-Token'=$session.AccessToken};UserId=$u.UserId;VideoId=$l.VideoId}
        RefreshPlayback $owner
        $subjects[$owner].OldToken=Prepare $owner
        OwnPositive before $owner $subjects[$owner].OldToken
    }
    $empty=Activity
    if((Count $empty NativeOpenStreams a) -ne 0 -or (Count $empty NativeOpenStreams b) -ne 0){throw 'Pre-restart native table not empty'}
    $ledgerBefore=if($RequireIsolation){CheckLedger}else{$false}
    & $control -Stop
    & $control
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$afterGuard=Guard;if($afterGuard.Ready -and $afterGuard.Enabled){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $afterGuard.Ready -or -not $afterGuard.Enabled -or $afterGuard.BootId -eq $beforeGuard.BootId){throw 'Restart not verified'}
    foreach($owner in @('a','b')){RefreshPlayback $owner}
    # Register the provider using only A's source. B's old token remains unissued
    # in the new guard process, while the same native provider can resolve it.
    $newA=Prepare a
    $ledgerAfter=if($RequireIsolation){CheckLedger}else{$false}
    $positiveEmpty=Activity
    if((Count $positiveEmpty ProviderOpenCalls b) -ne 0){throw 'B source opened during restart setup'}
    foreach($case in @('a-private','b-private','a-no-item')) {
        $actor=if($case -eq 'b-private'){'b'}else{'a'};$s=$subjects[$actor]
        $body=@{UserId=$s.UserId;OpenToken=$subjects.b.OldToken;PlaySessionId=$s.PlaySessionId;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        if($case -ne 'a-no-item'){$body.ItemId=[long]$s.VideoId}
        $before=Activity;$r=Call 'LiveStreams/Open' $s.Headers $body;$after=Activity
        $rows.Add(@{Phase='after restart before B reissue';Actor=$actor;Operation=$case;Status=$r.Status;HasPrivateBMarker=$r.Text.Contains('PrivateNativeVideo_b_client');
            BNativeBefore=(Count $before NativeOpenStreams b);BNativeAfter=(Count $after NativeOpenStreams b);
            BProviderOpenDelta=((Count $after ProviderOpenCalls b)-(Count $before ProviderOpenCalls b))})
        if($RequireIsolation) {
            if($actor -eq 'a' -and ($r.Status -ne 404 -or (Count $after NativeOpenStreams b) -ne (Count $before NativeOpenStreams b) -or (Count $after ProviderOpenCalls b) -ne (Count $before ProviderOpenCalls b))){throw 'Old foreign token caused access or mutation'}
            if($actor -eq 'b') {
                if($r.Status -ne 200){throw 'Owner lost old token continuity'}
                $live=($r.Text|ConvertFrom-Json).MediaSource.LiveStreamId
                $meta=Call 'LiveStreams/MediaInfo' $s.Headers @{LiveStreamId=$live}
                $right=$meta.Text.Contains('PrivateNativeVideo_b_client')
                $rows.Add(@{Phase='after restart before B reissue';Actor='b';Operation='Old owner token MediaInfo';Status=$meta.Status;HasCorrectMarker=$right})
                if($meta.Status -ne 200 -or -not $right){throw 'Old owner stream metadata failed'}
                $close=Call 'LiveStreams/Close' $s.Headers @{LiveStreamId=$live;PlaySessionId=$s.PlaySessionId}
                $rows.Add(@{Phase='after restart before B reissue';Actor='b';Operation='Old owner token Close';Status=$close.Status})
                if($close.Status -ne 204){throw 'Old owner stream close failed'}
            }
        }
    }
    $newB=Prepare b
    $sameB=$newB -eq $subjects.b.OldToken
    if(-not $sameB){throw 'Old B token no longer identifies the same valid native source'}
    OwnPositive after b $subjects.b.OldToken
    OwnPositive after a $newA
    $mutations=@($rows|Where-Object {$_.Phase -eq 'after restart before B reissue' -and $_.Actor -eq 'a' -and ($_.BNativeAfter -ne $_.BNativeBefore -or $_.BProviderOpenDelta -ne 0)})
    $name=if($RequireIsolation){'native-stale-open-token-persisted-results.json'}else{'native-stale-open-token-results.json'}
    @{Completed=$true;Scope='Synthetic local provider; old token after actual restart; no media bytes';RequireIsolation=$RequireIsolation.IsPresent;LedgerHashOwnerGuidBefore=$ledgerBefore;LedgerHashOwnerGuidAfter=$ledgerAfter;RestartVerified=$true;BTokenEqualsReissuedToken=$sameB;NoForeignMutation=($mutations.Count -eq 0);MutationCases=$mutations.Count;Observations=$rows;FinalNativeTable=(Activity)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    Write-Output ("Stale token test completed; observations="+$rows.Count+"; mutation cases="+$mutations.Count)
}catch{
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'bin/native-stale-open-token-incomplete.json') -Encoding UTF8
    throw
}
