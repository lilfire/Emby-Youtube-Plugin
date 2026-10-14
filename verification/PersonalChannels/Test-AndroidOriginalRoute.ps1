. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
try {
    $state=Get-Content (Join-Path $PSScriptRoot 'bin/alpha-browser-state.json') -Raw|ConvertFrom-Json
    $native=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    $other=@($native.Users|Where-Object Owner -eq 'b')[0]
    $session=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="Original route verification", Device="Isolated", DeviceId="alpha-original-b", Version="1"'} Post @{Username=$other.Name;Pw=''}
    if($session.User.Id -ne $other.UserId -or $session.User.Policy.IsAdministrator){throw 'Unexpected original-route account'}
    $owner=@{'X-Emby-Token'=$state.Token};$foreign=@{'X-Emby-Token'=$session.AccessToken}
    $job=Call 'YouTubePlugin/MyJob' $owner
    if($job.State -ne 'Ready'){throw 'Original-route test requires active publication'}
    $items=Call ('Users/'+$state.UserId+'/Items?ParentId='+$job.LibraryId+'&Recursive=true&IncludeItemTypes=Video&Fields=MediaSources,Path') $owner
    $video=$items.Items[0]
    $source=$video.MediaSources[0].Id
    if(-not $source -or -not $video.Path){throw 'Native source metadata unavailable'}
    $url='Videos/'+$video.Id+'/original.mp4?MediaSourceId='+[Uri]::EscapeDataString($source)
    $cases=@(
        @{Label='Owner Android original route without Static query';Path=$url;Headers=$owner;Status=200;Method='Get'},
        @{Label='Foreign original route';Path=$url;Headers=$foreign;Status=404;Method='Get'},
        @{Label='Owner mismatched source';Path=$url.Replace([Uri]::EscapeDataString($source),'mediasource_0');Headers=$owner;Status=404;Method='Get'},
        @{Label='Owner live-stream override';Path=$url+'&LiveStreamId=synthetic-other-stream';Headers=$owner;Status=404;Method='Get'},
        @{Label='Owner regular dynamic route remains denied';Path=('Videos/'+$video.Id+'/stream.mp4?MediaSourceId='+[Uri]::EscapeDataString($source));Headers=$owner;Status=404;Method='Get'},
        @{Label='Owner original HEAD';Path=$url;Headers=$owner;Status=200;Method='Head'},
        @{Label='Owner original range';Path=$url;Headers=@{'X-Emby-Token'=$state.Token;Range='bytes=0-4095'};Status=206;Method='Get'}
    )
    $observations=@()
    foreach($case in $cases){
        $result=Request $case.Path $case.Headers $case.Method
        if($result.Status -ne $case.Status){throw ('Original-route verification failed: '+$case.Label+' status '+$result.Status)}
        $mp4=$result.Bytes.Length -ge 12 -and [Text.Encoding]::ASCII.GetString($result.Bytes,4,4) -eq 'ftyp'
        if($case.Status -in @(200,206) -and $case.Method -eq 'Get' -and -not $mp4){throw 'Allowed original payload is not MP4'}
        if($case.Status -eq 404 -and $mp4){throw 'Denied original payload contains MP4'}
        if($case.Status -eq 200 -and $case.Method -eq 'Get'){
            $sha=[Security.Cryptography.SHA256]::Create()
            try {$digest=[BitConverter]::ToString($sha.ComputeHash([byte[]]$result.Bytes)).Replace('-','')}finally{$sha.Dispose()}
            if($digest -ne (Get-FileHash -LiteralPath $video.Path).Hash){throw 'Original payload differs from owned native file'}
        }
        $observations+=@(@{Label=$case.Label;Status=$result.Status;Bytes=$result.Bytes.Length;Mp4=$mp4})
    }
    @{Completed=$true;PluginSHA256=(Get-FileHash (Join-Path $repository 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash;Observations=$observations}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot 'bin/android-original-route-results.json') -Encoding UTF8
    Write-Output ('Original-route verification passed: '+$observations.Count+' observations.')
}finally{$client.Dispose()}
