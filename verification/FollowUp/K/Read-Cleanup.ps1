$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixtureRoot = Join-Path $repo 'verification/WatchState/bin/emby-isolated'
$processes = @(Get-CimInstance Win32_Process)
$fixtureProcesses = @($processes | Where-Object {
    $_.Name -match '^EmbyServer' -or
    ($_.CommandLine -and ($_.CommandLine.Contains($fixtureRoot) -or
    $_.CommandLine.Contains('followup-i-edge') -or $_.CommandLine.Contains('youtube-followup-g-')))
})
$ports = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object LocalPort -in @(18096,18108,18217))
$containers = @(& docker container ls -a --format '{{.Names}}|{{.State}}')
$dockerAvailable = $LASTEXITCODE -eq 0
$testContainers = @($containers | Where-Object { $_ -match '^(embytube-test|emby-youtube-)' } |
    ForEach-Object { $parts = $_.Split('|'); @{Name=$parts[0];State=$parts[1]} })
$checks = @(
    'verification/PersonalChannels/bin/native-client-state.json',
    'verification/WatchState/bin/emby-isolated/data/plugins/PersonalChannelsFixture.dll',
    'verification/WatchState/bin/emby-isolated/data/data/youtube-personal',
    'verification/FollowUp/H/bin/workspace',
    'bin/followup-i-edge'
) | ForEach-Object { @{Artifact=$_;Exists=(Test-Path -LiteralPath (Join-Path $repo $_))} }
$media = @(Get-ChildItem -LiteralPath (Join-Path $repo 'verification/PersonalChannels/bin/native-client') -File -Recurse -ErrorAction SilentlyContinue)
$libraries = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'data/root/default') -Directory -ErrorAction SilentlyContinue)
$tempRoots = @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -match '^youtube-followup-[eg]-|^personal-youtube-followup-')
@{CapturedUtc=[DateTime]::UtcNow.ToString('o');Scope='Local read-only snapshot; no remote Lilflix/TV readback';
  FixtureProcessCount=$fixtureProcesses.Count;TestListeners=@($ports | ForEach-Object LocalPort);
  DockerAvailable=$dockerAvailable;TestContainers=$testContainers;Paths=$checks;
  NativeClientMediaFiles=$media.Count;NativeLibraryDirectories=$libraries.Count;
  MatchingTempDirectories=$tempRoots.Count;
  Limit='Historical native user/library ID cleanup remains recorded in chapter evidence; no server restart performed'} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'CLEANUP-READBACK.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'CLEANUP-READBACK.json') -Raw -Encoding UTF8
