$ErrorActionPreference='Stop'
$rows=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/extended-privacy-results.json') -Raw | ConvertFrom-Json
function Row($label) {
    $found=@($rows | Where-Object Label -eq $label)
    if ($found.Count -ne 1) {throw "Missing or duplicate observation: $label"}
    return $found[0]
}
$assertions=0
foreach($label in @('Other user actual image','Anonymous actual image','Other user actual stream','Anonymous actual stream','Other user stream HEAD','Other user download','GUID lookup','Other user stream with owner play session ID','Body-only other user playback report','Private ID inside nested playback queue','After restart: other user direct metadata with automatic guard','Three seconds after restart: other user direct metadata')) {
    $value=Row $label
    if ($value.Status -ne 404 -or $value.PrivateMetadata -or $value.Bytes -gt 0) {throw "Private access was not blocked: $label"}
    $assertions++
}
foreach($label in @('CONTROL actual image without guard','CONTROL actual stream without guard','Owner actual image','Owner actual stream','After restart: owner retains actual stream')) {
    $value=Row $label
    if ($value.Status -ne 200 -or $value.Bytes -le 0) {throw "Positive byte control failed: $label"}
    $assertions++
}
foreach($label in @('Other user sessions with remote-control permission','Compressed session overview with remote-control permission','Global search without user','Channels without user')) {
    $value=Row $label
    if ($value.Status -ne 200 -or $value.PrivateMetadata) {throw "Aggregate data leak: $label"}
    $assertions++
}
$socket=Row 'Websocket sessions with remote-control permission'
if ($socket.SessionsMessages -lt 1 -or $socket.PrivateMetadata -or $socket.ErrorType) {throw 'Websocket negative control did not receive clean sessions'}
$assertions++
$ownerSocket=Row 'Owner websocket includes own private playback'
if ($ownerSocket.SessionsMessages -lt 1 -or -not $ownerSocket.PrivateMetadata -or $ownerSocket.ErrorType) {throw 'Owner websocket positive control failed'}
$assertions++
if (-not (Row 'Owner sees own private playback in sessions').PrivateMetadata) {throw 'Owner session positive control failed'}
$assertions++
if ((Row 'Body denial prevents handler side effect').OtherUserPlayingPrivateItem -ne 0) {throw 'A denied body request still mutated the session'}
$assertions++
$report=@{Assertions=$assertions;Passed=$true;ServerVersion='4.10.1.0';Scope='Synthetic isolated API and byte tests, with plugin present; not native TV/mobile application tests';CompletedUtc=[DateTime]::UtcNow.ToString('o')}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/privacy-verification.json') -Encoding UTF8
Write-Output "PASS: $assertions assertions, including positive owner controls and received websocket messages."
