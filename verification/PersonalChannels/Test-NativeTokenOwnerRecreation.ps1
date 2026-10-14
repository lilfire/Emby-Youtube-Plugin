$ErrorActionPreference='Stop'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$statePath=Join-Path $PSScriptRoot 'bin/native-client-state.json'
$state=Get-Content $statePath -Raw|ConvertFrom-Json
$control=Join-Path $PSScriptRoot '../EmbyFixture/Start-IsolatedServer.ps1'
$rows=[Collections.Generic.List[object]]::new()
$subjects=@{}
function Request($path,$headers,$method='Post',$body=$null) {
    $args=@{Uri=$base+$path;Headers=$headers;Method=$method;TimeoutSec=20;UseBasicParsing=$true}
    if($null -ne $body){$args.ContentType='application/json';$args.Body=$body|ConvertTo-Json -Depth 12}
    try{$r=Invoke-WebRequest @args;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Guard {Invoke-RestMethod ($base+'PersonalChannelsFixture/Guard') -Headers $admin}
function Activity {Invoke-RestMethod ($base+'PersonalChannelsFixture/NativeFixtureStreamActivity') -Headers $admin}
function Count($snapshot,$group,$owner){$v=$snapshot.$group.PSObject.Properties["PrivateNativeVideo_${owner}_client"].Value;if($null -eq $v){return 0};return [int]$v}
function Login($name,$expected,$device) {
    $r=Request 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Owner recreation test`", Device=`"Isolated`", DeviceId=`"$device`", Version=`"1.0`""} Post @{Username=$name;Pw=''}
    if($r.Status -ne 200){throw 'Synthetic login failed'}
    $data=$r.Text|ConvertFrom-Json
    if($data.User.Id -ne $expected -or $data.User.Policy.IsAdministrator){throw 'Wrong subject'}
    return @{'X-Emby-Token'=$data.AccessToken}
}
function Positive($phase,$owner) {
    $s=$subjects[$owner]
    $play=Request "Items/$($s.VideoId)/PlaybackInfo" $s.Headers Post @{UserId=$s.UserId;DeviceId="owner-recreate-$owner";IsPlayback=$true;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    if($play.Status -ne 200){throw 'Own playback info failed'}
    $s.PlaySessionId=($play.Text|ConvertFrom-Json).PlaySessionId
    $source=@(Invoke-RestMethod ($base+"PersonalChannelsFixture/NativeFixtureDynamicSource?ItemKey=$($s.VideoId)") -Headers $admin)
    if($source.Count -ne 1 -or -not $source[0].OpenToken){throw 'No native source'}
    $s.OpenToken=$source[0].OpenToken
    $open=Request 'LiveStreams/Open' $s.Headers Post @{ItemId=[long]$s.VideoId;UserId=$s.UserId;PlaySessionId=$s.PlaySessionId;OpenToken=$s.OpenToken;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Own Open';Status=$open.Status})
    if($open.Status -ne 200){throw 'Positive native open failed'}
    $live=($open.Text|ConvertFrom-Json).MediaSource.LiveStreamId
    $meta=Request 'LiveStreams/MediaInfo' $s.Headers Post @{LiveStreamId=$live}
    $right=$meta.Text.Contains("PrivateNativeVideo_${owner}_client")
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Own MediaInfo';Status=$meta.Status;HasCorrectMarker=$right})
    if($meta.Status -ne 200 -or -not $right){throw 'Positive metadata failed'}
    $close=Request 'LiveStreams/Close' $s.Headers Post @{LiveStreamId=$live;PlaySessionId=$s.PlaySessionId}
    $rows.Add(@{Phase=$phase;Actor=$owner;Operation='Own Close';Status=$close.Status})
    if($close.Status -ne 204){throw 'Positive close failed'}
}
function CheckOldOwner($phase) {
    foreach($actor in @('b','recreated-a','deleted-a')) {
        $headers=if($actor -eq 'deleted-a'){$subjects.a.Headers}else{$subjects[$actor].Headers}
        $userId=if($actor -eq 'deleted-a'){$subjects.a.UserId}else{$subjects[$actor].UserId}
        $before=Activity
        $r=Request 'LiveStreams/Open' $headers Post @{UserId=$userId;OpenToken=$subjects.a.OpenToken;EnableDirectPlay=$true;EnableDirectStream=$true;EnableTranscoding=$true}
        $after=Activity
        $delta=(Count $after ProviderOpenCalls a)-(Count $before ProviderOpenCalls a)
        $nativeDelta=(Count $after NativeOpenStreams a)-(Count $before NativeOpenStreams a)
        $marker=$r.Text.Contains('PrivateNativeVideo_a_client')
        $rows.Add(@{Phase=$phase;Actor=$actor;Operation='Deleted owner token without ItemId';Status=$r.Status;AProviderOpenDelta=$delta;ANativeStreamDelta=$nativeDelta;HasPrivateAMarker=$marker})
        $expected=if($actor -eq 'deleted-a'){401}else{404}
        if($r.Status -ne $expected -or $delta -ne 0 -or $nativeDelta -ne 0 -or $marker){throw 'Deleted owner token escaped isolation'}
    }
}
try {
    $info=Invoke-RestMethod ($base+'System/Info/Public');$initialGuard=Guard
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $initialGuard.Ready -or -not $initialGuard.Enabled -or -not $state.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')) {
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $subjects[$owner]=@{Headers=(Login $u.Name $u.UserId "owner-recreate-$owner");UserId=$u.UserId;VideoId=$l.VideoId;Name=$u.Name}
        Positive before $owner
    }
    $deleted=Request "Users/$($subjects.a.UserId)" $admin Delete
    if($deleted.Status -notin @(200,204)){throw 'Test owner deletion failed'}
    $remaining=Invoke-RestMethod ($base+'Users') -Headers $admin
    if(@($remaining|Where-Object Id -eq $subjects.a.UserId).Count){throw 'Deleted owner still present'}
    $created=(Request 'Users/New' $admin Post @{Name=$subjects.a.Name}).Text|ConvertFrom-Json
    if(-not $created.Id -or $created.Id -eq $subjects.a.UserId -or $created.Policy.IsAdministrator -or $created.Name -ne $subjects.a.Name){throw 'Recreated identity was not distinct'}
    $state.Users+=@([pscustomobject]@{Owner='recreated-a';Name=$created.Name;UserId=$created.Id})
    $state|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $statePath -Encoding UTF8
    $policy=$created.Policy;$policy.EnableAllFolders=$false;$policy.EnabledFolders=@();$policy.EnableAllChannels=$false;$policy.EnabledChannels=@()
    if((Request "Users/$($created.Id)/Policy" $admin Post $policy).Status -notin @(200,204)){throw 'Recreated account policy failed'}
    $subjects['recreated-a']=@{Headers=(Login $created.Name $created.Id 'owner-recreate-new-a');UserId=$created.Id}
    CheckOldOwner 'deleted/recreated before restart'
    Positive 'other owner after deletion' b
    & $control -Stop
    & $control
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do{try{$g=Guard;if($g.Enabled -and $g.Ready){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $g.Ready -or -not $g.Enabled -or $g.BootId -eq $initialGuard.BootId){throw 'Restart not verified'}
    Positive 'other owner after restart' b
    CheckOldOwner 'deleted/recreated after restart'
    $ledger=Get-Content (Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated/data/data/personal-channels-fixture.json.open-token-owners.json') -Raw|ConvertFrom-Json
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($subjects.a.OpenToken))).Replace('-','')}finally{$sha.Dispose()}
    $kept=$ledger.Owners.PSObject.Properties[$hash].Value -eq $subjects.a.UserId
    if(-not $kept){throw 'Old owner GUID was replaced in token ledger'}
    $final=Activity
    if((Count $final NativeOpenStreams a) -ne 0 -or (Count $final NativeOpenStreams b) -ne 0){throw 'Unexpected active fixture streams'}
    @{Completed=$true;Scope='Native synthetic local stream refs; deleted owner and same-name account; no media bytes';SameNameDifferentGuid=$true;DeletedOwnerAbsentReadback=$true;OldOwnerGuidPreserved=$kept;RestartVerified=$true;Observations=$rows;FinalNativeTable=$final}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/native-token-owner-recreation-results.json') -Encoding UTF8
    Write-Output ("Token owner recreation test completed; observations="+$rows.Count)
}catch{
    @{Completed=$false;ErrorCategory=$_.Exception.GetType().Name;Observations=$rows}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $PSScriptRoot 'bin/native-token-owner-recreation-incomplete.json') -Encoding UTF8
    throw
}
