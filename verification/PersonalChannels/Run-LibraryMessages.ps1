param([switch]$RequireProtected)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$results=[Collections.Generic.List[object]]::new()
$sockets=[Collections.Generic.List[object]]::new()
$started=$false;$configured=$false;$session=$null
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=20}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 15}
    Invoke-RestMethod @args
}
function Connect($token,$device) {
    $socket=[Net.WebSockets.ClientWebSocket]::new()
    $cancel=[Threading.CancellationTokenSource]::new(5000)
    try {$socket.ConnectAsync([Uri]($base.Replace('http:','ws:')+'/embywebsocket?api_key='+[Uri]::EscapeDataString($token)+'&deviceId='+$device),$cancel.Token).GetAwaiter().GetResult() | Out-Null}
    finally {$cancel.Dispose()}
    $sockets.Add($socket);return $socket
}
function ReadLibrary($socket) {
    $cancel=[Threading.CancellationTokenSource]::new(8000)
    $buffer=New-Object byte[] 65536
    try {
        while (-not $cancel.IsCancellationRequested) {
            $response=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$cancel.Token).GetAwaiter().GetResult()
            if (-not $response.EndOfMessage) {throw 'Fragmented test message requires a larger collector'}
            $message=[Text.Encoding]::UTF8.GetString($buffer,0,$response.Count) | ConvertFrom-Json
            if ($message.MessageType -eq 'LibraryChanged') {return $message.Data}
        }
        throw 'No LibraryChanged message received'
    } finally {$cancel.Dispose()}
}
function Check($condition,$label) {if (-not $condition) {throw $label};Write-Output "PASS: $label"}
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Library messages test", Device="Isolated test", DeviceId="library-message-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $other=@{'X-Emby-Token'=$session.AccessToken}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1});Prune=$true} | Out-Null
    $configured=$true
    $ownerSocket=Connect $auth.Token 'library-message-owner'
    $otherSocket=Connect $session.AccessToken 'library-message-fixture'
    foreach ($phase in @('Baseline','Protected')) {
        if ($phase -eq 'Protected') {Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null}
        $ids=Call 'PersonalChannelsFixture/Notify' $admin Post @{OwnerUserId=$auth.UserId;OtherUserId=$session.User.Id}
        $ownerData=ReadLibrary $ownerSocket;$otherData=ReadLibrary $otherSocket
        foreach ($field in @('ItemsAdded','ItemsUpdated','ItemsRemoved','FoldersAddedTo','FoldersRemovedFrom','CollectionFolders')) {
            $privateId=if ($field.StartsWith('Items')) {$ids.PrivateId} else {$ids.PrivateChannelId}
            $ownerHas=$privateId -in $ownerData.$field;$otherHas=$privateId -in $otherData.$field
            $publicRemains=if ($field.StartsWith('Items')) {$ids.PublicId -in $otherData.$field} else {$true}
            $results.Add(@{Phase=$phase;Field=$field;OwnerHasPrivate=$ownerHas;OtherHasPrivate=$otherHas;PublicRemains=$publicRemains})
            Write-Output "$phase $field : owner private=$ownerHas; other private=$otherHas; public remains=$publicRemains"
            Check $ownerHas "$phase owner receives private $field positive control"
            Check $publicRemains "$phase public $field remains visible"
            if ($phase -eq 'Baseline') {Check $otherHas "Baseline other user receives unguarded $field"}
            elseif ($RequireProtected) {Check (-not $otherHas) "Protected $field has no private ID for other user"}
        }
    }
}
finally {
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/library-message-results.json') -Encoding UTF8
    foreach ($socket in $sockets) {$socket.Abort();$socket.Dispose()}
    if ($started) {
        if ($configured) {Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null}
        if ($session) {Call 'Sessions/Logout' $other Post | Out-Null}
        & $control -Stop
    }
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative));if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
