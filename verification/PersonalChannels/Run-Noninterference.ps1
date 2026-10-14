param([switch]$RequireUnchanged)
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
function Snapshot($path,$full=$false) {
    $status=200;$data=$null
    try {$data=Call $path $other} catch {if (-not $_.Exception.Response) {throw 'Snapshot request failed before HTTP response'};$status=[int]$_.Exception.Response.StatusCode}
    if (-not $full -and $null -ne $data.Items) {
        # Compare visible identities, ordering and count. Do not remove any private-data fields from these.
        $data=@{TotalRecordCount=$data.TotalRecordCount;Items=@($data.Items | ForEach-Object { @{Id=$_.Id;Name=$_.Name} })}
    }
    @{Status=$status;Data=$data} | ConvertTo-Json -Depth 30 -Compress
}
function ConcurrentOwners($expectedA,$phase) {
    Add-Type -AssemblyName System.Net.Http
    $clients=@([Net.Http.HttpClient]::new(),[Net.Http.HttpClient]::new())
    $pending=[Collections.Generic.List[object]]::new()
    try {
        $ownerIds=@{
            0=@((Call "Items?ParentId=$($a.Id)&Recursive=true&IncludeItemTypes=Video" $admin).Items.Id)
            1=@((Call "Items?ParentId=$($b.Id)&Recursive=true&IncludeItemTypes=Video" $other).Items.Id)
        }
        $clients[0].DefaultRequestHeaders.Add('X-Emby-Token',$auth.Token)
        $clients[1].DefaultRequestHeaders.Add('X-Emby-Token',$session.AccessToken)
        foreach ($index in 0..19) {
            foreach ($owner in 0..1) {
                $pending.Add(@{Owner=$owner;Task=$clients[$owner].GetStringAsync("$base/Items?Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=1")})
            }
        }
        foreach ($request in $pending) {
            $data=$request.Task.GetAwaiter().GetResult() | ConvertFrom-Json
            $expected=if ($request.Owner -eq 0) {$expectedA} else {2}
            if ($data.TotalRecordCount -ne $expected -or $data.Items.Count -ne 1) {throw 'Concurrent owner paging failed'}
            if ($data.Items[0].Id -notin $ownerIds[$request.Owner]) {throw 'Concurrent request returned wrong owner item'}
        }
        $results.Add(@{Label="Concurrent owners $phase";Passed=$true;Requests=$pending.Count})
        Write-Output "Concurrent owners $phase : $($pending.Count) requests passed"
    } finally {foreach ($client in $clients) {$client.Dispose()}}
}
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Noninterference test", Device="Isolated test", DeviceId="noninterference-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $other=@{'X-Emby-Token'=$session.AccessToken};$uid=$session.User.Id
    $original=(Call "Users/$uid").Policy
    $policy=$original | ConvertTo-Json -Depth 15 | ConvertFrom-Json;$policy.EnableAllChannels=$true
    Call "Users/$uid/Policy" $admin Post $policy | Out-Null
    if (-not (Call "Users/$uid").Policy.EnableAllChannels) {throw 'Policy readback failed'}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1},@{Owner='b';Revision=1});Prune=$true} | Out-Null
    $configured=$true
    $channels=(Call 'Channels').Items
    $a=$channels | Where-Object Name -eq 'Personal Fixture a';$b=$channels | Where-Object Name -eq 'Personal Fixture b'
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;OwnerUserIds=@{a=$auth.UserId;b=$uid}} | Out-Null
    $paths=[ordered]@{
        'Own full search'="Items?UserId=$uid&Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName"
        'First page size 1'="Items?UserId=$uid&Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=0"
        'Second page size 1'="Items?UserId=$uid&Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=1"
        'First page size 2'="Items?UserId=$uid&Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=2"
        'Own parent search'="Items?UserId=$uid&ParentId=$($b.Id)&Recursive=true&IncludeItemTypes=Video"
        'Count with user'="Items/Counts?UserId=$uid"
        'Count without user'='Items/Counts'
        'Channels page 1'="Channels?UserId=$uid&StartIndex=0&Limit=1"
        'Genres page 1'="Genres?UserId=$uid&StartIndex=0&Limit=1&SortBy=SortName"
        'Genres page 2'="Genres?UserId=$uid&StartIndex=1&Limit=1&SortBy=SortName"
        'Studios'="Studios?UserId=$uid"
        'Tags'="Tags?UserId=$uid"
        'Search without user page 1'='Items?Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=0'
        'Search without user page 2'='Items?Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=1'
        'User route page 1'="Users/$uid/Items?Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=0"
        'User route page 2'="Users/$uid/Items?Recursive=true&SearchTerm=Personal%20Video&SortBy=SortName&Limit=1&StartIndex=1"
        'Own full metadata'="Items?UserId=$uid&ParentId=$($b.Id)&Recursive=true&IncludeItemTypes=Video&Fields=Genres,Studios,Tags,Overview,MediaSources,DateCreated,UserData"
        'Search hints'="Search/Hints?UserId=$uid&SearchTerm=Personal%20Video&Limit=1"
    }
    $before=@{}
    foreach ($label in $paths.Keys) {Write-Output "Before: $label";$before[$label]=Snapshot $paths[$label] ($label -eq 'Own full metadata')}
    $own=Call $paths['Own full search'] $other
    if ($own.Items.Count -ne 2 -or $own.TotalRecordCount -ne 2) {throw 'Own visible data positive control failed'}
    $pagingLabels=@('First page size 1','Second page size 1','First page size 2','Search without user page 1','Search without user page 2','User route page 1','User route page 2')
    foreach ($label in $pagingLabels) {
        $page=Call $paths[$label] $other
        $expected=if ($label -eq 'First page size 2') {2} else {1}
        if ($RequireUnchanged -and ($page.Items.Count -ne $expected -or $page.TotalRecordCount -ne 2)) {
            throw "Own pagination positive control failed: $label"
        }
    }
    ConcurrentOwners 2 'before'
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=2},@{Owner='b';Revision=1});Prune=$true} | Out-Null
    $new=(Call "Items?UserId=$($auth.UserId)&ParentId=$($a.Id)&Recursive=true&SearchTerm=added_a").Items
    if ($new.Count -ne 1) {throw 'Private world change was not verified'}
    ConcurrentOwners 3 'after'
    foreach ($label in $paths.Keys) {
        $after=Snapshot $paths[$label] ($label -eq 'Own full metadata');$same=$after -eq $before[$label]
        $results.Add(@{Label=$label;Unchanged=$same;Before=$before[$label];After=$after})
        if ($RequireUnchanged -and $label -in $pagingLabels) {
            $page=Call $paths[$label] $other
            $expected=if ($label -eq 'First page size 2') {2} else {1}
            if ($page.Items.Count -ne $expected -or $page.TotalRecordCount -ne 2) {throw "Own pagination after change failed: $label"}
        }
        Write-Output "$label : unchanged=$same"
    }
    $changed=@($results | Where-Object {$_.ContainsKey('Unchanged') -and -not $_.Unchanged})
    if ($RequireUnchanged -and $changed.Count -gt 0) {throw ('Noninterference failed in '+$changed.Count+' observations')}
}
finally {
    $results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/noninterference-results.json') -Encoding UTF8
    if ($started) {
        if ($original) {
            Call "Users/$uid/Policy" $admin Post $original | Out-Null
            if (((Call "Users/$uid").Policy | ConvertTo-Json -Depth 15 -Compress) -ne ($original | ConvertTo-Json -Depth 15 -Compress)) {throw 'Policy restoration failed'}
        }
        if ($configured) {Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null}
        if ($session) {Call 'Sessions/Logout' $other Post | Out-Null}
        & $control -Stop
    }
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative));if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
