$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testRoot = Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base = 'http://127.0.0.1:18096/emby'
$auth = Get-Content -LiteralPath (Join-Path $testRoot 'test-auth.json') -Raw | ConvertFrom-Json
$headers = @{ 'X-Emby-Token' = $auth.Token }
$serverControl = Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$checks = [Collections.Generic.List[string]]::new()

function Call([string]$path, [string]$method = 'Get', $body = $null) {
    $arguments = @{ Uri = "$base/$path"; Method = $method; Headers = $headers }
    if ($null -ne $body) {
        $arguments.ContentType = 'application/json'
        $arguments.Body = ConvertTo-Json -InputObject $body -Depth 15
    }
    Invoke-RestMethod @arguments
}
function VerifyServer {
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        try { $info = Call 'System/Info/Public'; break }
        catch { Start-Sleep -Milliseconds 500 }
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {
        throw 'Refusing to test a different server.'
    }
}
function Check([bool]$condition, [string]$label) {
    if (-not $condition) { throw "FAIL: $label" }
    $checks.Add($label)
    Write-Output "PASS: $label"
}
function Configure($profiles, [bool]$prune = $false) {
    Call 'PersonalChannelsFixture/Configure' 'Post' @{ Profiles = @($profiles); Prune = $prune }
}
function PersonalChannels {
    @((Call 'Channels').Items | Where-Object { $_.Name.StartsWith('Personal Fixture ') })
}
function Videos($channel) {
    @((Call "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video&Fields=ProviderIds").Items)
}
function SameIds($before, $after) {
    foreach ($old in $before) {
        $match = @($after | Where-Object Name -eq $old.Name)
        if ($match.Count -ne 1 -or $match[0].Id -ne $old.Id -or $match[0].Guid -ne $old.Guid) { return $false }
    }
    return $true
}

VerifyServer
try {
    Configure @() $true | Out-Null
    $profiles = @(@{ Owner = 'a'; Revision = 1 }, @{ Owner = 'b'; Revision = 1 })
    $state = Configure $profiles
    $initial = @(PersonalChannels)
    Check ($initial.Count -eq 2) 'Two channel instances of the same class materialize independently'
    Check (@($state.Registered | Where-Object Name -in @('YouTube','Watch State Fixture')).Count -eq 2) 'Existing channels survive registry replacement'
    Check (@($state.Profiles | Where-Object { $_.SelectedCredentialOwner -notin @('a','b') }).Count -eq 0) 'Each channel resolves its own synthetic credential owner'
    Check (@($state.Profiles | ForEach-Object ObservedUserIds | Where-Object { $_ -ne 0 }).Count -eq 0) 'Background queries carry UserId zero'
    $a = $initial | Where-Object Name -eq 'Personal Fixture a'
    $b = $initial | Where-Object Name -eq 'Personal Fixture b'
    $sharedA = @(Videos $a | Where-Object { $_.ProviderIds.YouTube -eq 'shared00001' })
    $sharedB = @(Videos $b | Where-Object { $_.ProviderIds.YouTube -eq 'shared00001' })
    Check ($sharedA.Count -eq 1 -and $sharedB.Count -eq 1 -and $sharedA[0].Id -ne $sharedB[0].Id) 'The same YouTube ID gets distinct database items in different channels'
    Call "Users/$($auth.UserId)/PlayedItems/$($sharedA[0].Id)" 'Post' | Out-Null
    $playedA = Call "Users/$($auth.UserId)/Items/$($sharedA[0].Id)"
    $playedB = Call "Users/$($auth.UserId)/Items/$($sharedB[0].Id)"
    Check ($playedA.UserData.Played -and -not $playedB.UserData.Played) 'Watched state is independent between duplicate videos for the same user'
    $state = Configure $profiles
    Check ($state.Registered.Count -eq 4 -and (SameIds $initial @(PersonalChannels))) 'Repeated registration keeps IDs stable and creates no duplicate registrations'
    $profiles[0].Revision = 2
    Configure $profiles | Out-Null
    Check (@(Videos $a).Count -eq 3 -and @(Videos $b).Count -eq 2) 'Updating one profile changes only its own collection'

    $profiles = @(@{ Owner = 'a'; Revision = 2 }, @{ Owner = 'c'; Revision = 1 })
    $state = Configure $profiles
    Check (@($state.Registered | Where-Object Name -eq 'Personal Fixture b').Count -eq 0) 'Removing a profile removes its runtime registration'
    Check (@(PersonalChannels | Where-Object Name -eq 'Personal Fixture b').Count -eq 1) 'Registry removal alone leaves stale channel data in the database'
    Configure $profiles $true | Out-Null
    Check (@(PersonalChannels | Where-Object Name -eq 'Personal Fixture b').Count -eq 0) 'Explicit library cleanup removes the stale channel'
    Check (@((Call 'Items?Recursive=true&SearchTerm=unique_b').Items).Count -eq 0) 'Cleanup also removes the stale videos from search'
    $removedStatus = 200
    try { Call "Users/$($auth.UserId)/Items/$($sharedB[0].Id)" | Out-Null }
    catch { $removedStatus = [int]$_.Exception.Response.StatusCode }
    Check ($removedStatus -eq 404) 'Deleted video is unavailable by its old item ID'

    $profiles[0].Label = 'a renamed'
    Configure $profiles | Out-Null
    $renamed = PersonalChannels | Where-Object Name -eq 'Personal Fixture a renamed'
    Check ($renamed.Id -ne $a.Id -and $renamed.Guid -ne $a.Guid) 'Changing channel Name changes identity despite the unchanged declared Id property'
    $profiles[0].Remove('Label')
    Configure $profiles $true | Out-Null
    $beforeRestart = @(PersonalChannels)
    & $serverControl -Stop
    & $serverControl
    VerifyServer
    $afterRestart = @(PersonalChannels)
    Check (SameIds $beforeRestart $afterRestart) 'Database IDs and GUIDs survive a server restart'
    $state = Call 'PersonalChannelsFixture/State'
    Check ($state.Profiles.Count -eq 2 -and @($state.Registered | Where-Object Name -in @('Personal Fixture a','Personal Fixture c')).Count -eq 2) 'Persisted profiles restore both runtime instances at startup'
    $state = Configure $profiles
    Check (@($state.Profiles | Where-Object { $_.ObservedUserIds.Count -lt 2 -or $_.SelectedCredentialOwner -notin @('a','c') }).Count -eq 0) 'Both restored instances refresh through their own owners'
    Check (SameIds $beforeRestart @(PersonalChannels)) 'Post-restart refresh preserves the same identities'
    $report = @{ ServerVersion = '4.10.1.0'; Checks = @($checks); CompletedUtc = [DateTime]::UtcNow.ToString('o') }
    $outputDirectory = Join-Path $PSScriptRoot 'bin'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputDirectory 'lifecycle-results.json')
} finally {
    Configure @() $true | Out-Null
    if (@(PersonalChannels).Count -ne 0) { throw 'Fixture cleanup left channel records behind.' }
    & $serverControl -Stop
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll', 'data/data/personal-channels-fixture.json',
        'personal-fixture-baseline.json', 'personal-fixture-restart.json')) {
        $target = [IO.Path]::GetFullPath((Join-Path $testRoot $relative))
        if (-not $target.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Unexpected fixture cleanup path.'
        }
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
    Write-Output 'Fixture records removed; isolated server stopped; test plugin uninstalled.'
}
