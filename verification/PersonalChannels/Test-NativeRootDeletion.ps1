param([switch]$RequireIsolation)
# Isolated investigation only. No main-server mutation or production change.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../WatchState/bin/emby-isolated'))
$control=Join-Path $PSScriptRoot '../EmbyFixture/Start-IsolatedServer.ps1'
$state=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
$auth=Get-Content (Join-Path $root 'test-auth.json') -Raw|ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token};$subjects=@{};$rows=[Collections.Generic.List[object]]::new()
function Request($path,$headers=$admin,$method='Get',$body=$null){
    $args=@{Uri=('http://127.0.0.1:18096/emby/'+$path);Headers=$headers;Method=$method;TimeoutSec=10;UseBasicParsing=$true}
    if($null -ne $body){$args.ContentType='application/json';$args.Body=$body|ConvertTo-Json -Depth 12}
    try{$r=Invoke-WebRequest @args;return @{Status=[int]$r.StatusCode;Text=$r.Content}}
    catch{if(-not $_.Exception.Response){throw};return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message}}
}
function Control($path,$headers=$admin,$method='Get',$body=$null){
    $r=Request $path $headers $method $body
    if($r.Status -lt 200 -or $r.Status -ge 300){throw 'Isolated root-deletion control failed'}
    if($r.Text){return ($r.Text|ConvertFrom-Json)}
}
function Observe($phase,$label,$path,$headers,$expected=$null){
    $r=Request $path $headers
    $correct=$false
    if($label -eq 'B own video' -and $r.Status -eq 200){
        $item=$r.Text|ConvertFrom-Json
        $correct=[string]$item.Id -eq [string]$subjects.b.Library.VideoId -and $item.Name -eq 'PrivateNativeVideo_b_client'
        if(-not $correct){throw 'Wrong surviving own video'}
    }
    $rows.Add(@{Phase=$phase;Operation=$label;Status=$r.Status;CorrectOwnVideo=$correct;ContainsPrivateA=$r.Text.Contains('PrivateNativeVideo_a_client');ContainsPrivateB=$r.Text.Contains('PrivateNativeVideo_b_client')})
    if($null -ne $expected -and $r.Status -ne $expected){throw 'Unexpected root-deletion baseline'}
    return $r
}
function CheckPlayback($phase){
    $b=$subjects.b
    $r=Request "Items/$($b.Library.VideoId)/PlaybackInfo?UserId=$($b.User.UserId)" $b.Headers
    $correct=$false
    if($r.Status -eq 200){$p=$r.Text|ConvertFrom-Json;$correct=@($p.MediaSources|Where-Object Path -eq (Join-Path $b.Library.Folder 'PrivateNativeVideo_b_client.mp4')).Count -ge 1}
    $rows.Add(@{Phase=$phase;Operation='B own PlaybackInfo';Status=$r.Status;CorrectOwnFileSource=$correct})
    if($r.Status -ne 200 -or -not $correct){throw 'Surviving owner lost playback metadata'}
}
$completed=$false;$removed=$false;$restart=$false;$ledgerReadback=$false;$guardReady=$false
try{
    $info=Control 'System/Info/Public';$guard=Control 'PersonalChannelsFixture/Guard'
    if($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Ready -or -not $guard.Enabled -or -not $state.SetupReady){throw 'Wrong isolated fixture'}
    foreach($owner in @('a','b')){
        $u=@($state.Users|Where-Object Owner -eq $owner)[0];$l=@($state.Libraries|Where-Object Owner -eq $owner)[0]
        $login=Control 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Root deletion test`", Device=`"Isolated`", DeviceId=`"root-delete-$owner`", Version=`"1.0`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary subject'}
        $subjects[$owner]=@{User=$u;Library=$l;Headers=@{'X-Emby-Token'=$login.AccessToken}}
    }
    $a=$subjects.a;$b=$subjects.b
    Observe before 'A own video' "Users/$($a.User.UserId)/Items/$($a.Library.VideoId)" $a.Headers 200|Out-Null
    Observe before 'B own video' "Users/$($b.User.UserId)/Items/$($b.Library.VideoId)" $b.Headers 200|Out-Null
    Observe before 'B foreign A video' "Users/$($b.User.UserId)/Items/$($a.Library.VideoId)" $b.Headers 404|Out-Null
    # Trusted admin mutation requires temporary admin ownership of A's root.
    # Leave that mapping persisted after deletion to exercise a missing root.
    $map=@{};$map[$a.Library.LibraryId]=$auth.UserId;$map[$b.Library.LibraryId]=$b.User.UserId
    Control 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId;RootOwnerUserIds=$map}|Out-Null
    $delete=Request 'Library/VirtualFolders/Delete' $admin Post @{Id=$a.Library.LibraryId}
    $rows.Add(@{Phase='trusted admin delete';Operation='Native DeleteVirtualFolder';Status=$delete.Status})
    if($delete.Status -notin @(200,204)){throw 'Native root deletion failed'}
    $remaining=Control 'Library/VirtualFolders/Query'
    if(@($remaining.Items|Where-Object {[string]$_.ItemId -eq [string]$a.Library.LibraryId -or $_.Name -eq $a.Library.Name}).Count){throw 'Deleted root still listed'}
    Observe 'after delete' 'Admin old root' "Items/$($a.Library.LibraryId)" $admin 404|Out-Null
    $removed=$true
    Observe 'after delete' 'B own video' "Users/$($b.User.UserId)/Items/$($b.Library.VideoId)" $b.Headers|Out-Null
    Observe 'after delete' 'B foreign old A video' "Users/$($b.User.UserId)/Items/$($a.Library.VideoId)" $b.Headers|Out-Null
    if($RequireIsolation){CheckPlayback 'after delete'}
    $oldPid=[int](Get-Content (Join-Path $root 'server.pid'))
    & $control -Stop|Out-Null
    & $control|Out-Null
    $newPid=[int](Get-Content (Join-Path $root 'server.pid'))
    if($oldPid -eq $newPid){throw 'Restart PID unchanged'}
    $deadline=[DateTime]::UtcNow.AddSeconds(30);$readyResponse=$null
    do{
        try{
            $readyResponse=Request 'System/Info/Public'
            $guardResponse=Request 'PersonalChannelsFixture/Guard'
            if($readyResponse.Status -eq 200 -and $guardResponse.Status -eq 200){
                $readyGuard=$guardResponse.Text|ConvertFrom-Json
                if($readyGuard.Ready -and $readyGuard.Enabled -and $readyGuard.BootId -ne $guard.BootId){break}
            }
        }catch{}
        Start-Sleep -Milliseconds 150
    }while([DateTime]::UtcNow -lt $deadline)
    if($null -eq $readyResponse){throw 'No HTTP response after restart'}
    $restart=$true
    Observe 'after restart' 'Public server info' 'System/Info/Public' @{}|Out-Null
    Observe 'after restart' 'Guard readiness endpoint' 'PersonalChannelsFixture/Guard' $admin|Out-Null
    Observe 'after restart' 'B own video' "Users/$($b.User.UserId)/Items/$($b.Library.VideoId)" $b.Headers|Out-Null
    Observe 'after restart' 'B foreign old A video' "Users/$($b.User.UserId)/Items/$($a.Library.VideoId)" $b.Headers|Out-Null
    if($RequireIsolation){
        $g=Control 'PersonalChannelsFixture/Guard'
        $guardReady=$g.Ready -and $g.Enabled -and $g.BootId -ne $guard.BootId
        if(-not $guardReady){throw 'Guard did not recover after root deletion'}
        $expected=@(200,200,404,204,404,200,404,200,200,200,200,404)
        for($i=0;$i -lt $expected.Count;$i++){if($rows[$i].Status -ne $expected[$i]){throw 'Root-deletion recovery status failed'}}
        CheckPlayback 'after restart'
        Observe 'after restart' 'A own old deleted video' "Users/$($a.User.UserId)/Items/$($a.Library.VideoId)" $a.Headers 404|Out-Null
        Observe 'after restart' 'B old deleted root' "Users/$($b.User.UserId)/Items/$($a.Library.LibraryId)" $b.Headers 404|Out-Null
        $ledger=Get-Content (Join-Path $root 'data/data/personal-channels-fixture.json.native-reference-owners.json') -Raw|ConvertFrom-Json
        $collections=@($ledger.Collections.PSObject.Properties|ForEach-Object Value)
        $deleted=@($collections|Where-Object RootKey -eq $a.Library.LibraryId)
        $active=@($collections|Where-Object RootKey -eq $b.Library.LibraryId)
        $ledgerReadback=$ledger.Version -eq 1 -and $deleted.Count -eq 1 -and $deleted[0].Deleted -and [string]$a.Library.VideoId -in $deleted[0].References -and $active.Count -eq 1 -and -not $active[0].Deleted -and $active[0].OwnerGuid -eq $b.User.UserId -and [string]$b.Library.VideoId -in $active[0].References
        if(-not $ledgerReadback){throw 'Deleted collection or surviving provenance did not persist'}
        foreach($row in @($rows|Where-Object Status -eq 404)){if($row.ContainsPrivateA -or $row.ContainsPrivateB){throw 'Denied root-deletion response exposed private marker'}}
    }
    $completed=$true
}finally{
    $report=if($RequireIsolation){'bin/native-root-deletion-durable-results.json'}else{'bin/native-root-deletion-results.json'}
    @{Completed=$completed;RequireIsolation=$RequireIsolation.IsPresent;RootDeletionReadback=$removed;RestartVerified=$restart;GuardRecovered=$guardReady;DeletedCollectionLedgerReadback=$ledgerReadback;TrustedTemporaryAdminOwnership=$true;Scope='Deleted synthetic native root with persisted root mapping; metadata and restart only';Observations=$rows}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot $report) -Encoding UTF8
    try{& $control -Stop|Out-Null}catch{
        $isolatedPid=[int](Get-Content (Join-Path $root 'server.pid'))
        $proc=Get-Process -Id $isolatedPid -ErrorAction SilentlyContinue
        if($proc){
            $expected=[IO.Path]::GetFullPath((Join-Path $root 'server/system/EmbyServer.exe'))
            if([IO.Path]::GetFullPath($proc.Path) -ne $expected){throw 'Refusing to stop unrelated process'}
            Stop-Process -Id $isolatedPid
            $proc.WaitForExit(10000)|Out-Null
        }
    }
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
}
$rows|ForEach-Object {[pscustomobject]$_}|Format-Table Phase,Operation,Status,CorrectOwnVideo -AutoSize
