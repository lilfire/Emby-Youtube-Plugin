# Item-list gate latency on a separate isolated Emby 4.10.1.0 instance
# (own programdata, port 18097) with the synthetic library from
# New-SyntheticLibrary.ps1. Shares only the portable server binaries with
# verification/WatchState. No production data, Google or Lilflix involved.
param(
    [Parameter(Mandatory)][string]$PluginDll,
    [Parameter(Mandatory)][string]$Label,
    [int]$Repeat = 3,
    [switch]$ParallelHome,
    [switch]$Stop,
    [switch]$KeepRunning
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$executable = Join-Path $repository 'verification/WatchState/bin/emby-isolated/server/system/EmbyServer.exe'
$bin = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin'))
$programData = Join-Path $bin 'emby-perf'
$library = Join-Path $bin 'synthetic-movies'
$pidFile = Join-Path $bin 'emby-perf.pid'
$authFile = Join-Path $bin 'emby-perf-auth.json'
$base = 'http://127.0.0.1:18097/emby'
$client = 'MediaBrowser Client="Gate latency", Device="Isolated", DeviceId="gate-latency", Version="1"'

function Invoke-Emby($path, $method = 'Get', $body = $null, $token = $null) {
    $headers = @{ 'X-Emby-Authorization' = $client }
    if ($token) { $headers['X-Emby-Token'] = $token }
    $arguments = @{ Uri = "$base/$path"; Method = $method; Headers = $headers; TimeoutSec = 900 }
    if ($null -ne $body) { $arguments.Body = ($body | ConvertTo-Json -Depth 10); $arguments.ContentType = 'application/json' }
    Invoke-RestMethod @arguments
}
function Stop-PerfServer {
    if (-not (Test-Path -LiteralPath $pidFile)) { return }
    $process = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile)) -ErrorAction SilentlyContinue
    if ($process) {
        if ($process.Path -ne $executable) { throw 'Refusing to control an unrelated process.' }
        try { Invoke-Emby 'System/Shutdown' Post $null (Get-Content $authFile -Raw | ConvertFrom-Json).Token | Out-Null } catch {}
        if (-not $process.WaitForExit(20000)) { Stop-Process -Id $process.Id }
    }
    Remove-Item -LiteralPath $pidFile
}
if ($Stop) { Stop-PerfServer; return }
if (-not (Test-Path -LiteralPath $library)) { throw 'Run New-SyntheticLibrary.ps1 first' }
Stop-PerfServer
foreach ($folder in 'config', 'plugins') { New-Item -ItemType Directory -Force (Join-Path $programData $folder) | Out-Null }
$system = Join-Path $programData 'config/system.xml'
if (-not (Test-Path -LiteralPath $system)) {
    Set-Content -LiteralPath $system -Encoding UTF8 -Value @'
<?xml version="1.0"?>
<ServerConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <HttpServerPortNumber>18097</HttpServerPortNumber>
  <HttpsPortNumber>18922</HttpsPortNumber>
  <PublicPort>18097</PublicPort>
  <PublicHttpsPort>18922</PublicHttpsPort>
  <EnableUPnP>false</EnableUPnP>
  <ServerName>Isolated Gate Latency</ServerName>
</ServerConfiguration>
'@
}
Copy-Item -LiteralPath $PluginDll -Destination (Join-Path $programData 'plugins/Emby.YouTubePlugin.dll') -Force
$previousHeapLimit = [Environment]::GetEnvironmentVariable('DOTNET_GCHeapHardLimit', 'Process')
try {
    [Environment]::SetEnvironmentVariable('DOTNET_GCHeapHardLimit', '0x80000000', 'Process')
    $process = Start-Process -FilePath $executable -ArgumentList @('-programdata', $programData, '-noautorunwebapp', '-nosplash', '-service') `
        -WorkingDirectory (Split-Path $executable) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $bin 'emby-perf-stdout.log') `
        -RedirectStandardError (Join-Path $bin 'emby-perf-stderr.log') -PassThru
} finally { [Environment]::SetEnvironmentVariable('DOTNET_GCHeapHardLimit', $previousHeapLimit, 'Process') }
$process.Id | Set-Content -LiteralPath $pidFile
$deadline = [DateTime]::UtcNow.AddSeconds(90)
do { try { $info = Invoke-Emby 'System/Info/Public'; break } catch { Start-Sleep -Milliseconds 500 } } while ([DateTime]::UtcNow -lt $deadline)
if ($info.ServerName -ne 'Isolated Gate Latency' -or $info.Version -ne '4.10.1.0') { throw 'Wrong latency server' }

if (-not (Test-Path -LiteralPath $authFile)) {
    Invoke-Emby 'Startup/Configuration' Post @{ UICulture = 'en-US'; MetadataCountryCode = 'US'; PreferredMetadataLanguage = 'en' } | Out-Null
    Invoke-Emby 'Startup/User' Post @{ Name = 'perf-admin'; Password = '' } | Out-Null
    Invoke-Emby 'Startup/Complete' Post | Out-Null
    $login = Invoke-Emby 'Users/AuthenticateByName' Post @{ Username = 'perf-admin'; Pw = '' }
    $admin = $login.AccessToken
    $user = Invoke-Emby 'Users/New' Post @{ Name = 'perf-user' } $admin
    Invoke-Emby "Users/$($user.Id)/Password" Post @{ NewPw = ''; ResetPassword = $true } $admin | Out-Null
    $userToken = (Invoke-Emby 'Users/AuthenticateByName' Post @{ Username = 'perf-user'; Pw = '' }).AccessToken
    Invoke-Emby 'Auth/Keys?App=GateLatency' Post $null $admin | Out-Null
    $key = @((Invoke-Emby 'Auth/Keys' Get $null $admin).Items | Where-Object AppName -eq 'GateLatency')[0].AccessToken
    $options = @{ LibraryOptions = @{
        PathInfos = @(@{ Path = $library }); EnableRealtimeMonitor = $false; SaveLocalMetadata = $false
        EnableChapterImageExtraction = $false; ExtractChapterImagesDuringLibraryScan = $false; ImportPlaylists = $false
        TypeOptions = @(@{ Type = 'Movie'; MetadataFetchers = @(); ImageFetchers = @() }) } }
    Invoke-Emby 'Library/VirtualFolders?name=Synthetic&collectionType=movies&refreshLibrary=true' Post $options $admin | Out-Null
    @{ Token = $admin; AdminId = $login.User.Id; UserId = $user.Id; UserToken = $userToken; Key = $key } | ConvertTo-Json | Set-Content -LiteralPath $authFile -Encoding UTF8
}
$auth = Get-Content -LiteralPath $authFile -Raw | ConvertFrom-Json
$adminId = $auth.AdminId
# Wait for the initial scan: movie count stable and no running library task.
$deadline = [DateTime]::UtcNow.AddMinutes(40); $last = -1; $stable = 0
do {
    Start-Sleep -Seconds 10
    $movies = (Invoke-Emby 'Items/Counts' Get $null $auth.Key).MovieCount
    $running = @(Invoke-Emby 'ScheduledTasks' Get $null $auth.Token | Where-Object { $_.State -ne 'Idle' -and $_.Category -eq 'Library' }).Count
    if ($movies -eq $last -and $running -eq 0) { $stable++ } else { $stable = 0 }
    $last = $movies
} while ($stable -lt 3 -and [DateTime]::UtcNow -lt $deadline)
if ($stable -lt 3) { throw 'Synthetic library scan did not settle' }

$subjects = [ordered]@{ admin = @{ Id = $adminId; Token = $auth.Token }; user = @{ Id = $auth.UserId; Token = $auth.UserToken } }
$rows = [Collections.Generic.List[object]]::new()
foreach ($round in 1..$Repeat) {
    foreach ($name in $subjects.Keys) {
        $s = $subjects[$name]
        foreach ($path in @("Users/$($s.Id)/Views", "Users/$($s.Id)/Items?SortBy=DateCreated&SortOrder=Descending&Recursive=true&Filters=IsUnplayed&Limit=12&IncludeItemTypes=Movie",
                "Users/$($s.Id)/Items/Latest?Limit=16", "Items/Counts?UserId=$($s.Id)", "Genres?UserId=$($s.Id)&Limit=50", "Studios?UserId=$($s.Id)&Limit=50", "Tags?UserId=$($s.Id)&Limit=50")) {
            $watch = [Diagnostics.Stopwatch]::StartNew(); $status = 200; $count = $null
            try { $body = Invoke-Emby $path Get $null $s.Token; $count = if ($body.PSObject.Properties['TotalRecordCount']) { $body.TotalRecordCount } elseif ($body.PSObject.Properties['MovieCount']) { $body.MovieCount } else { @($body).Count } }
            catch { $status = [int]$_.Exception.Response.StatusCode }
            $rows.Add([pscustomobject]@{ Label = $Label; Round = $round; Actor = $name; Route = ($path -replace '\?.*', '' -replace '[0-9a-f]{32}', '{u}'); Status = $status; Ms = $watch.ElapsedMilliseconds; Count = $count })
        }
    }
    foreach ($path in 'Items/Counts', 'Library/VirtualFolders', 'Items?IncludeItemTypes=BoxSet&Limit=0&Recursive=true') {
        $watch = [Diagnostics.Stopwatch]::StartNew(); $status = 200
        try { Invoke-Emby $path Get $null $auth.Key | Out-Null } catch { $status = [int]$_.Exception.Response.StatusCode }
        $rows.Add([pscustomobject]@{ Label = $Label; Round = $round; Actor = 'serverkey'; Route = ($path -replace '\?.*', ''); Status = $status; Ms = $watch.ElapsedMilliseconds; Count = $null })
    }
}
$parallelRows = [Collections.Generic.List[object]]::new()
if ($ParallelHome) {
    Add-Type -AssemblyName System.Net.Http
    $http = [Net.Http.HttpClient]::new(); $http.Timeout = [TimeSpan]::FromSeconds(30)
    try {
        foreach ($round in 1..$Repeat) {
            $pending = [Collections.Generic.List[object]]::new()
            foreach ($name in $subjects.Keys) {
                $s = $subjects[$name]
                foreach ($route in @("Users/$($s.Id)/Views", "Users/$($s.Id)/Items?SortBy=DateCreated&SortOrder=Descending&Recursive=true&Limit=12&IncludeItemTypes=Movie", "Users/$($s.Id)/Items/Latest?Limit=16")) {
                    $message = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, "$base/$route")
                    $message.Headers.TryAddWithoutValidation('X-Emby-Authorization', $client) | Out-Null
                    $message.Headers.TryAddWithoutValidation('X-Emby-Token', $s.Token) | Out-Null
                    $watch = [Diagnostics.Stopwatch]::StartNew()
                    $pending.Add(@{ Message=$message; Task=$http.SendAsync($message); Watch=$watch; Actor=$name; Route=$route })
                }
            }
            while ($pending.Count) {
                foreach ($request in @($pending.ToArray())) {
                    if (-not $request.Task.IsCompleted) { continue }
                    $request.Watch.Stop(); $response = $request.Task.GetAwaiter().GetResult()
                    try {
                        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                        $count = if ($body.PSObject.Properties['TotalRecordCount']) { $body.TotalRecordCount } else { @($body).Count }
                        $parallelRows.Add([pscustomobject]@{ Round=$round; Actor=$request.Actor; Route=($request.Route -replace '\?.*', '' -replace '[0-9a-f]{32}', '{u}'); Status=[int]$response.StatusCode; Ms=$request.Watch.ElapsedMilliseconds; Count=$count })
                    } finally { $response.Dispose(); $request.Message.Dispose() }
                    $pending.Remove($request) | Out-Null
                }
                if ($pending.Count) { Start-Sleep -Milliseconds 5 }
            }
        }
    } finally { $http.Dispose() }
}
$items = (Invoke-Emby 'Items?Recursive=true&Limit=0' Get $null $auth.Token).TotalRecordCount
if ($KeepRunning) { Write-Output "Kept running on $base"; $rows | Format-Table -AutoSize | Out-String -Width 200; return }
$gateLog = Get-ChildItem -LiteralPath (Join-Path $programData 'data') -Filter 'youtube-plugin.log' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-Content -LiteralPath $_.FullName | Where-Object { $_ -match 'Item-list gate' } | Select-Object -Last 12 }
Stop-PerfServer
[pscustomobject]@{ Label = $Label; PluginSha256 = (Get-FileHash -LiteralPath $PluginDll).Hash; AdminVisibleItems = $items; Rows = $rows; ParallelRows = $parallelRows; GateLog = @($gateLog) } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bin "latency-$Label.json") -Encoding UTF8
$rows | Group-Object Actor, Route | ForEach-Object {
    [pscustomobject]@{ Label = $Label; Actor = $_.Group[0].Actor; Route = $_.Group[0].Route; Status = ($_.Group.Status | Sort-Object -Unique) -join ','; MedianMs = ($_.Group.Ms | Sort-Object)[[int][Math]::Floor($_.Count / 2)]; Count = $_.Group[-1].Count }
} | Format-Table -AutoSize | Out-String -Width 200
