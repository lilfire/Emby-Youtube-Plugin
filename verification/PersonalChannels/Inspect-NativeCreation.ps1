. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
try {
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') | Out-Null
    $inspection=Call 'PersonalChannelsFixture/NativeCreationInspection'
    if (-not $inspection.RuntimeType -or $inspection.Methods.Count -lt 2) {throw 'Missing runtime native creation methods'}
    $inspection | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $PSScriptRoot 'bin/native-creation-il.json') -Encoding UTF8
    Write-Output ('Inspected native creation methods: '+$inspection.Methods.Count)
} finally {
    try { & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop | Out-Null }
    finally { $client.Dispose() }
}
