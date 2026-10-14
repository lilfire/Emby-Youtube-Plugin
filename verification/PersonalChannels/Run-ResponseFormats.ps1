$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$results=[Collections.Generic.List[object]]::new()
$started=$false;$configured=$false;$session=$null;$original=$null
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=20}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 15}
    Invoke-RestMethod @args
}
function Probe($label,$path,$token,$accept) {
    $headers=@{'X-Emby-Token'=$token;Accept=$accept}
    $status=200;$content='';$type=''
    try {
        $response=Invoke-WebRequest -Uri "$base/$path" -Headers $headers -UseBasicParsing -TimeoutSec 20
        $status=[int]$response.StatusCode;$type=$response.Headers['Content-Type']
        $content=if ($response.Content -is [byte[]]) {[Text.Encoding]::UTF8.GetString($response.Content)} else {[string]$response.Content}
    } catch {if (-not $_.Exception.Response) {throw 'Format request failed before HTTP response'};$status=[int]$_.Exception.Response.StatusCode}
    $private=$content.Contains('Personal Video') -or $content.Contains('Personal Fixture')
    $count=$null
    if ($status -eq 200) {
        if ($type -like '*xml*') {
            $xml=[xml]$content;$count=[int]$xml.SelectSingleNode("//*[local-name()='TotalRecordCount']").InnerText
        } else {$count=($content | ConvertFrom-Json).TotalRecordCount}
    }
    $results.Add(@{Label=$label;Status=$status;ContentType=$type;PrivateMetadata=$private;TotalRecordCount=$count})
    Write-Output "$label : HTTP $status; type=$type; private=$private"
}
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Response formats test", Device="Isolated test", DeviceId="response-format-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $original=(Call "Users/$($session.User.Id)").Policy
    $policy=$original | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $policy.EnableAllChannels=$true
    Call "Users/$($session.User.Id)/Policy" $admin Post $policy | Out-Null
    if (-not (Call "Users/$($session.User.Id)").Policy.EnableAllChannels) {throw 'Policy readback failed'}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1});Prune=$true} | Out-Null
    $configured=$true
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null
    foreach ($format in @(
        @{Label='JSON';Accept='application/json';Suffix=''},
        @{Label='XML Accept';Accept='application/xml';Suffix=''},
        @{Label='XML format';Accept='application/json';Suffix='&format=xml'},
        @{Label='CSV format';Accept='application/json';Suffix='&format=csv'},
        @{Label='JSV format';Accept='application/json';Suffix='&format=jsv'},
        @{Label='MessagePack format';Accept='application/json';Suffix='&format=msgpack'},
        @{Label='JSONP format';Accept='application/json';Suffix='&format=jsonp&callback=fixtureCallback'},
        @{Label='JSONP';Accept='application/json';Suffix='&callback=fixtureCallback'},
        @{Label='CSV Accept';Accept='text/csv';Suffix=''},
        @{Label='MessagePack Accept';Accept='application/x-msgpack';Suffix=''})) {
        Probe ("Owner "+$format.Label) ("Items?UserId=$($auth.UserId)&Recursive=true&SearchTerm=Personal"+$format.Suffix) $auth.Token $format.Accept
        Probe ("Other "+$format.Label) ("Items?UserId=$($session.User.Id)&Recursive=true&SearchTerm=Personal"+$format.Suffix) $session.AccessToken $format.Accept
    }
    foreach ($row in $results | Where-Object {$_.Label.StartsWith('Other')}) {
        if ($row.Status -ne 200 -or $row.PrivateMetadata -or $row.TotalRecordCount -ne 0) {throw ('Alternate-format privacy or count failure: '+$row.Label)}
    }
    foreach ($row in $results | Where-Object {$_.Label.StartsWith('Owner')}) {
        if ($row.Status -ne 200 -or -not $row.PrivateMetadata -or $row.TotalRecordCount -ne 2) {throw ('Owner positive control failed: '+$row.Label)}
    }
    Write-Output 'PASS: 20 format responses parsed; owner has two videos and other user has zero across all variants.'
}
finally {
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/response-format-results.json') -Encoding UTF8
    if ($started) {
        if ($original) {
            Call "Users/$($session.User.Id)/Policy" $admin Post $original | Out-Null
            if (((Call "Users/$($session.User.Id)").Policy | ConvertTo-Json -Depth 15 -Compress) -ne ($original | ConvertTo-Json -Depth 15 -Compress)) {throw 'Policy restoration failed'}
        }
        if ($configured) {Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null}
        if ($session) {Call 'Sessions/Logout' @{'X-Emby-Token'=$session.AccessToken} Post | Out-Null}
        & $control -Stop
    }
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative));if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
