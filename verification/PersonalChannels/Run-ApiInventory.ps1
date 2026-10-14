$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$installed=$false;$started=$false
try {
    if (Test-Path (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')) {throw 'Fixture already installed'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    $installed=$true
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Invoke-RestMethod "$base/System/Info/Public" -TimeoutSec 2;break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $surface=Invoke-RestMethod "$base/PersonalChannelsFixture/Surface" -Headers @{'X-Emby-Token'=$auth.Token} -TimeoutSec 20
    if (-not $surface.ApiRoutes.Count) {throw 'No routes discovered; inventory is not verified'}
    @{Version=$info.Version;Routes=$surface.ApiRoutes;SyncSurface=$surface.SyncSurface;SyncModels=$surface.SyncModels;SyncCallReferences=$surface.SyncCallReferences;SyncProtocolReferences=$surface.SyncProtocolReferences;SyncSecurity=$surface.SyncSecurity;SyncTargetLookup=$surface.SyncTargetLookup;NativeNotifications=$surface.NativeNotifications;SocketHooks=$surface.SocketHooks} | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/api-inventory.json') -Encoding UTF8
    Write-Output "Declared API routes discovered: $($surface.ApiRoutes.Count)"
} finally {
    if ($started) {& $control -Stop}
    if ($installed) {Remove-Item -LiteralPath (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')}
}
