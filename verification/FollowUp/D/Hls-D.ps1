# Follow actual native playlist references with the requesting actor's own
# header. Strip any auth query field so A's credential is never delegated to B.
function DLocalReference($parent,$reference){
    $uri=[Uri]::new([Uri]"$base/$parent",$reference)
    if($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne 18096 -or -not $uri.AbsolutePath.StartsWith('/emby/')){throw 'Unexpected nonlocal native playlist reference'}
    $parts=@($uri.Query.TrimStart('?').Split('&')|Where-Object {$_ -and $_ -notmatch '^(?i)(api_key|token|access_token|X-Emby-Token)='})
    return $uri.AbsolutePath.Substring(6)+$(if($parts.Count){'?'+($parts -join '&')}else{''})
}
foreach($actor in @('a','b')){
    $path="Videos/$($subjects.a.VideoId)/master.m3u8?VideoCodec=h264&AudioCodec=aac&MediaSourceId=$($subjects.a.SourceId)&SegmentContainer=ts&MinSegments=1"
    $r=DResult "D HLS $actor actual master" $path $subjects[$actor].Headers
    if($actor -eq 'a'){$rows[$rows.Count-1].Remove('IsolationPass');$rows[$rows.Count-1].OwnerPlaylistPass=$r.Status -eq 200}
    $text=[Text.Encoding]::UTF8.GetString($r.Bytes)
    $refs=@($text -split '\r?\n'|Where-Object {$_ -and -not $_.StartsWith('#')})
    if($r.Status -ne 200 -or $refs.Count -ne 1){throw 'HLS master positive path unavailable'}
    $path=DLocalReference $path $refs[0]
    $r=DResult "D HLS $actor actual variant" $path $subjects[$actor].Headers
    if($actor -eq 'a'){$rows[$rows.Count-1].Remove('IsolationPass');$rows[$rows.Count-1].OwnerPlaylistPass=$r.Status -eq 200}
    $text=[Text.Encoding]::UTF8.GetString($r.Bytes)
    $refs=@($text -split '\r?\n'|Where-Object {$_ -and -not $_.StartsWith('#')})
    $rows.Add(@{Label="D HLS $actor actual variant segment references";SegmentReferences=$refs.Count})
    if($r.Status -ne 200 -or $refs.Count -eq 0){continue}
    $path=DLocalReference $path $refs[0]
    $r=DResult "D HLS $actor actual first segment" $path $subjects[$actor].Headers
    $rows[$rows.Count-1].Remove('IsolationPass')
    $file=Join-Path $dOutput ("hls-$actor.ts");$rgb=Join-Path $dOutput ("hls-$actor.rgb")
    try{
        [IO.File]::WriteAllBytes($file,$r.Bytes)
        & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel fatal -i $file -frames:v 1 -vf 'scale=1:1' -f rawvideo -pix_fmt rgb24 -y $rgb 2>$null
        $pixel=if(Test-Path $rgb){[IO.File]::ReadAllBytes($rgb)}else{[byte[]]@()}
        $blue=$pixel.Length -eq 3 -and $pixel[2] -gt 200 -and $pixel[0] -lt 30 -and $pixel[1] -lt 30
        $rows.Add(@{Label="D HLS $actor actual segment decoded A blue frame";Status=$r.Status;Bytes=$r.Bytes.Length;DecodedA=$blue;DecoderExit=$LASTEXITCODE})
    }finally{foreach($f in @($file,$rgb)){if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f}}}
}
