. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
if(Test-Path (Join-Path $root 'data/data/youtube-personal')){throw 'Native variant baseline requires absent personal profiles and bindings'}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1')|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    $u=@($fixture.Users|Where-Object Owner -eq 'a')[0];$lib=@($fixture.Libraries|Where-Object Owner -eq 'a')[0]
    $login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Native variant baseline", Device="Isolated", DeviceId="baseline-a", Version="1"'} Post @{Username=$u.Name;Pw=''}
    if($login.User.Policy.IsAdministrator -or $login.User.Id -ne $u.UserId){throw 'Wrong synthetic ordinary identity'}
    $headers=@{'X-Emby-Token'=$login.AccessToken}
    $state=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($state.ExperimentalEnabled){throw 'Experimental guard still active'}
    $path="Items/$($lib.VideoId)/Download"
    $full=Request $path $headers
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$full.Bytes)).Replace('-','')}finally{$sha.Dispose()}
    $sourceHash=(Get-FileHash (Join-Path $lib.Folder 'PrivateNativeVideo_a_client.mp4')).Hash
    if($full.Status -ne 200 -or $hash -ne $sourceHash -or -not $full.ETag){throw 'Native source or ETag not established'}
    $rows.Add(@{Label='Native ordinary download';Status=$full.Status;HashMatches=$true;Bytes=$full.Bytes.Length;HasETag=$true})
    $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
    $head=Request $path $headers Head
    $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
    $rows.Add(@{Label='Native HEAD baseline';Status=$head.Status;Bytes=$head.Bytes.Length;ContentLength=$head.ContentLength;PrivateHeader=$head.PrivateAHeader;CheckedDelta=($after.Checked-$before.Checked)})
    if($head.Status -ne 404 -or $head.Bytes.Length -ne 0 -or $head.PrivateAHeader -or $after.Checked -ne $before.Checked){throw 'HEAD native baseline differs from unsupported route expectation'}
    $conditional=$headers.Clone();$conditional['If-None-Match']=$full.ETag
    $cached=Request $path $conditional
    $rows.Add(@{Label='Native matching ETag baseline';Status=$cached.Status;Bytes=$cached.Bytes.Length})
    if($cached.Status -ne 304 -or $cached.Bytes.Length -ne 0){throw 'Native conditional download does not support 304'}
    $inventory=Call 'PersonalChannelsFixture/NativeBoundaryInspection'
    $inventory|ConvertTo-Json -Depth 12|Set-Content (Join-Path $PSScriptRoot 'bin/native-download-writer-inventory.json') -Encoding UTF8
    $inventory.HttpResultContract
    $inventory.ResultFactoryContract
    $completed=$true
}finally{
    @{Completed=$completed;Observations=$rows.ToArray();Scope='No personal profiles/bindings; native synthetic download variants; experimental guard disabled'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/native-download-variant-baseline-results.json') -Encoding UTF8
    try{& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null}finally{$client.Dispose()}
}
