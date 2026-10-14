$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root=Join-Path $repository 'verification/WatchState/bin/emby-isolated'
$base='http://127.0.0.1:18096/emby'
$auth=Get-Content -LiteralPath (Join-Path $root 'test-auth.json') -Raw | ConvertFrom-Json
$admin=@{'X-Emby-Token'=$auth.Token}
$checks=[Collections.Generic.List[string]]::new()
$control=Join-Path $repository 'verification/EmbyFixture/Start-IsolatedServer.ps1'
$started=$false;$session=$null;$configured=$false
function Call($path,$headers=$admin,$method='Get',$body=$null) {
    $args=@{Uri="$base/$path";Headers=$headers;Method=$method;TimeoutSec=20}
    if ($null -ne $body) {$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $body -Depth 15}
    Invoke-RestMethod @args
}
function Check($condition,$label) {if (-not $condition) {throw $label};$checks.Add($label);Write-Output "PASS: $label"}
function Fetch($uri,$headers,$method='Get') {
    try {return Invoke-WebRequest -Uri $uri -Headers $headers -Method $method -UseBasicParsing -TimeoutSec 30}
    catch {if ($_.Exception.Response) {throw ('HTTP '+[int]$_.Exception.Response.StatusCode+' for HLS request')};throw 'HLS request failed before HTTP response'}
}
function Denied($uri,$headers,$label,$method='Get') {
    $status=200
    try {
        if ($headers.ContainsKey('Range')) {
            $request=[Net.HttpWebRequest]::Create($uri);$request.Method=$method;$request.Timeout=20000
            $request.Headers['X-Emby-Token']=$headers['X-Emby-Token'];$request.AddRange(0,187)
            $response=$request.GetResponse();$status=[int]$response.StatusCode;$response.Dispose()
        } else {Invoke-WebRequest -Uri $uri -Headers $headers -Method $method -UseBasicParsing -TimeoutSec 20 | Out-Null}
    }
    catch {
        $failure=$_.Exception
        while ($null -eq $failure.Response -and $failure.InnerException) {$failure=$failure.InnerException}
        if (-not $failure.Response) {throw ('Privacy request failed before HTTP response: '+$failure.GetType().Name)}
        $status=[int]$failure.Response.StatusCode
    }
    Check ($status -eq 404) "$label (HTTP $status)"
}
function ResolveClean($parent,$reference) {
    $resolved=[Uri]::new([Uri]$parent,$reference)
    if ($resolved.Host -ne '127.0.0.1' -or $resolved.Port -ne 18096) {throw 'Unexpected HLS origin'}
    # Never carry the owner's authentication into the other-user or anonymous test.
    $builder=[UriBuilder]::new($resolved)
    $builder.Query=($resolved.Query.TrimStart('?').Split('&') | Where-Object {$_ -and ($_ -split '=',2)[0] -notmatch '^(api_key|token|X-Emby-Token)$'}) -join '&'
    $builder.Uri.AbsoluteUri
}
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/net6.0/PersonalChannelsFixture.dll') -Destination (Join-Path $root 'data/plugins/PersonalChannelsFixture.dll')
    & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel error -f lavfi -i 'color=c=blue:s=160x90:r=25:d=6' -f lavfi -i 'anullsrc=r=44100:cl=stereo' -t 6 -c:v libx264 -g 25 -pix_fmt yuv420p -c:a aac -b:a 64k -y (Join-Path $root 'data/data/personal-fixture.mp4')
    if ($LASTEXITCODE -ne 0) {throw 'Synthetic video generation failed'}
    & $control;$started=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {try {$info=Call 'System/Info/Public';break} catch {Start-Sleep -Milliseconds 100}} while ([DateTime]::UtcNow -lt $deadline)
    if ($info.ServerName -ne 'Isolated Watch State Test' -or $info.Version -ne '4.10.1.0') {throw 'Wrong server'}
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="HLS privacy test", Device="Isolated test", DeviceId="hls-privacy-fixture", Version="1.0"'} Post @{Username='fixture-second';Pw=''}
    $other=@{'X-Emby-Token'=$session.AccessToken}
    Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@(@{Owner='a';Revision=1;LocalMedia=$true});Prune=$true} | Out-Null
    $configured=$true
    $channel=(Call 'Channels').Items | Where-Object Name -eq 'Personal Fixture a'
    $video=(Call "Items?ParentId=$($channel.Id)&Recursive=true&IncludeItemTypes=Video&Fields=MediaSources").Items | Select-Object -First 1
    $id=$video.Id
    Call 'PersonalChannelsFixture/Guard' $admin Post @{OwnerUserId=$auth.UserId} | Out-Null
    $playSession=[Guid]::NewGuid().ToString('N')
    $masterUri="$base/Videos/$id/master.m3u8?Container=ts&VideoCodec=h264&AudioCodec=aac&VideoBitRate=100000&AudioBitRate=64000&MaxWidth=80&MaxHeight=46&MediaSourceId=shared00001&DeviceId=hls-privacy-fixture&PlaySessionId=$playSession"
    # Select the actual source ID instead of assuming item ordering.
    $source=(Call "Items/$id/PlaybackInfo" $admin Post @{UserId=$auth.UserId;IsPlayback=$true}).MediaSources[0]
    $masterUri=$masterUri.Replace('MediaSourceId=shared00001','MediaSourceId='+[Uri]::EscapeDataString($source.Id))
    $master=Fetch $masterUri $admin
    $masterText=if ($master.Content -is [byte[]]) {[Text.Encoding]::UTF8.GetString($master.Content)} else {[string]$master.Content}
    Check ($master.StatusCode -eq 200 -and $masterText.StartsWith('#EXTM3U')) 'Owner receives real HLS master playlist'
    Denied $masterUri $other 'Other user cannot read owner HLS master'
    Denied $masterUri @{} 'Anonymous cannot read owner HLS master'
    $variant=($masterText -split '\r?\n' | Where-Object {$_ -and -not $_.StartsWith('#')} | Select-Object -First 1).Trim()
    if (-not $variant) {throw 'No variant URL in HLS master'}
    $mainUri=ResolveClean $masterUri $variant
    $main=Fetch $mainUri $admin
    $mainText=if ($main.Content -is [byte[]]) {[Text.Encoding]::UTF8.GetString($main.Content)} else {[string]$main.Content}
    Check ($main.StatusCode -eq 200 -and $mainText.Contains('#EXTINF:')) 'Owner receives real HLS media playlist'
    Denied $mainUri $other 'Other user cannot reuse owner HLS media playlist'
    Denied $mainUri @{} 'Anonymous cannot reuse owner HLS media playlist'
    $segment=($mainText -split '\r?\n' | Where-Object {$_ -and -not $_.StartsWith('#')} | Select-Object -First 1).Trim()
    $segmentUri=ResolveClean $mainUri $segment
    $response=Fetch $segmentUri $admin
    Check ($response.StatusCode -eq 200 -and $response.RawContentLength -gt 188) 'Owner receives actual HLS segment bytes'
    $segmentFile=Join-Path $PSScriptRoot 'bin/hls-owner-segment.ts'
    [IO.File]::WriteAllBytes($segmentFile,$response.RawContentStream.ToArray())
    $probe=& (Join-Path $root 'server/system/ffprobe.exe') -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of json $segmentFile | ConvertFrom-Json
    Check ($probe.streams[0].width -eq 80 -and $probe.streams[0].codec_name -eq 'h264') 'HLS video is actually transcoded from 160 to 80 pixels wide'
    Denied $segmentUri $other 'Other user cannot reuse owner HLS segment and playback session'
    Denied $segmentUri @{} 'Anonymous cannot reuse owner HLS segment and playback session'
    Denied $segmentUri $other 'Other user cannot HEAD owner HLS segment' Head
    $rangeHeaders=@{'X-Emby-Token'=$session.AccessToken;Range='bytes=0-187'}
    Denied $segmentUri $rangeHeaders 'Other user cannot request a byte range of owner HLS segment'
    $checks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/hls-results.json') -Encoding UTF8
}
finally {
    if ($started) {
        if ($playSession) {try {Call "Videos/ActiveEncodings?DeviceId=hls-privacy-fixture&PlaySessionId=$playSession" $admin Delete | Out-Null} catch {Write-Output 'Encoding cleanup request failed; isolated server will be stopped.'}}
        if ($configured) {Call 'PersonalChannelsFixture/Configure' $admin Post @{Profiles=@();Prune=$true} | Out-Null}
        if ($session) {Call 'Sessions/Logout' $other Post | Out-Null}
        & $control -Stop
    }
    foreach ($relative in @('data/plugins/PersonalChannelsFixture.dll','data/data/personal-channels-fixture.json','data/data/personal-channels-fixture.json.guard.json','data/data/personal-fixture.mp4')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative));if (-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar)) {throw 'Unsafe path'}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
