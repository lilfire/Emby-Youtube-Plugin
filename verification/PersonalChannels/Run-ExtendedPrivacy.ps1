param([switch]$ThroughGateway)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testRoot = Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base = 'http://127.0.0.1:18096/emby'
$auth = Get-Content -LiteralPath (Join-Path $testRoot 'test-auth.json') -Raw | ConvertFrom-Json
$admin = @{'X-Emby-Token'=$auth.Token}
$results = [Collections.Generic.List[object]]::new()
function Call($path, $headers=$admin, $method='Get', $body=$null) {
    $args = @{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=20}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 15}
    Invoke-RestMethod @args
}
function Probe($label,$path,$headers,$method='Get',$body=$null,$binary=$false) {
    $status=200;$content=$null;$length=0
    try {
        if ($binary) {
            $response=Invoke-WebRequest -Uri "$base/$path" -Headers $headers -Method $method -UseBasicParsing -TimeoutSec 20
            $status=[int]$response.StatusCode;$length=$response.RawContentLength
        } else {$content=Call $path $headers $method $body}
    } catch {if ($null -eq $_.Exception.Response) {throw};$status=[int]$_.Exception.Response.StatusCode}
    $json=if ($null -ne $content) {ConvertTo-Json -InputObject $content -Depth 30 -Compress} else {''}
    $private=$json.Contains('Personal Video') -or $json.Contains('Personal Fixture')
    $results.Add(@{Label=$label;Status=$status;PrivateMetadata=$private;Bytes=$length})
    Write-Host "$label : HTTP $status; private metadata=$private; bytes=$length"
    return $content
}
function ProbeSocket($label,$token,$deviceId='extended-privacy-fixture') {
    $socket=[Net.WebSockets.ClientWebSocket]::new()
    $cancellation=[Threading.CancellationTokenSource]::new(3500)
    $messages=0;$sessionsMessages=0;$private=$false;$errorType=$null
    try {
        $uri=[Uri]($base.Replace('http:','ws:')+'/embywebsocket?api_key='+[Uri]::EscapeDataString($token)+'&deviceId='+[Uri]::EscapeDataString($deviceId))
        $socket.ConnectAsync($uri,$cancellation.Token).GetAwaiter().GetResult() | Out-Null
        $bytes=[Text.Encoding]::UTF8.GetBytes('{"MessageType":"SessionsStart","Data":"0,1000"}')
        $socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$cancellation.Token).GetAwaiter().GetResult() | Out-Null
        if ($deviceId -eq 'extended-privacy-owner') {
            # Trigger a real session change; do not depend on the listener repeating unchanged data.
            Start-Sleep -Milliseconds 150
            Call 'Sessions/Playing/Progress' $admin Post @{ItemId="$id";PlaySessionId=$started.PlaySessionId;PositionTicks=10000000;PlayMethod='DirectPlay';MediaSourceId=$started.MediaSourceId} | Out-Null
        }
        $buffer=New-Object byte[] 65536
        while (-not $cancellation.IsCancellationRequested) {
            $received=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$cancellation.Token).GetAwaiter().GetResult()
            $text=[Text.Encoding]::UTF8.GetString($buffer,0,$received.Count)
            $messages++
            if ($text.Contains('"MessageType":"Sessions"')) {$sessionsMessages++}
            if ($text.Contains('Personal Video') -or $text.Contains('Personal Fixture')) {$private=$true}
        }
    } catch { if (-not $cancellation.IsCancellationRequested) {$errorType=$_.Exception.GetType().Name} }
    finally {$socket.Abort();$socket.Dispose();$cancellation.Dispose()}
    $results.Add(@{Label=$label;Messages=$messages;SessionsMessages=$sessionsMessages;PrivateMetadata=$private;ErrorType=$errorType})
    Write-Host "$label : messages=$messages; sessions messages=$sessionsMessages; private metadata=$private; error=$errorType"
}
$info=Call 'System/Info/Public'
if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong test server'}
$session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Extended privacy test", Device="Isolated test", DeviceId="extended-privacy-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
$outsider=@{'X-Emby-Token'=$session.AccessToken}
$uid=$session.User.Id
$originalPolicy=(Call "Users/$uid").Policy
try {
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=10;LocalMedia=$true});Prune=$true} | Out-Null
    $channels=(Call 'Channels').Items
    $channel=$channels | Where-Object Name -eq 'Personal Fixture a'
    $video=(Call "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video").Items | Select-Object -First 1
    $id=$video.Id
    $image=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $repository 'thumb.png')))
    Invoke-RestMethod -Uri "$base/Items/$id/Images/Primary" -Method Post -Headers $admin -ContentType 'image/png' -Body $image | Out-Null
    Probe 'CONTROL actual image without guard' "Items/$id/Images/Primary" $outsider Get $null $true | Out-Null
    Probe 'CONTROL actual stream without guard' "Videos/$id/stream.mp4?Static=true" $outsider Get $null $true | Out-Null
    $policy=$originalPolicy | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $policy.EnableAllChannels=$false
    $policy.EnabledChannels=@($channels | Where-Object {-not $_.Name.StartsWith('Personal Fixture ')} | ForEach-Object Guid)
    Call "Users/$uid/Policy" $admin Post $policy | Out-Null
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null
    if ($ThroughGateway) {$base='http://127.0.0.1:18097/emby'}
    Probe 'Owner actual image' "Items/$id/Images/Primary" $admin Get $null $true | Out-Null
    Probe 'Other user actual image' "Items/$id/Images/Primary" $outsider Get $null $true | Out-Null
    Probe 'Anonymous actual image' "Items/$id/Images/Primary" @{} Get $null $true | Out-Null
    Probe 'Owner actual stream' "Videos/$id/stream.mp4?Static=true" $admin Get $null $true | Out-Null
    Probe 'Other user actual stream' "Videos/$id/stream.mp4?Static=true" $outsider Get $null $true | Out-Null
    Probe 'Anonymous actual stream' "Videos/$id/stream.mp4?Static=true" @{} Get $null $true | Out-Null
    Probe 'Other user stream HEAD' "Videos/$id/stream.mp4?Static=true" $outsider Head $null $true | Out-Null
    Probe 'Other user HLS manifest' "Videos/$id/master.m3u8?Static=true" $outsider | Out-Null
    Probe 'Other user download' "Items/$id/Download" $outsider Get $null $true | Out-Null
    Probe 'GUID lookup' "Items/$($video.Guid)/PlaybackInfo" $outsider | Out-Null
    foreach ($entry in @(
        @('Global search with own user',"Items?UserId=$uid&Recursive=true&SearchTerm=Personal"),
        @('Global search without user','Items?Recursive=true&SearchTerm=Personal'),
        @('Anonymous global search','Items?Recursive=true&SearchTerm=Personal'),
        @('Channels with own user',"Channels?UserId=$uid"),
        @('Channels without user','Channels'),
        @('Search hints without user','Search/Hints?SearchTerm=Personal'),
        @('Latest without user','Items/Latest'),
        @('User latest',"Users/$uid/Items/Latest"),
        @('User resume',"Users/$uid/Items/Resume"),
        @('AdjacentTo alternative item reference',"Items?UserId=$uid&AdjacentTo=$id&Recursive=true"),
        @('StartItemId alternative item reference',"Items?UserId=$uid&StartItemId=$id&Recursive=true"))) {
        $h=if ($entry[0] -eq 'Anonymous global search') {@{}} else {$outsider}
        Probe $entry[0] $entry[1] $h | Out-Null
    }
    $playback=Call "Items/$id/PlaybackInfo?UserId=$($auth.UserId)"
    if ($playback.PlaySessionId) {
        Probe 'Other user stream with owner play session ID' "Videos/$id/stream.mp4?Static=true&PlaySessionId=$($playback.PlaySessionId)" $outsider Get $null $true | Out-Null
    }
    $started=@{ItemId="$id";MediaSourceId=$playback.MediaSources[0].Id;PlaySessionId=[guid]::NewGuid().ToString('N');PlayMethod='DirectPlay';PositionTicks=0;CanSeek=$true}
    Probe 'Body-only other user playback report' 'Sessions/Playing' $outsider Post $started | Out-Null
    $sessions=Call 'Sessions'
    $otherPlaying=@($sessions | Where-Object {$_.UserId -eq $uid -and $_.NowPlayingItem.Id -eq $id}).Count
    $results.Add(@{Label='Body denial prevents handler side effect';OtherUserPlayingPrivateItem=$otherPlaying})
    Write-Output "Body-only side effect: other user private playback sessions=$otherPlaying"
    Probe 'Other user playback stopped report' 'Sessions/Playing/Stopped' $outsider Post @{ItemId="$id";PlaySessionId=$started.PlaySessionId;PositionTicks=0} | Out-Null
    Probe 'Owner playback report' 'Sessions/Playing' $admin Post $started | Out-Null
    Probe 'Owner sees own private playback in sessions' 'Sessions' $admin | Out-Null
    Probe 'Other user session overview while owner plays private item' 'Sessions' $outsider | Out-Null
    ProbeSocket 'Websocket sessions with normal rights' $session.AccessToken
    $policy.EnableRemoteControlOfOtherUsers=$true
    Call "Users/$uid/Policy" $admin Post $policy | Out-Null
    if (-not (Call "Users/$uid").Policy.EnableRemoteControlOfOtherUsers) {throw 'Remote-control policy readback failed'}
    Probe 'Other user sessions with remote-control permission' 'Sessions' $outsider | Out-Null
    $compressed=@{'X-Emby-Token'=$session.AccessToken;'Accept-Encoding'='gzip'}
    Probe 'Compressed session overview with remote-control permission' 'Sessions' $compressed | Out-Null
    ProbeSocket 'Websocket sessions with remote-control permission' $session.AccessToken
    ProbeSocket 'Owner websocket includes own private playback' $auth.Token 'extended-privacy-owner'
    $ownerSession=(Call 'Sessions' | Where-Object {$_.NowPlayingItem.Id -eq $id} | Select-Object -First 1).Id
    if ($ownerSession) {Probe 'Owner session queue with remote-control permission' "Sessions/PlayQueue?Id=$ownerSession" $outsider | Out-Null}
    $nested=@{ItemId='25';PlaySessionId=[guid]::NewGuid().ToString('N');PlayMethod='DirectPlay';NowPlayingQueue=@(@{Id=[long]$id});PositionTicks=0}
    Probe 'Private ID inside nested playback queue' 'Sessions/Playing' $outsider Post $nested | Out-Null
    $otherSession=(Call 'Sessions' | Where-Object {$_.UserId -eq $uid} | Select-Object -First 1).Id
    if ($otherSession) {Probe 'Other user reads own nested private queue' "Sessions/PlayQueue?Id=$otherSession" $outsider | Out-Null}
    $policy.EnableRemoteControlOfOtherUsers=$false
    Call "Users/$uid/Policy" $admin Post $policy | Out-Null
    if ((Call "Users/$uid").Policy.EnableRemoteControlOfOtherUsers) {throw 'Remote-control disable readback failed'}
    Probe 'Session overview after removing cross-user remote control' 'Sessions' $outsider | Out-Null
    ProbeSocket 'Websocket after removing cross-user remote control' $session.AccessToken
    Call 'Sessions/Playing/Stopped' $outsider Post @{ItemId='25';PlaySessionId=$nested.PlaySessionId;PositionTicks=0} | Out-Null
    Call 'Sessions/Playing/Stopped' $admin Post @{ItemId="$id";PlaySessionId=$started.PlaySessionId;PositionTicks=0} | Out-Null
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1') -Stop
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1')
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 500}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test') {throw 'Restart server check failed'}
    Probe 'After restart: other user direct metadata with automatic guard' "Users/$uid/Items/$id" $outsider | Out-Null
    Probe 'After restart: owner retains actual stream' "Videos/$id/stream.mp4?Static=true" $admin Get $null $true | Out-Null
    Start-Sleep -Seconds 3
    Probe 'Three seconds after restart: other user direct metadata' "Users/$uid/Items/$id" $outsider | Out-Null
    $guard=Call 'PersonalChannelsFixture/Guard'
    $results.Add(@{Label='Guard counters after restart';UrlChecks=$guard.UrlChecks;DtoChecks=$guard.DtoChecks;Denials=$guard.Denials})
}
finally {
    $reportName=if ($ThroughGateway) {'gateway-privacy-results.json'} else {'extended-privacy-results.json'}
    $results | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/$reportName") -Encoding UTF8
    Call "Users/$uid/Policy" $admin Post $originalPolicy | Out-Null
    if (((Call "Users/$uid").Policy | ConvertTo-Json -Depth 15 -Compress) -ne ($originalPolicy | ConvertTo-Json -Depth 15 -Compress)) {throw 'Policy restoration failed'}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null
    if (@((Call 'Channels').Items | Where-Object {$_.Name.StartsWith('Personal Fixture ')}).Count -ne 0) {throw 'Fixture cleanup failed'}
    Call 'Sessions/Logout' $outsider Post | Out-Null
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1') -Stop
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json','data/data/personal-fixture.mp4')) {
        $target=[IO.Path]::GetFullPath((Join-Path $testRoot $relative))
        if (-not $target.StartsWith($testRoot+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe cleanup path'}
        if (Test-Path -LiteralPath $target) {Remove-Item -LiteralPath $target}
    }
}
