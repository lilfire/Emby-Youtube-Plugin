. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $r=Call 'PersonalChannelsFixture/NativeBoundaryInspection'
    $r|ConvertTo-Json -Depth 14|Set-Content (Join-Path $PSScriptRoot 'bin/native-boundary-inventory.json') -Encoding UTF8
    if($r.Methods.Count -lt 2 -or $r.RouteDtos.Count -lt 100){throw 'Native boundary inventory missing'}
    Write-Output ('Native route DTOs='+$r.RouteDtos.Count)
}finally{
    try{& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null}finally{$client.Dispose()}
}
