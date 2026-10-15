param()
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Push-Location $repository
try {
    & dotnet run --project (Join-Path $PSScriptRoot 'G.csproj') -c Release -- $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw 'G verification failed' }
    $evidence = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'WINDOWS-EVIDENCE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $evidence.Complete -or -not $evidence.Cleanup.FixtureRemoved -or -not $evidence.Cleanup.AllTrackedProcessesExited) { throw 'G evidence or cleanup incomplete' }
    if (@($evidence.Observations | Where-Object { -not $_.Reproduced }).Count -gt 0) { throw 'Unreproduced observation' }
    [pscustomobject]@{ Complete=$evidence.Complete; Observations=$evidence.Observations.Count; RequirementNotMet=@($evidence.Observations | Where-Object { -not $_.RequirementMet }).Count; CleanupVerified=$true }
} finally { Pop-Location }
