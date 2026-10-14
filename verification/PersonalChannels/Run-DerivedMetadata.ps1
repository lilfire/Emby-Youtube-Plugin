param([switch]$RequireProtected)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$results=[Collections.Generic.List[object]]::new()
$started=$false;$configured=$false;$session=$null;$original=$null
$metadataIds=@{a=@{};b=@{}}
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=20}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 20}
    Invoke-RestMethod @args
}
function Probe($phase,$role,$label,$path,$token) {
    $status=200;$content=''
    try {
        $response=Invoke-WebRequest -Uri "$base/$path" -Headers @{'X-Emby-Token'=$token} -UseBasicParsing -TimeoutSec 20
        $content=if ($response.Content -is [byte[]]) {[Text.Encoding]::UTF8.GetString($response.Content)} else {[string]$response.Content}
    } catch {if (-not $_.Exception.Response) {throw 'Metadata request failed before HTTP response'};$status=[int]$_.Exception.Response.StatusCode}
    $hasA=$content.Contains('PrivateFixtureGenre_a') -or $content.Contains('PrivateFixtureStudio_a') -or $content.Contains('PrivateFixtureTag_a')
    $hasB=$content.Contains('PrivateFixtureGenre_b') -or $content.Contains('PrivateFixtureStudio_b') -or $content.Contains('PrivateFixtureTag_b')
    $shared=$content.Contains('SharedFixture')
    $total=$null;$counts=@();$names=@()
    if ($status -eq 200) {
        if ($content.TrimStart().StartsWith('<')) {
            $xml=[xml]$content
            $total=[int]$xml.SelectSingleNode("//*[local-name()='TotalRecordCount']").InnerText
            $names=@($xml.SelectNodes("//*[local-name()='Items']/*") | ForEach-Object {$_.SelectSingleNode("*[local-name()='Name']").InnerText})
        } else {
            $data=$content | ConvertFrom-Json
            $total=$data.TotalRecordCount
            $names=@($data.Items | ForEach-Object Name)
            $counts=@($data.Items | Where-Object Name -like 'SharedFixture*' | ForEach-Object { $_ | Select-Object Name,ChildCount,MovieCount,EpisodeCount,ItemCount })
        }
    }
    if ($label.StartsWith('Genres')) {$content | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/derived-$phase-$role-$($label.Replace(' ','-').Replace('/','-')).txt") -Encoding UTF8}
    $results.Add(@{Phase=$phase;Role=$role;Label=$label;Status=$status;HasA=$hasA;HasB=$hasB;Shared=$shared;Total=$total;Names=$names;Counts=$counts})
    Write-Output "$phase $role $label : HTTP $status; A=$hasA; B=$hasB"
}
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Derived metadata test", Device="Isolated test", DeviceId="derived-metadata-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $original=(Call "Users/$($session.User.Id)").Policy
    $policy=$original | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $policy.EnableAllChannels=$true
    Call "Users/$($session.User.Id)/Policy" $admin Post $policy | Out-Null
    if (-not (Call "Users/$($session.User.Id)").Policy.EnableAllChannels) {throw 'Policy readback failed'}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1},@{Owner='b';Revision=1});Prune=$true} | Out-Null
    $configured=$true
    $channels=(Call 'Channels').Items
    foreach ($owner in @('a','b')) {
        $channel=$channels | Where-Object Name -eq "Personal Fixture $owner"
        $videos=(Call "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video").Items
        foreach ($video in $videos) {
            $readBack=Call "Users/$($auth.UserId)/Items/$($video.Id)?Fields=Genres,Studios,Tags"
            if ("PrivateFixtureGenre_$owner" -notin $readBack.GenreItems.Name -or "PrivateFixtureTag_$owner" -notin $readBack.TagItems.Name -or "PrivateFixtureStudio_$owner" -notin $readBack.Studios.Name) {throw 'Metadata readback failed'}
            $metadataIds[$owner]=@{Genres=($readBack.GenreItems | Where-Object Name -eq "PrivateFixtureGenre_$owner").Id;Studios=($readBack.Studios | Where-Object Name -eq "PrivateFixtureStudio_$owner").Id;Tags=($readBack.TagItems | Where-Object Name -eq "PrivateFixtureTag_$owner").Id}
        }
    }
    Call 'PersonalChannelsFixture/Surface' | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/derived-metadata-surface.json') -Encoding UTF8
    foreach ($phase in @('Baseline','Protected')) {
        if ($phase -eq 'Protected') {Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;OwnerUserIds=@{a=$auth.UserId;b=$session.User.Id}} | Out-Null}
        foreach ($role in @(@{Name='A';UserId=$auth.UserId;Token=$auth.Token},@{Name='B';UserId=$session.User.Id;Token=$session.AccessToken})) {
            foreach ($route in @('Genres','Studios','Tags','Items/Filters','Items/Filters2')) {
                Probe $phase $role.Name "$route with user" "$route`?UserId=$($role.UserId)&IncludeItemTypes=Video" $role.Token
                Probe $phase $role.Name "$route without user" "$route`?IncludeItemTypes=Video" $role.Token
            }
            if ($phase -eq 'Baseline') {
                foreach ($category in @('Genres','Studios','Tags')) {Probe $phase $role.Name "BaselineXML $category" "$category`?UserId=$($role.UserId)&format=xml" $role.Token}
            }
            if ($phase -eq 'Protected') {
                foreach ($category in @(@{Route='Genres';Name='Genre'},@{Route='Studios';Name='Studio'},@{Route='Tags';Name='Tag'})) {
                    $otherId=if ($role.Name -eq 'A') {$session.User.Id} else {$auth.UserId}
                    Probe $phase $role.Name "Spoof $($category.Route)" "$($category.Route)`?UserId=$otherId" $role.Token
                    Probe $phase $role.Name "XML $($category.Route)" "$($category.Route)`?UserId=$($role.UserId)&format=xml" $role.Token
                    Probe $phase $role.Name "Shared $($category.Route)" "$($category.Route)`?UserId=$($role.UserId)&Fields=ItemCounts" $role.Token
                    Probe $phase $role.Name "Page0 $($category.Route)" "$($category.Route)`?UserId=$($role.UserId)&SortBy=SortName&StartIndex=0&Limit=1" $role.Token
                    Probe $phase $role.Name "Page1 $($category.Route)" "$($category.Route)`?UserId=$($role.UserId)&SortBy=SortName&StartIndex=1&Limit=1" $role.Token
                    foreach ($owner in @('a','b')) {
                        Probe $phase $role.Name "Lookup-$owner $($category.Route)" "$($category.Route)/PrivateFixture$($category.Name)_$owner`?UserId=$($role.UserId)" $role.Token
                        Probe $phase $role.Name "Id-$owner $($category.Route)" "Users/$($role.UserId)/Items/$($metadataIds[$owner][$category.Route])" $role.Token
                    }
                }
            }
        }
    }
    $baseline=@($results | Where-Object { $_.Phase -eq 'Baseline' -and $_.HasA -and $_.HasB })
    (Call 'PersonalChannelsFixture/Guard').MetadataIdentities | ForEach-Object {Write-Output $_}
    Write-Output ('Metadata query hooks invoked: '+(Call 'PersonalChannelsFixture/Guard').MetadataQueries)
    if ($baseline.Count -eq 0) {throw 'No positive metadata aggregate controls'}
    $leaks=@($results | Where-Object { $_.Phase -eq 'Protected' -and (($_.Role -eq 'A' -and $_.HasB) -or ($_.Role -eq 'B' -and $_.HasA)) })
    Write-Output "Protected observations leaking another owner's metadata: $($leaks.Count)"
    if ($RequireProtected -and $leaks.Count -gt 0) {throw 'Derived metadata privacy leak'}
    if ($RequireProtected) {
        foreach ($row in $results | Where-Object {$_.Phase -eq 'Protected' -and $_.Label -notlike 'Items/*' -and $_.Label -notlike 'Lookup-*' -and $_.Label -notlike 'Id-*' -and $_.Label -notlike 'Page*' -and $_.Label -notlike 'Spoof*'}) {
            if ($row.Label.StartsWith('XML')) {
                $baselineXml=@($results | Where-Object {$_.Phase -eq 'Baseline' -and $_.Role -eq $row.Role -and $_.Label -eq ('Baseline'+$row.Label)})[0]
                if ($baselineXml.Status -ne 200) {
                    if ($row.HasA -or $row.HasB) {throw 'Private metadata exposed by failing XML route'}
                    Write-Output "LIMITATION: $($row.Label) already failed without guard (HTTP $($baselineXml.Status)); not a positive owner XML proof."
                    continue
                }
            }
            if ($row.Status -ne 200 -or ($row.Role -eq 'A' -and -not $row.HasA) -or ($row.Role -eq 'B' -and -not $row.HasB)) {throw 'Owner metadata positive control failed'}
        }
        foreach ($row in $results | Where-Object {$_.Phase -eq 'Protected' -and $_.Label -like 'Spoof*'}) {if ($row.Status -ne 404) {throw 'Metadata user spoofing was not denied'}}
        foreach ($row in $results | Where-Object {$_.Phase -eq 'Protected' -and $_.Label -like 'Page*'}) {
            $own=if ($row.Role -eq 'A') {$row.HasA} else {$row.HasB}
            if ($row.Status -ne 200 -or $row.Total -ne 2 -or $row.Names.Count -ne 1 -or ($row.Label.StartsWith('Page0') -and -not $own) -or ($row.Label.StartsWith('Page1') -and -not $row.Shared)) {throw 'Scoped metadata pagination failed'}
        }
        foreach ($row in $results | Where-Object {$_.Phase -eq 'Protected' -and ($_.Label -like 'Id-*' -or ($_.Label -like 'Lookup-*' -and $_.Label -notlike '*Tags'))}) {
            $own=$row.Label.StartsWith('Id-'+$row.Role.ToLowerInvariant()) -or $row.Label.StartsWith('Lookup-'+$row.Role.ToLowerInvariant())
            $expected=if ($own) {200} else {404}
            if ($row.Status -ne $expected) {throw 'Direct metadata status control failed'}
        }
    }
}
finally {
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/derived-metadata-results.json') -Encoding UTF8
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
