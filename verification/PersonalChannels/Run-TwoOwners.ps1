$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$checks=[Collections.Generic.List[string]]::new()
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 15}
    Invoke-RestMethod @args
}
function Check($condition,$label) {if (-not $condition) {throw $label};$checks.Add($label);Write-Output "PASS: $label"}
function Status($path,$headers,$expected,$label) {
    $status=200;try {Call $path $headers | Out-Null} catch {if (-not $_.Exception.Response) {throw};$status=[int]$_.Exception.Response.StatusCode}
    Check ($status -eq $expected) "$label (HTTP $status)"
}
$info=Call 'System/Info/Public'
if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
$session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Two owners test", Device="Isolated test", DeviceId="two-owners-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
$other=@{'X-Emby-Token'=$session.AccessToken};$uid=$session.User.Id
$originalAdmin=(Call "Users/$($auth.UserId)").Policy
$originalOther=(Call "Users/$uid").Policy
try {
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1},@{Owner='b';Revision=1});Prune=$true} | Out-Null
    $channels=(Call 'Channels').Items
    $a=$channels | Where-Object Name -eq 'Personal Fixture a';$b=$channels | Where-Object Name -eq 'Personal Fixture b'
    $aVideos=(Call "Items?ParentId=$($a.Id)&Recursive=true&IncludeItemTypes=Video&Fields=ProviderIds").Items
    $bVideos=(Call "Items?ParentId=$($b.Id)&Recursive=true&IncludeItemTypes=Video&Fields=ProviderIds").Items
    $sameA=$aVideos | Where-Object {$_.ProviderIds.YouTube -eq 'shared00001'}
    $sameB=$bVideos | Where-Object {$_.ProviderIds.YouTube -eq 'shared00001'}
    Check ($sameA.Id -ne $sameB.Id) 'Shared YouTube video has distinct database identity per owner'
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;OwnerUserIds=@{a=$auth.UserId;b=$uid}} | Out-Null
    Status "Users/$($auth.UserId)/Items/$($sameA.Id)" $admin 200 'A can read own shared video'
    Status "Users/$uid/Items/$($sameB.Id)" $other 200 'B can read own shared video'
    Status "Users/$uid/Items/$($sameA.Id)" $other 404 'B cannot read A copy'
    Status "Users/$($auth.UserId)/Items/$($sameB.Id)" $admin 404 'A cannot read B copy despite admin status'
    foreach ($entry in @(@($auth.UserId,$originalAdmin,$a),@($uid,$originalOther,$b))) {
        $policy=$entry[1] | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        $policy.EnableAllChannels=$false
        $policy.EnabledChannels=@($channels | Where-Object {-not $_.Name.StartsWith('Personal Fixture ')} | ForEach-Object Guid)+@($entry[2].Guid)
        Call "Users/$($entry[0])/Policy" $admin Post $policy | Out-Null
        $readBack=(Call "Users/$($entry[0])").Policy
        Check (-not $readBack.EnableAllChannels -and $entry[2].Guid -in $readBack.EnabledChannels) 'Owner-specific channel policy is read back'
    }
    $aSearch=(Call "Items?UserId=$($auth.UserId)&Recursive=true&SearchTerm=Personal%20Video" $admin).Items
    $bSearch=(Call "Items?UserId=$uid&Recursive=true&SearchTerm=Personal%20Video" $other).Items
    Check ($aSearch.Count -eq 2 -and @($aSearch | Where-Object {$_.Id -in $bVideos.Id}).Count -eq 0) 'A search returns only A videos'
    Check ($bSearch.Count -eq 2 -and @($bSearch | Where-Object {$_.Id -in $aVideos.Id}).Count -eq 0) 'B search returns only B videos'
    $policy=(Call "Users/$uid").Policy;$policy.EnableAllChannels=$true
    Call "Users/$uid/Policy" $admin Post $policy | Out-Null
    $search=Call "Items?UserId=$uid&Recursive=true&SearchTerm=Personal%20Video" $other
    Check ($search.Items.Count -eq 2 -and $search.TotalRecordCount -eq 2 -and @($search.Items | Where-Object {$_.Id -in $aVideos.Id}).Count -eq 0) 'Server output guard protects B even with all channels enabled'
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=2},@{Owner='b';Revision=2});Prune=$true} | Out-Null
    $newA=(Call "Items?UserId=$($auth.UserId)&ParentId=$($a.Id)&Recursive=true&SearchTerm=added_a" $admin).Items[0]
    $newB=(Call "Items?UserId=$uid&ParentId=$($b.Id)&Recursive=true&SearchTerm=added_b" $other).Items[0]
    Status "Users/$uid/Items/$($newA.Id)" $other 404 'New A video inherits A ownership'
    Status "Users/$uid/Items/$($newB.Id)" $other 200 'New B video inherits B ownership'
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1') -Stop
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1')
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    Status "Users/$uid/Items/$($sameB.Id)" $other 200 'B ownership survives restart'
    Status "Users/$uid/Items/$($sameA.Id)" $other 404 'A isolation survives restart'
}
finally {
    $checks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/two-owners-results.json') -Encoding UTF8
    foreach ($entry in @(@($auth.UserId,$originalAdmin),@($uid,$originalOther))) {
        Call "Users/$($entry[0])/Policy" $admin Post $entry[1] | Out-Null
        if (((Call "Users/$($entry[0])").Policy | ConvertTo-Json -Depth 15 -Compress) -ne ($entry[1] | ConvertTo-Json -Depth 15 -Compress)) {throw 'Policy restoration failed'}
    }
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null
    Call 'Sessions/Logout' $other Post | Out-Null
    & (Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1') -Stop
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative));if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
