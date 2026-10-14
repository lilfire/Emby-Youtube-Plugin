$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$data=Join-Path $root 'data/data'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$headers=@{'X-Emby-Token'=$auth.Token}
$state=Join-Path $data 'personal-channels-fixture.json'
$report=[Collections.Generic.List[object]]::new()
function Call($path,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=2}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 12}
    Invoke-RestMethod @args
}
function StopVerified {
    $idFile=Join-Path $root 'server.pid'
    if (Test-Path -LiteralPath $idFile) {
        $serverProcess=Get-Process -Id ([int](Get-Content -LiteralPath $idFile)) -ErrorAction SilentlyContinue
        if ($serverProcess) {
            if ($serverProcess.Path -ne (Join-Path $root 'server/system/EmbyServer.exe')) {throw 'Wrong process'}
            Stop-Process -Id $serverProcess.Id
            $serverProcess.WaitForExit()
        }
    }
}
function StartAndHammer($label,$path) {
    $job=Start-Job -ScriptBlock {param($script) & $script} -ArgumentList $control
    $counts=@{}
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    do {
        $status=200
        try {Call $path | Out-Null}
        catch {$status=if ($_.Exception.Response) {[int]$_.Exception.Response.StatusCode} else {0}}
        $statusKey=[string]$status
        if (-not $counts.ContainsKey($statusKey)) {$counts[$statusKey]=0};$counts[$statusKey]++
        Start-Sleep -Milliseconds 40
    } while ([DateTime]::UtcNow -lt $deadline)
    $job | Wait-Job -Timeout 2 | Out-Null
    Receive-Job $job | Out-Null
    Remove-Job $job -Force
    $report.Add(@{Label=$label;StatusCounts=$counts})
    Write-Host ($label+': '+($counts|ConvertTo-Json -Compress))
    return $counts
}
$session=$null
try {
    $info=Call 'System/Info/Public'
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Invoke-RestMethod "$base/Users/AuthenticateByName" -Method Post -Headers @{Authorization='MediaBrowser Client="Startup gate test", Device="Isolated test", DeviceId="startup-privacy", Version="1.0"'} -ContentType application/json -Body '{"Username":"fixture-second","Pw":""}'
    Call 'PersonalChannelsFixture/Configure' Post @{Profiles=@(@{Owner='a';Revision=1});Prune=$true} | Out-Null
    $channel=(Call 'Channels').Items | Where-Object Name -eq 'Personal Fixture a'
    $video=(Call "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video").Items | Select-Object -First 1
    Call 'PersonalChannelsFixture/Guard' Post @{OwnerUserId=$auth.UserId} | Out-Null
    $headers=@{'X-Emby-Token'=$session.AccessToken}
    StopVerified
    Set-Content -LiteralPath ($state+'.delay') -Value 'deliberate test delay'
    $counts=StartAndHammer 'Delayed initialization refuses private metadata' "Users/$($session.User.Id)/Items/$($video.Id)"
    if ($counts.ContainsKey('200') -or -not $counts.ContainsKey('503') -or -not $counts.ContainsKey('404')) {throw 'Startup gate did not cover delayed initialization'}
    StopVerified
    '"nonexistent-test-owner"' | Set-Content -LiteralPath ($state+'.guard.json')
    $counts=StartAndHammer 'Invalid owner keeps server requests blocked' "Users/$($session.User.Id)/Items/$($video.Id)"
    if ($counts.ContainsKey('200') -or -not $counts.ContainsKey('503') -or $counts.ContainsKey('404')) {throw 'Invalid owner did not fail closed'}
}
finally {
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/startup-gate-results.json') -Encoding UTF8
    StopVerified
    foreach ($target in @(($state+'.guard.json'),($state+'.delay'))) {
        if (-not [IO.Path]::GetFullPath($target).StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe cleanup path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
    & $control
    $headers=@{'X-Emby-Token'=$auth.Token}
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 200}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test') {throw 'Cleanup server guard failed'}
    Call 'PersonalChannelsFixture/Configure' Post @{Profiles=@();Prune=$true} | Out-Null
    if (@((Call 'Channels').Items | Where-Object {$_.Name.StartsWith('Personal Fixture ')}).Count -ne 0) {throw 'Fixture cleanup failed'}
    if ($session) {Invoke-RestMethod "$base/Sessions/Logout" -Method Post -Headers @{'X-Emby-Token'=$session.AccessToken} | Out-Null}
    & $control -Stop
    foreach ($target in @($state,(Join-Path $root 'data/plugins/PersonalChannelsFixture.dll'))) {
        if (-not [IO.Path]::GetFullPath($target).StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe cleanup path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
