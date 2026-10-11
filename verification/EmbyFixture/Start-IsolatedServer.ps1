param([switch]$Stop)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$isolatedRoot = Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$executable = Join-Path $isolatedRoot 'server/system/EmbyServer.exe'
$pidFile = Join-Path $isolatedRoot 'server.pid'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Download/extract the portable test server first.' }
if (Test-Path -LiteralPath $pidFile) {
    $testProcessId = [int](Get-Content -LiteralPath $pidFile)
    $existing = Get-Process -Id $testProcessId -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.Path -ne $executable) { throw 'Refusing to control an unrelated process.' }
        if (-not $Stop) { throw 'The isolated server is already running.' }
        $auth = Get-Content -LiteralPath (Join-Path $isolatedRoot 'test-auth.json') -Raw | ConvertFrom-Json
        Invoke-RestMethod -Uri 'http://127.0.0.1:18096/emby/System/Shutdown' -Method Post -Headers @{ 'X-Emby-Token' = $auth.Token } | Out-Null
        if (-not $existing.WaitForExit(10000)) { Stop-Process -Id $testProcessId -ErrorAction Stop }
    }
}
if ($Stop) { Write-Output 'Isolated server stopped.'; exit 0 }
Copy-Item -LiteralPath (Join-Path $repository 'bin/Release/net6.0/Emby.YouTubePlugin.dll') -Destination (Join-Path $isolatedRoot 'data/plugins/Emby.YouTubePlugin.dll')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/WatchStateFixture.dll') -Destination (Join-Path $isolatedRoot 'data/plugins/WatchStateFixture.dll')
$testProcess = Start-Process -FilePath $executable -ArgumentList @('-programdata', (Join-Path $isolatedRoot 'data'), '-noautorunwebapp', '-nosplash', '-service') -WorkingDirectory (Join-Path $isolatedRoot 'server/system') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $isolatedRoot 'stdout.log') -RedirectStandardError (Join-Path $isolatedRoot 'stderr.log') -PassThru
$testProcess.Id | Set-Content -LiteralPath $pidFile
Write-Output ('Isolated server started: ' + $testProcess.Id)
