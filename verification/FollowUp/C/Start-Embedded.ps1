$starter=Get-Content (Join-Path $assetScripts 'Start-NativeClientFixture.ps1') -Raw
$starter=$starter.Replace('$PSScriptRoot','$assetScripts')
$seam="        `$collectionType=if(`$Movies)"
if(([regex]::Matches($starter,[regex]::Escape($seam))).Count -ne 1){throw 'Embedded scan seam changed'}
$insert=@'
        # Genuine FFmpeg mov_text stream in the synthetic MP4; remove sidecar
        # before native scanning so IsExternal=false is a meaningful control.
        $embeddedTemp=Join-Path $folder 'embedded-temp.mp4'
        try{
            & (Join-Path $root 'server/system/ffmpeg.exe') -hide_banner -loglevel error -i $media -i $subtitle -map 0:v -map 0:a -map 1:0 -c:v copy -c:a copy -c:s mov_text -metadata:s:s:0 language=eng -y $embeddedTemp
            if($LASTEXITCODE -ne 0){throw 'Embedded subtitle generation failed'}
            Move-Item -LiteralPath $embeddedTemp -Destination $media -Force
            Remove-Item -LiteralPath $subtitle
        }finally{Remove-Item -LiteralPath $embeddedTemp -ErrorAction SilentlyContinue}
'@
$starter=$starter.Replace($seam,$insert+"`n"+$seam)
& ([scriptblock]::Create($starter)) -MediaAssets
