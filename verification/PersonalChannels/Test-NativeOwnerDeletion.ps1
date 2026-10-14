param([switch]$RequireOrphanIsolation)
# Disposable isolated-fixture investigation; never points at the main server.
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$base='http://127.0.0.1:18096/emby'
$journal=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw | ConvertFrom-Json
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$rows=[Collections.Generic.List[object]]::new()
function Request($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=10;UseBasicParsing=$true}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 12}
    try {$response=Invoke-WebRequest @args;return @{Status=[int]$response.StatusCode;Body=[string]$response.Content}}
    catch {if (-not $_.Exception.Response) {throw}; return @{Status=[int]$_.Exception.Response.StatusCode;Body=[string]$_.ErrorDetails.Message}}
}
function Record($label,$path,$headers) {
    $r=Request $path $headers
    $rows.Add(@{Label=$label;Status=$r.Status;ContainsPrivateA=$r.Body.Contains('PrivateNativeVideo_a_client');ContainsPrivateB=$r.Body.Contains('PrivateNativeVideo_b_client')})
    return $r.Status
}
$info=(Request 'System/Info/Public').Body | ConvertFrom-Json
if ($info.ServerName -ne 'Isolated Watch State Test' -or -not $journal.SetupReady) {throw 'Wrong or incomplete isolated fixture'}
$sessions=@{}
foreach ($owner in @('a','b')) {
    $user=@($journal.Users | Where-Object Owner -eq $owner)[0]
    $actual=(Request "Users/$($user.UserId)").Body | ConvertFrom-Json
    if ($actual.Name -ne $user.Name -or $actual.Policy.IsAdministrator) {throw 'Unexpected disposable user'}
    $login=Request 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Owner deletion test`", Device=`"Isolated`", DeviceId=`"native-owner-delete-$owner`", Version=`"1.0`""} Post @{Username=$user.Name;Pw=''}
    if ($login.Status -ne 200) {throw 'Synthetic login failed'}
    $data=$login.Body | ConvertFrom-Json
    if ($data.User.Id -ne $user.UserId) {throw 'Unexpected authenticated subject'}
    $sessions[$owner]=@{'X-Emby-Token'=$data.AccessToken}
}
$a=@($journal.Users|Where-Object Owner -eq 'a')[0]
$b=@($journal.Users|Where-Object Owner -eq 'b')[0]
$av=@($journal.Libraries|Where-Object Owner -eq 'a')[0].VideoId
$bv=@($journal.Libraries|Where-Object Owner -eq 'b')[0].VideoId
$beforePid=@(Get-Process EmbyServer)[0].Id
try {
    if ((Record 'A own metadata before deletion' "Users/$($a.UserId)/Items/$av" $sessions.a) -ne 200) {throw 'Missing A positive control'}
    if ((Record 'B own metadata before deletion' "Users/$($b.UserId)/Items/$bv" $sessions.b) -ne 200) {throw 'Missing B positive control'}
    if ((Record 'B denied A metadata before deletion' "Users/$($b.UserId)/Items/$av" $sessions.b) -ne 404) {throw 'Missing negative control'}
    if ((Request "Users/$($a.UserId)" $admin Delete).Status -notin @(200,204)) {throw 'Disposable A deletion failed'}
    $remaining=(Request 'Users').Body | ConvertFrom-Json
    if (@($remaining|Where-Object Id -eq $a.UserId).Count) {throw 'A deletion readback failed'}
    Record 'Deleted A stale token, own metadata' "Users/$($a.UserId)/Items/$av" $sessions.a | Out-Null
    Record 'B own metadata after A deletion' "Users/$($b.UserId)/Items/$bv" $sessions.b | Out-Null
    Record 'B denied orphaned A metadata' "Users/$($b.UserId)/Items/$av" $sessions.b | Out-Null
    & $control -Stop | Out-Null
    & $control | Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {
        try {$public=Request 'System/Info/Public';if (-not $RequireOrphanIsolation -or $public.Status -eq 200) {break}} catch {}
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -eq $public) {throw 'No HTTP response after restart'}
    $afterPid=@(Get-Process EmbyServer)[0].Id
    if ($afterPid -eq $beforePid) {throw 'Restart did not change process'}
    Record 'Public server info after owner deletion and restart' 'System/Info/Public' @{} | Out-Null
    Record 'B own metadata after owner deletion and restart' "Users/$($b.UserId)/Items/$bv" $sessions.b | Out-Null
    Record 'B foreign metadata after owner deletion and restart' "Users/$($b.UserId)/Items/$av" $sessions.b | Out-Null
    Record 'Deleted A stale token after restart' "Users/$($a.UserId)/Items/$av" $sessions.a | Out-Null
    if ($RequireOrphanIsolation) {
        $expected=@(200,200,404,404,200,404,200,200,404,404)
        for ($index=0;$index -lt $expected.Count;$index++) {
            if ($rows[$index].Status -ne $expected[$index]) {throw "Unexpected orphan control: $($rows[$index].Label)"}
        }
        $ready=(Request 'PersonalChannelsFixture/Guard').Body | ConvertFrom-Json
        if (-not $ready.Ready -or -not $ready.Enabled -or $ready.BootId -eq $journal.BootId) {throw 'Guard recovery not verified'}
        foreach ($row in $rows | Where-Object Status -eq 404) {
            if ($row.ContainsPrivateA -or $row.ContainsPrivateB) {throw 'Denied response exposed a marker'}
        }
    }
    $reportName=if ($RequireOrphanIsolation) {'native-owner-deletion-quarantine-results.json'} else {'native-owner-deletion-results.json'}
    @{Server=$info.ServerName;Version=$info.Version;OwnerDeletionReadback=$true;RestartVerified=$true;OrphanIsolationRequired=[bool]$RequireOrphanIsolation;Observations=$rows.ToArray();Scope='One deleted synthetic native root owner, two native libraries, metadata and old tokens; no general deleted-reference or client proof'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/$reportName") -Encoding UTF8
    $rows | ForEach-Object {[pscustomobject]$_} | Format-Table Label,Status,ContainsPrivateA,ContainsPrivateB -AutoSize
} finally {
    # Stop directly: the fixture's normal HTTP readiness check cannot pass when
    # startup rejects an orphaned persisted owner mapping.
    try {& $control -Stop | Out-Null} catch {
        $isolatedPid=[int](Get-Content -LiteralPath (Join-Path $root 'server.pid'))
        $isolatedProcess=Get-Process -Id $isolatedPid -ErrorAction SilentlyContinue
        if ($isolatedProcess) {
            $expected=[IO.Path]::GetFullPath((Join-Path $root 'server/system/EmbyServer.exe'))
            if ([IO.Path]::GetFullPath($isolatedProcess.Path) -ne $expected) {throw 'Refusing to stop unrelated process'}
            Stop-Process -Id $isolatedPid
        }
    }
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop
}
