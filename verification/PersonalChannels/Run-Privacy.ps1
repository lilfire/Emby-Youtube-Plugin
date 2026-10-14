$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testRoot = Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base = 'http://127.0.0.1:18096/emby'
$auth = Get-Content -LiteralPath (Join-Path $testRoot 'test-auth.json') -Raw | ConvertFrom-Json
$session = Get-Content -LiteralPath (Join-Path $testRoot 'privacy-session.json') -Raw | ConvertFrom-Json
$admin = @{ 'X-Emby-Token' = $auth.Token }
$outsider = @{ 'X-Emby-Token' = $session.AccessToken }
$userId = $session.User.Id
$checks = [Collections.Generic.List[object]]::new()
function Call($path, $headers = $admin, $method = 'Get', $body = $null) {
    $arguments = @{ Uri = "$base/$path"; Headers = $headers; Method = $method }
    if ($null -ne $body) { $arguments.ContentType = 'application/json'; $arguments.Body = ConvertTo-Json -InputObject $body -Depth 15 }
    Invoke-RestMethod @arguments
}
function Status($path, $headers, $expected, $label, $method = 'Get', $body = $null) {
    $actual = 200
    try { Call $path $headers $method $body | Out-Null }
    catch { if ($null -eq $_.Exception.Response) { throw }; $actual = [int]$_.Exception.Response.StatusCode }
    $checks.Add(@{ Label = $label; Expected = $expected; Actual = $actual })
    if ($actual -ne $expected) { throw "FAIL: $label (HTTP $actual, expected $expected)" }
    Write-Output "PASS: $label (HTTP $actual)"
}
$info = Call 'System/Info/Public'
if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') { throw 'Refusing to test a different server.' }
$originalPolicy = (Call "Users/$userId").Policy
try {
    Call 'PersonalChannelsFixture/Configure' $admin Post @{ Profiles = @(@{ Owner = 'a'; Revision = 1 }); Prune = $true } | Out-Null
    $channels = (Call 'Channels').Items
    $channel = $channels | Where-Object Name -eq 'Personal Fixture a'
    $video = (Call "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video").Items | Select-Object -First 1
    Status "Users/$userId/Items/$($video.Id)" $outsider 200 'Control: direct metadata is exposed before guard'
    Status "Items/$($video.Id)/PlaybackInfo?UserId=$userId" $outsider 200 'Control: playback information is exposed before guard'
    $policy = $originalPolicy | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $policy.EnableAllChannels = $false
    $policy.EnabledChannels = @($channels | Where-Object { -not $_.Name.StartsWith('Personal Fixture ') } | ForEach-Object Guid)
    Call "Users/$userId/Policy" $admin Post $policy | Out-Null
    $readBack = (Call "Users/$userId").Policy
    if ($readBack.EnableAllChannels -or $channel.Guid -in $readBack.EnabledChannels) { throw 'Channel policy readback failed.' }
    $search = Call "Items?UserId=$userId&Recursive=true&SearchTerm=unique_a" $outsider
    if ($search.Items.Count -ne 0) { throw 'Channel policy does not hide global search.' }
    $checks.Add(@{Label='Channel policy hides ordinary global search and is read back';Expected=0;Actual=$search.Items.Count})
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null
    Status "Users/$($auth.UserId)/Items/$($video.Id)" $admin 200 'Owner retains metadata access'
    Status "Items/$($video.Id)/PlaybackInfo?UserId=$($auth.UserId)" $admin 200 'Owner retains playback information'
    Status "Users/$userId/Items/$($video.Id)" $outsider 404 'Other user cannot fetch direct metadata'
    Status "Items/$($video.Id)/PlaybackInfo?UserId=$userId" $outsider 404 'Other user cannot fetch playback information'
    Status "Items/$($video.Id)/PlaybackInfo" $outsider 404 'POST playback information is denied' Post @{UserId=$userId}
    Status "Items?UserId=$userId&ParentId=$($channel.Id)&Recursive=true" $outsider 404 'Known parent ID does not bypass ownership'
    Status "Users/$userId/Items/Latest?ParentId=$($channel.Id)" $outsider 404 'Latest with known parent ID is denied'
    Status "Items?UserId=$userId&Ids=$($video.Id)" $outsider 404 'Bulk item lookup is denied'
    Status "Users/$($auth.UserId)/Items/$($video.Id)" $outsider 404 'Spoofed user ID in path is denied'
    Status "Items?UserId=$($auth.UserId)&Recursive=true&SearchTerm=unique_a" $outsider 404 'Spoofed user ID in global search is denied'
    Status "Items/$($video.Id)/Images/Primary" @{} 404 'Anonymous private image request is rejected'
    Status "Items/$($video.Id)" @{} 404 'Anonymous private item request is rejected'
    $fake = @{ 'X-Emby-Token'=$session.AccessToken; Authorization=('MediaBrowser UserId="'+$auth.UserId+'"') }
    Status "Users/$($auth.UserId)/Items/$($video.Id)" $fake 404 'Authorization header user ID cannot override token owner'
    Status "Users/$userId/Items/25" $outsider 200 'Unrelated public fixture remains available'
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$userId} | Out-Null
    Status "Users/$userId/Items/$($video.Id)" $outsider 200 'Ordinary non-admin owner passes ownership guard'
    Status "Users/$($auth.UserId)/Items/$($video.Id)" $admin 404 'Admin status alone does not bypass fixture ownership'
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=2});Prune=$true} | Out-Null
    $added = (Call "Items?UserId=$($auth.UserId)&ParentId=$($channel.Id)&Recursive=true&SearchTerm=added_a").Items | Select-Object -First 1
    if ($null -eq $added) { throw 'New synthetic video was not materialized.' }
    Status "Users/$userId/Items/$($added.Id)" $outsider 404 'New video inherits protection without rebuilding owner map'
    $report = @{ServerVersion=$info.Version;Checks=$checks;Guard=Call 'PersonalChannelsFixture/Guard';Limitations=@('Synthetic API test only; no TV/mobile app or real playback test','No complete audit of streaming sessions, websocket, all aggregate routes, or body-only requests','Image has no actual image bytes; this verifies request rejection only','Guard is runtime-only and does not implement production fail-closed startup')}
    $report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/privacy-results.json') -Encoding UTF8
    Write-Output ("Completed {0} privacy checks." -f $checks.Count)
}
finally {
    Call "Users/$userId/Policy" $admin Post $originalPolicy | Out-Null
    $restored = (Call "Users/$userId").Policy
    if (($restored | ConvertTo-Json -Depth 15 -Compress) -ne ($originalPolicy | ConvertTo-Json -Depth 15 -Compress)) { throw 'Policy restoration verification failed.' }
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null
    if (@((Call 'Channels').Items | Where-Object { $_.Name.StartsWith('Personal Fixture ') }).Count -ne 0) { throw 'Fixture cleanup verification failed.' }
    Call 'Sessions/Logout' $outsider Post | Out-Null
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1') -Stop
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json','privacy-session.json')) {
        $target = [IO.Path]::GetFullPath((Join-Path $testRoot $relative))
        if (-not $target.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar)) { throw 'Unsafe cleanup path.' }
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
    }
}
