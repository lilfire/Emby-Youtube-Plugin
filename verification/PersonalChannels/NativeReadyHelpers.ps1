# Isolated native Original-file investigation, owner or whole-root deletion.
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$rows=[Collections.Generic.List[object]]::new()
$subjects=@{}
$completed=$false
Add-Type -AssemblyName System.Net.Http
$client=[System.Net.Http.HttpClient]::new()
$client.Timeout=[TimeSpan]::FromSeconds(15)
function Request($path,$headers=$admin,$method='Get',$body=$null) {
    # Read success and denial bodies as raw bytes. HTTP errors must not consume
    # the stream before we can verify absence of a private media payload.
    $message=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($method.ToUpperInvariant()),"$base/$path")
    foreach($key in $headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$headers[$key])|Out-Null}
    if($null -ne $body){$message.Content=[System.Net.Http.StringContent]::new(($body|ConvertTo-Json -Depth 10),[Text.Encoding]::UTF8,'application/json')}
    $response=$null
    try{
        $response=$client.SendAsync($message).GetAwaiter().GetResult()
        $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $contentType=[string]$response.Content.Headers.ContentType
        $text=if($contentType -match 'json|text|xml' -or [int]$response.StatusCode -ge 400){[Text.Encoding]::UTF8.GetString($bytes)}else{''}
        $headerText=(@($response.Headers|ForEach-Object {$_.Key+':'+($_.Value -join ',')})+@($response.Content.Headers|ForEach-Object {$_.Key+':'+($_.Value -join ',')})) -join "`n"
        return @{Status=[int]$response.StatusCode;Text=$text;Bytes=$bytes;CacheControl=[string]$response.Headers.CacheControl;
            ETag=[string]$response.Headers.ETag;LastModified=(@($response.Content.Headers|Where-Object Key -eq 'Last-Modified'|ForEach-Object {$_.Value -join ','}) -join '');
            ContentLength=$response.Content.Headers.ContentLength;ContentRange=[string]$response.Content.Headers.ContentRange;
            HeaderNames=@($response.Headers|ForEach-Object {$_.Key})+@($response.Content.Headers|ForEach-Object {$_.Key});
            PrivateAHeader=[Uri]::UnescapeDataString($headerText).Contains('PrivateNativeVideo_a_client');
            PrivateBHeader=[Uri]::UnescapeDataString($headerText).Contains('PrivateNativeVideo_b_client')}
    }catch{
        $script:RequestFailure=@{Path=$path;Method=$method;ErrorCategory=$_.Exception.GetType().Name}
        throw
    }finally{if($response){$response.Dispose()};$message.Dispose()}
}
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $r=Request $path $headers $method $body
    if ($r.Status -notin @(200,204)) {throw "Control HTTP $($r.Status): $path"}
    if ($r.Text) {return $r.Text | ConvertFrom-Json}
}
function Check($label,$path,$headers,$expected,$fileOwner=$null) {
    $r=Request $path $headers
    $row=@{Label=$label;Path=$path;Status=$r.Status;Expected=$expected;ContainsPrivateA=$r.Text.Contains('PrivateNativeVideo_a_client');ContainsPrivateB=$r.Text.Contains('PrivateNativeVideo_b_client')}
    if ($fileOwner) {
        $stream=[IO.MemoryStream]::new([byte[]]$r.Bytes,$false)
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')} finally {$sha.Dispose()}
        $row.PayloadBytes=$stream.Length;$row.MatchesSource=$digest -eq $subjects[$fileOwner].SourceHash
        if (-not $row.MatchesSource -or $stream.Length -le 0) {throw 'Own Original file mismatch'}
    }
    if($expected -eq 404 -and $path.EndsWith('/File')){
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$deniedHash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$r.Bytes)).Replace('-','')}finally{$sha.Dispose()}
        $row.DeniedPayloadBytes=$r.Bytes.Length
        $row.DeniedBodyMatchesPrivateSource=$deniedHash -eq $subjects.a.SourceHash -or $deniedHash -eq $subjects.b.SourceHash
        $row.DeniedBodyLooksLikeMp4=$r.Bytes.Length -ge 12 -and [Text.Encoding]::ASCII.GetString($r.Bytes,4,4) -eq 'ftyp'
        if($row.DeniedBodyMatchesPrivateSource -or $row.DeniedBodyLooksLikeMp4){throw 'Denied response contained native media payload'}
    }
    $rows.Add($row)
    if ($r.Status -ne $expected) {throw "Unexpected status: $label"}
    if ($expected -eq 404 -and ($row.ContainsPrivateA -or $row.ContainsPrivateB)) {throw 'Denied response exposed private name'}
    return $r
}
function ForeignViews($phase) {
    foreach ($actor in @('b','old-a','anonymous')) {
        $headers=if ($actor -eq 'b') {$subjects.b.Headers} elseif ($actor -eq 'old-a') {$subjects.a.Headers} else {@{}}
        foreach ($path in @("Sync/Jobs/$($subjects.a.JobId)","Sync/JobItems?JobId=$($subjects.a.JobId)","Sync/JobItems/$($subjects.a.JobItemId)/File")) {
            Check "$phase $actor private A reference" $path $headers 404 | Out-Null
        }
    }
    Check "$phase B own Original file" "Sync/JobItems/$($subjects.b.JobItemId)/File" $subjects.b.Headers 200 'b' | Out-Null
    foreach ($path in @('Sync/Jobs','Sync/Items/Ready?TargetId=native-owner-ready-a','Sync/Items/Ready?TargetId=native-owner-ready-b')) {
        $r=Check "$phase B list $path" $path $subjects.b.Headers 200
        if ($r.Text.Contains('PrivateNativeVideo_a_client')) {throw 'B list exposed A name'}
        if ($path -ne 'Sync/Items/Ready?TargetId=native-owner-ready-a' -and -not $r.Text.Contains('PrivateNativeVideo_b_client')) {throw 'B own list positive control missing'}
    }
    $native=Call "PersonalChannelsFixture/NativeSyncJobProbe?JobKey=$($subjects.a.JobId)"
    $rows.Add(@{Label="$phase A job native retention";ExistsInNativeManager=$native.Exists;SyntheticNameVerified=$native.SyntheticNameVerified;NativeJobItems=$native.NativeItemCount;NativeReadyItems=$native.ReadyItemCount;ExistingSyntheticOutputFiles=$native.ExistingSyntheticOutputFileCount})
    if($DeleteRoot){ProbeItem "$phase A jobitem direct native retention"}
}
function ProbeItem($label,$requirePositive=$false){
    $native=Call "PersonalChannelsFixture/NativeSyncItemProbe?JobKey=$($subjects.a.JobId)&ItemKey=$($subjects.a.JobItemId)"
    $rows.Add(@{Label=$label;DirectNativeItemExists=$native.Exists;ParentJobExists=$native.ParentJobExists;NativeReadyToTransfer=$native.ReadyToTransfer;NativeStatus=$native.NativeStatus;KnownPrivateSourceVerified=$native.KnownPrivateSourceVerified})
    if($requirePositive -and (-not $native.Exists -or -not $native.ParentJobExists -or -not $native.ReadyToTransfer -or -not $native.KnownPrivateSourceVerified)){throw 'Direct native item probe positive control failed'}
}
