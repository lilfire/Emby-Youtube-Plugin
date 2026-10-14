param([switch]$ProbeSourceMismatch)
# Requires the disposable Start-NativeClientFixture.ps1 -MediaAssets setup.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Web
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$base='http://127.0.0.1:18096/emby/'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$journal=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw | ConvertFrom-Json
$rows=[Collections.Generic.List[object]]::new()
$subjects=@{}
function Request($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri=$base+$path;Headers=$headers;Method=$method;TimeoutSec=30;UseBasicParsing=$true}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 10}
    try {
        $response=Invoke-WebRequest @args
        $stream=$response.RawContentStream;$stream.Position=0
        $memory=New-Object IO.MemoryStream;$stream.CopyTo($memory);$bytes=$memory.ToArray();$memory.Dispose()
        return @{Status=[int]$response.StatusCode;Text=[Text.Encoding]::UTF8.GetString($bytes);Bytes=$bytes;ContentType=[string]$response.Headers['Content-Type']}
    } catch {
        if (-not $_.Exception.Response) {throw}
        return @{Status=[int]$_.Exception.Response.StatusCode;Text=[string]$_.ErrorDetails.Message;Bytes=@();ContentType=[string]$_.Exception.Response.ContentType}
    }
}
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $r=Request $path $headers $method $body
    if ($r.Status -notin @(200,204)) {throw "Control HTTP $($r.Status): $path"}
    if ($r.Text) {return $r.Text | ConvertFrom-Json}
}
function Digest([byte[]]$bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try {[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')} finally {$sha.Dispose()}
}
function Check($label,$path,$headers,$expected,$kind,$owner) {
    $r=Request $path $headers
    $row=@{Label=$label;Path=$path;Status=$r.Status;Expected=$expected;ContentType=$r.ContentType;Bytes=$r.Bytes.Length;ContainsPrivateA=($r.Text.Contains('PrivateSubtitle_a_native_media') -or $r.Text.Contains('PrivateNativeVideo_a_client'));ContainsPrivateB=($r.Text.Contains('PrivateSubtitle_b_native_media') -or $r.Text.Contains('PrivateNativeVideo_b_client'))}
    if ($kind -eq 'segment') {$row.Prefix=@($r.Bytes|Select-Object -First 8)}
    $rows.Add($row)
    if ($expected -eq 200) {
        if ($kind -eq 'subtitle' -and -not $r.Text.Contains("PrivateSubtitle_${owner}_native_media")) {throw 'Own subtitle marker missing'}
        if ($kind -eq 'image') {
            if ($r.Bytes.Length -lt 100 -or $r.Bytes[0] -ne 137 -or $r.Bytes[1] -ne 80 -or -not $r.ContentType.Contains('image/')) {throw 'No positive PNG image payload'}
            $row.MatchesUploadedSource=(Digest $r.Bytes) -eq $subjects[$owner].ImageHash
            if (-not $row.MatchesUploadedSource) {throw 'Own image differs from uploaded synthetic source'}
        }
        if ($kind -eq 'manifest' -and -not $r.Text.StartsWith('#EXTM3U')) {throw 'No positive HLS manifest'}
        if ($kind -eq 'segment' -and ($r.Bytes.Length -lt 188 -or $r.Bytes[0] -ne 71)) {throw 'No positive MPEG TS segment'}
    }
    if ($r.Status -ne $expected) {throw "Unexpected media response: $label HTTP $($r.Status)"}
    if ($expected -eq 404 -and ($row.ContainsPrivateA -or $row.ContainsPrivateB -or $r.Bytes.Length)) {throw 'Foreign media payload was returned'}
    return $r
}
function CheckThree($phase,$owner,$kind,$path) {
    $other=if ($owner -eq 'a') {'b'} else {'a'}
    $own=Check "$phase $owner own $kind" $path $subjects[$owner].Headers 200 $kind $owner
    Check "$phase $other foreign $owner $kind" $path $subjects[$other].Headers 404 $kind $owner | Out-Null
    Check "$phase anonymous $owner $kind" $path @{} 404 $kind $owner | Out-Null
    return $own
}
function ChildPath($parentPath,$manifest) {
    $line=@($manifest.Split([char]10)|ForEach-Object Trim|Where-Object {$_ -and -not $_.StartsWith('#')})[0]
    if (-not $line) {throw 'HLS manifest has no child resource'}
    $parent=New-Object Uri ($base+$parentPath)
    $child=New-Object Uri ($parent,$line)
    if ($child.Scheme -ne 'http' -or $child.Host -ne '127.0.0.1' -or $child.Port -ne 18096 -or -not $child.AbsolutePath.StartsWith('/emby/')) {throw 'Unexpected HLS destination'}
    $query=[Web.HttpUtility]::ParseQueryString($child.Query)
    foreach ($key in @($query.AllKeys)) {if ($key -match '(?i)token|api.?key|authorization') {$query.Remove($key)}}
    $path=$child.AbsolutePath.Substring('/emby/'.Length)
    if ($query.Count) {$path+='?'+$query.ToString()}
    return $path
}
function Phase($phase) {
    foreach ($owner in @('a','b')) {
        $subject=$subjects[$owner]
        $info=Call "Items/$($subject.VideoId)/PlaybackInfo" $subject.Headers Post @{UserId=$subject.UserId;DeviceId=$subject.DeviceId;EnableDirectPlay=$false;EnableDirectStream=$false;EnableTranscoding=$true;IsPlayback=$true}
        $source=@($info.MediaSources)[0]
        $subtitle=@($source.MediaStreams|Where-Object {$_.Type -eq 'Subtitle' -and $_.IsExternal})
        if (-not $source.Id -or $subtitle.Count -ne 1) {throw 'No positive external subtitle source'}
        if (-not $info.PlaySessionId) {throw 'No native playback session for HLS'}
        $subject.SourceId=$source.Id;$subject.SubtitleIndex=$subtitle[0].Index
        CheckThree $phase $owner 'image' "Items/$($subject.VideoId)/Images/Primary" | Out-Null
        CheckThree $phase $owner 'subtitle' "Videos/$($subject.VideoId)/$($source.Id)/Subtitles/$($subtitle[0].Index)/Stream.srt" | Out-Null
        $masterPath="Videos/$($subject.VideoId)/master.m3u8?MediaSourceId=$($source.Id)&PlaySessionId=$($info.PlaySessionId)&DeviceId=$($subject.DeviceId)&VideoCodec=h264&AudioCodec=aac&VideoBitrate=64000&AudioBitrate=32000&MaxWidth=160&MaxHeight=90&SegmentContainer=ts&SegmentLength=2&MinSegments=1&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false"
        $master=CheckThree $phase $owner 'manifest' $masterPath
        $playlistPath=ChildPath $masterPath $master.Text
        $playlist=CheckThree $phase $owner 'manifest' $playlistPath
        $segmentPath=ChildPath $playlistPath $playlist.Text
        CheckThree $phase $owner 'segment' $segmentPath | Out-Null
    }
    if ($ProbeSourceMismatch) {
        foreach ($owner in @('a','b')) {
            $other=if ($owner -eq 'a') {'b'} else {'a'}
            $subject=$subjects[$owner];$foreign=$subjects[$other].SourceId
            $missing='mediasource_999999999'
            $prefix="Videos/$($subject.VideoId)/"
            $suffix="/Subtitles/$($subject.SubtitleIndex)/Stream.srt"
            $hidden=Request ($prefix+$foreign+$suffix) $subject.Headers
            $absent=Request ($prefix+$missing+$suffix) $subject.Headers
            $exposed=$hidden.Text.Contains("PrivateSubtitle_${other}_native_media") -or $hidden.Text.Contains("PrivateNativeVideo_${other}_client")
            $same=$hidden.Status -eq $absent.Status -and $hidden.Text.Replace($foreign,'[source]') -eq $absent.Text.Replace($missing,'[source]')
            $rows.Add(@{Label="$phase $owner own item foreign subtitle source";Status=$hidden.Status;MissingStatus=$absent.Status;ContainsForeignPrivateMarker=$exposed;SameAsMissing=$same;ForeignResponseBytes=$hidden.Bytes.Length;MissingResponseBytes=$absent.Bytes.Length})
            if ($exposed -or -not $same) {throw 'Foreign media-source mismatch not isolated from missing source'}
        }
    }
}
try {
    $info=Call 'System/Info/Public'
    $guard=Call 'PersonalChannelsFixture/Guard'
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0' -or -not $guard.Ready -or -not $guard.Enabled -or -not $journal.SetupReady) {throw 'Wrong isolated media fixture'}
    foreach ($owner in @('a','b')) {
        $user=@($journal.Users|Where-Object Owner -eq $owner)[0]
        $library=@($journal.Libraries|Where-Object Owner -eq $owner)[0]
        $device="native-media-assets-$owner"
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Media assets test`", Device=`"Isolated`", DeviceId=`"$device`", Version=`"1.0`""} Post @{Username=$user.Name;Pw=''}
        if ($login.User.Id -ne $user.UserId -or $login.User.Policy.IsAdministrator) {throw 'Unexpected synthetic subject'}
        $image=Join-Path $library.Folder "fixture-primary-$owner.png"
        $subjects[$owner]=@{Headers=@{'X-Emby-Token'=$login.AccessToken};UserId=$user.UserId;VideoId=$library.VideoId;DeviceId=$device;ImageHash=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash}
    }
    Phase 'Before restart'
    $oldBoot=$guard.BootId
    & $control -Stop | Out-Null
    & $control | Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$guard=Call 'PersonalChannelsFixture/Guard';if ($guard.Ready -and $guard.Enabled -and $guard.BootId -ne $oldBoot) {break}} catch {};Start-Sleep -Milliseconds 200} while ([DateTime]::UtcNow -lt $deadline)
    if (-not $guard.Ready -or $guard.BootId -eq $oldBoot) {throw 'Media guard restart not verified'}
    Phase 'After restart'
    $passed=$true
} finally {
    $reportName=if ($ProbeSourceMismatch) {'native-media-assets-source-mismatch-results.json'} else {'native-media-assets-results.json'}
    @{Version='4.10.1.0';Passed=($passed -eq $true);SourceMismatchRequested=[bool]$ProbeSourceMismatch;Observations=$rows.ToArray();Scope='Own PNG, external SRT, HLS master/media manifest and first MPEG TS segment; both owners, foreign and anonymous; optional mixed item/source IDs; no all-format/client proof'} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "bin/$reportName") -Encoding UTF8
    $rows|ForEach-Object {[pscustomobject]$_}|Format-Table Label,Status,Bytes,MatchesUploadedSource -AutoSize
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop
}
