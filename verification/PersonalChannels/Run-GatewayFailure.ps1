$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$direct='http://127.0.0.1:18096/emby'
$gateway='http://127.0.0.1:18097/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$checks=[Collections.Generic.List[object]]::new()
function Call($base,$path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=5}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 12}
    Invoke-RestMethod @args
}
function Status($label,$base,$path,$headers,$expected) {
    $status=200
    try {Call $base $path $headers | Out-Null} catch {if (-not $_.Exception.Response) {throw};$status=[int]$_.Exception.Response.StatusCode}
    $checks.Add(@{Label=$label;Status=$status;Expected=$expected})
    if ($status -ne $expected) {throw "$label failed: HTTP $status"}
    Write-Output "$label : HTTP $status"
}
function WaitServer {
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call $direct 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
}
$session=$null
WaitServer
try {
    $session=Call $direct 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Gateway fault test", Device="Isolated test", DeviceId="gateway-fault-test", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $other=@{'X-Emby-Token'=$session.AccessToken}
    Call $direct 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1});Prune=$true} | Out-Null
    $channel=(Call $direct 'Channels').Items | Where-Object Name -eq 'Personal Fixture a'
    $video=(Call $direct "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video").Items | Select-Object -First 1
    $path="Users/$($session.User.Id)/Items/$($video.Id)"
    Status 'Gate refuses inactive privacy control' $gateway $path $other 503
    Call $direct 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null
    Status 'Ready gate preserves owner metadata' $gateway "Users/$($auth.UserId)/Items/$($video.Id)" $admin 200
    Status 'Ready gate refuses other user' $gateway $path $other 404
    & $control -Stop
    $plugin=[IO.Path]::GetFullPath((Join-Path $root 'data/plugins/PersonalChannelsFixture.dll'))
    if (-not $plugin.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe fixture path'}
    Remove-Item -LiteralPath $plugin
    & $control
    WaitServer
    Status 'CONTROL missing plugin exposes metadata upstream' $direct $path $other 200
    Status 'Gate blocks missing plugin' $gateway $path $other 503
    Status 'Gate blocks websocket route with missing plugin' $gateway 'embywebsocket' $other 503
    $socket=[Net.WebSockets.ClientWebSocket]::new()
    $socketCancellation=[Threading.CancellationTokenSource]::new(3000)
    $rejected=$false
    try {$socket.ConnectAsync([Uri]('ws://127.0.0.1:18097/emby/embywebsocket?api_key='+[Uri]::EscapeDataString($session.AccessToken)+'&deviceId=gateway-fault-test'),$socketCancellation.Token).GetAwaiter().GetResult() | Out-Null}
    catch {$rejected=$_.Exception.ToString().Contains('503')}
    finally {$socket.Abort();$socket.Dispose();$socketCancellation.Dispose()}
    $checks.Add(@{Label='Actual websocket handshake is rejected with missing plugin';Rejected503=$rejected})
    if (-not $rejected) {throw 'Websocket handshake was not rejected with 503'}
    & $control -Stop
    Status 'Gate blocks stopped backend' $gateway $path $other 503
}
finally {
    $checks | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/gateway-failure-results.json') -Encoding UTF8
    & $control -Stop
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & $control
    WaitServer
    Call $direct 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null
    if (@((Call $direct 'Channels').Items | Where-Object {$_.Name.StartsWith('Personal Fixture ')}).Count -ne 0) {throw 'Cleanup failed'}
    if ($session) {Call $direct 'Sessions/Logout' @{'X-Emby-Token'=$session.AccessToken} Post | Out-Null}
    & $control -Stop
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe cleanup path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
