. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $journal=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    $lib=@($journal.Libraries|Where-Object Owner -eq 'a')[0]
    $native=Call 'PersonalChannelsFixture/NativeRecreatedRootProbe'
    if(-not $native.Exists -or $native.RootKey -ne $lib.LibraryId -or $native.Videos.Count -ne 1){throw 'Wrong isolated native root'}
    $expected=[IO.Path]::GetFullPath($lib.Folder)
    $matches=@($native.PhysicalLocations|Where-Object{[IO.Path]::GetFullPath($_) -eq $expected}).Count
    $configuredMatches=@($native.NativeConfiguredLocations|Where-Object{[IO.Path]::GetFullPath($_) -eq $expected}).Count
    $result=@{Completed=$true;Version='4.10.1.0';RootRuntimeType=$native.RootRuntimeType;PhysicalLocationsPropertyFound=$native.PhysicalLocationsPropertyFound;PhysicalLocationsCount=$native.PhysicalLocations.Count;PhysicalLocationsMatchControlledMedia=($matches -eq 1);NativeConfiguredLocationsMatchControlledMedia=($native.NativeVirtualFolderMatches -eq 1 -and $configuredMatches -eq 1);RootPathEqualsControlledMedia=($native.RootPath -and [IO.Path]::GetFullPath($native.RootPath) -eq $expected);NativeSnapshot=$native}
    $result|ConvertTo-Json -Depth 9|Set-Content (Join-Path $PSScriptRoot 'bin/native-root-locations-results.json') -Encoding UTF8
    [pscustomobject]$result|Select-Object Completed,RootRuntimeType,PhysicalLocationsPropertyFound,PhysicalLocationsCount,PhysicalLocationsMatchControlledMedia,RootPathEqualsControlledMedia|ConvertTo-Json
}finally{& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null;$client.Dispose()}
