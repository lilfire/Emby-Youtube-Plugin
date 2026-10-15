param([switch]$WindowsOnly)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Push-Location $repository
try {
    & dotnet build (Join-Path $PSScriptRoot 'E.csproj') -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw 'E build failed' }
    $binary = Join-Path $PSScriptRoot 'bin/Release/net8.0'
    & dotnet (Join-Path $binary 'PersonalYouTubeVerification.dll') (Join-Path $PSScriptRoot 'bin/windows')
    if ($LASTEXITCODE -ne 0) { throw 'E Windows reproduction failed' }
    if (-not $WindowsOnly) {
        $name = 'emby-youtube-followup-e'
        $existing = @(& docker container ls -a --format '{{.Names}}')
        if ($LASTEXITCODE -ne 0) { throw 'Docker unavailable' }
        if ($name -in $existing) { throw 'E container already exists; inspect it before continuing' }
        $created = $false
        try {
            & docker create --name $name --label 'purpose=emby-youtube-followup-e' --network none --memory 512m --cpus 2 --mount "type=bind,source=$binary,target=/app,readonly" mcr.microsoft.com/dotnet/runtime:8.0@sha256:60d11c2be381e7f90b8bd984472dd2432933858aba55087d5936980cf2071d5a dotnet /app/PersonalYouTubeVerification.dll /tmp/e-evidence
            if ($LASTEXITCODE -ne 0) { throw 'E container creation failed' }
            $created = $true
            & docker start --attach $name
            if ($LASTEXITCODE -ne 0) { throw 'E Linux reproduction failed' }
            $state = (& docker inspect $name --format '{{json .State}}') | ConvertFrom-Json
            if ($state.Running -or $state.ExitCode -ne 0) { throw 'E Linux process did not finish successfully' }
            New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'bin/linux') -Force | Out-Null
            & docker cp "${name}:/tmp/e-evidence/EVIDENCE.json" (Join-Path $PSScriptRoot 'bin/linux/EVIDENCE.json')
            if ($LASTEXITCODE -ne 0) { throw 'E Linux evidence copy failed' }
        } finally {
            if ($created) {
                $inspection = (& docker inspect $name) | ConvertFrom-Json
                $purpose = $inspection[0].Config.Labels.purpose
                if ($purpose -ne 'emby-youtube-followup-e') { throw 'Unexpected container identity during cleanup' }
                & docker rm --force $name
                if ($LASTEXITCODE -ne 0) { throw 'E container cleanup failed' }
            }
        }
        $remaining = @(& docker container ls -a --format '{{.Names}}')
        if ($name -in $remaining) { throw 'E container cleanup readback failed' }
    }
    $platforms = if ($WindowsOnly) { @('windows') } else { @('windows','linux') }
    $summary = @()
    foreach ($platform in $platforms) {
        $inputPath = Join-Path $PSScriptRoot "bin/$platform/EVIDENCE.json"
        $evidence = Get-Content -LiteralPath $inputPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $evidence.Completed -or -not $evidence.TestDataGone -or @($evidence.Observations | Where-Object {-not $_.Reproduced}).Count) { throw "Incomplete $platform evidence" }
        Copy-Item -LiteralPath $inputPath -Destination (Join-Path $PSScriptRoot ($platform.ToUpper() + '-EVIDENCE.json'))
        $summary += @{Platform=$evidence.Platform;Runtime=$evidence.Runtime;Observations=$evidence.Observations.Count;UnmetRequirementObservations=@($evidence.Observations|Where-Object {$null -ne $_.RequirementMet -and -not $_.RequirementMet}).Count;Skipped=@($evidence.Skipped);TestDataGone=$evidence.TestDataGone}
    }
    $source = @('PersonalYouTubeNativeCreation.cs','PersonalYouTubeNativeCreationHook.cs','PersonalYouTubeNativePublisher.cs','PersonalYouTubePublicationJournal.cs','PersonalYouTubeLifecycle.cs','PersonalYouTubeNativeBindings.cs','PersonalYouTubeNativeAccess.cs','PersonalYouTubeStore.cs','PersonalYouTubeJobs.cs','PersonalYouTubeJobRuntime.cs','PersonalYouTubeInitialRefresh.cs','PluginEntryPoint.cs') | ForEach-Object {
        @{File=$_;SHA256=(Get-FileHash -LiteralPath (Join-Path $repository $_) -Algorithm SHA256).Hash}
    }
    @{Commit=(& git rev-parse HEAD);Platforms=$summary;Source=$source;ContainerGone=($WindowsOnly -or $name -notin $remaining);NoEmbyServerStarted=$true;MainServerChanged=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'SUMMARY.json') -Encoding UTF8
    Write-Output 'E evidence exported; process/container and test-data cleanup verified.'
} finally { Pop-Location }
