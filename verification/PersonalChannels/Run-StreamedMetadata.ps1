param([switch]$RequireProtected)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$results=[Collections.Generic.List[object]]::new()
$started=$false;$configured=$false;$session=$null
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=20}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 15}
    Invoke-RestMethod @args
}
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Streamed metadata test", Device="Isolated test", DeviceId="streamed-metadata-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $other=@{'X-Emby-Token'=$session.AccessToken}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1});Prune=$true} | Out-Null
    $configured=$true
    foreach ($phase in @('Baseline','Protected')) {
        if ($phase -eq 'Protected') {Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null}
        foreach ($style in @('json','xml','soap')) {
            foreach ($role in @(@{Name='Owner';Headers=$admin},@{Name='Other';Headers=$other})) {
                $response=Invoke-WebRequest -Uri "$base/PersonalChannelsFixture/StreamedMetadata?Style=$style" -Headers $role.Headers -UseBasicParsing -TimeoutSec 20
                $content=if ($response.Content -is [byte[]]) {[Text.Encoding]::UTF8.GetString($response.Content)} else {[string]$response.Content}
                $private=$content.Contains('Personal Video Stream Control');$public=$content.Contains('Fixture Video 1')
                if ($style -eq 'soap') {
                    $parsed=[xml]$content;$didl=[xml]$parsed.SelectSingleNode("//*[local-name()='Result']").InnerText
                    $total=[int]$parsed.SelectSingleNode("//*[local-name()='TotalMatches']").InnerText
                    $count=$didl.SelectNodes("//*[local-name()='item']").Count
                    if ([int]$parsed.SelectSingleNode("//*[local-name()='NumberReturned']").InnerText -ne $count) {throw 'SOAP count does not match returned items'}
                }
                elseif ($style -eq 'xml') {$parsed=[xml]$content;$total=[int]$parsed.QueryResult.TotalRecordCount;$count=@($parsed.QueryResult.Items.BaseItemDto).Count}
                else {$parsed=$content | ConvertFrom-Json;$total=$parsed.TotalRecordCount;$count=$parsed.Items.Count}
                $row=@{Phase=$phase;Style=$style;Role=$role.Name;Private=$private;Public=$public;Count=$count;Total=$total;Status=[int]$response.StatusCode}
                $results.Add($row);Write-Output ($row | ConvertTo-Json -Compress)
                if (-not $public) {throw 'Public streamed metadata was lost'}
                if ($phase -eq 'Baseline' -or $role.Name -eq 'Owner') {if (-not $private -or $count -ne 2 -or $total -ne 2) {throw 'Positive streamed metadata control failed'}}
                elseif ($RequireProtected) {if ($private -or $count -ne 1 -or $total -ne 1) {throw 'Streamed metadata privacy leak'}}
            }
        }
    }
}
finally {
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/streamed-metadata-results.json') -Encoding UTF8
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
