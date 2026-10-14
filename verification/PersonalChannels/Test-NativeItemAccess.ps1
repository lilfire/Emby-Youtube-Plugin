# Probe documented native item access on disposable normal libraries, without
# the test guard. The main server is never used.
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$rows=[Collections.Generic.List[object]]::new()
function Request($label,$path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=15;UseBasicParsing=$true}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 10}
    $status=200;$text=''
    try {$response=Invoke-WebRequest @args;$status=[int]$response.StatusCode;$text=[string]$response.Content}
    catch {if (-not $_.Exception.Response) {throw};$status=[int]$_.Exception.Response.StatusCode;$text=[string]$_.ErrorDetails.Message}
    if ($label) {$rows.Add(@{Label=$label;Status=$status;ContainsPrivateA=$text.Contains('PrivateNativeVideo_a_client')})}
    return @{Status=$status;Text=$text}
}
& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') | Out-Null
try {
    $journal=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw | ConvertFrom-Json
    & $control -Stop | Out-Null
    $guardFile=[IO.Path]::GetFullPath((Join-Path $root 'data/data/personal-channels-fixture.json.guard.json'))
    if (-not $guardFile.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe synthetic guard path'}
    Remove-Item -LiteralPath $guardFile
    & $control | Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$public=Request '' 'System/Info/Public';if ($public.Status -eq 200) {break}} catch {};Start-Sleep -Milliseconds 200} while ([DateTime]::UtcNow -lt $deadline)
    $info=$public.Text | ConvertFrom-Json
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong isolated server'}
    $guard=(Request '' 'PersonalChannelsFixture/Guard').Text | ConvertFrom-Json
    if ($guard.Enabled) {throw 'Guard must be disabled for native access probe'}
    $subjects=@{}
    foreach ($owner in @('a','b')) {
        $user=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $login=Request '' 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Native access probe`", Device=`"Isolated`", DeviceId=`"native-item-access-$owner`", Version=`"1.0`""} Post @{Username=$user.Name;Pw=''}
        if ($login.Status -ne 200) {throw 'Synthetic login failed'}
        $data=$login.Text | ConvertFrom-Json
        if ($data.User.Id -ne $user.UserId -or $data.User.Policy.IsAdministrator) {throw 'Unexpected subject'}
        $subjects[$owner]=@{UserId=$user.UserId;Headers=@{'X-Emby-Token'=$data.AccessToken}}
    }
    $library=@($journal.Libraries|Where-Object Owner -eq 'a')[0]
    $av=$library.VideoId
    Request 'A own metadata, native baseline' "Users/$($subjects.a.UserId)/Items/$av" $subjects.a.Headers | Out-Null
    Request 'B foreign metadata, native baseline' "Users/$($subjects.b.UserId)/Items/$av" $subjects.b.Headers | Out-Null
    foreach ($actor in @('a','admin')) {
        $headers=if ($actor -eq 'admin') {$admin} else {$subjects.a.Headers}
        foreach ($id in @($library.LibraryId,$av)) {
            Request "$actor MakePrivate on native item $id" "Items/$id/MakePrivate" $headers Post | Out-Null
            Request "$actor Items Access None on native item $id" 'Items/Access' $headers Post @{ItemIds=@($id);UserIds=@($subjects.b.UserId);ItemAccess='None'} | Out-Null
        }
    }
    Request 'A own metadata after documented access calls' "Users/$($subjects.a.UserId)/Items/$av" $subjects.a.Headers | Out-Null
    Request 'B foreign metadata after documented access calls' "Users/$($subjects.b.UserId)/Items/$av" $subjects.b.Headers | Out-Null
    Request 'B foreign PlaybackInfo after documented access calls' "Items/$av/PlaybackInfo?UserId=$($subjects.b.UserId)" $subjects.b.Headers | Out-Null
    Request 'B foreign download after documented access calls' "Items/$av/Download" $subjects.b.Headers | Out-Null
    @{Server=$info.ServerName;Version=$info.Version;GuardEnabled=$guard.Enabled;Observations=$rows.ToArray();Scope='Documented MakePrivate and Items Access on native Folder and Video, as ordinary library user and admin; one synthetic library, no full route proof'} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/native-item-access-results.json') -Encoding UTF8
    $rows | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
} finally {& (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop}
