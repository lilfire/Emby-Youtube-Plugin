foreach($format in @('png','jpg','gif')){
    foreach($owner in @('a','b')){
        $other=if($owner -eq 'a'){'b'}else{'a'}
        $path="Items/$($subjects[$owner].VideoId)/Images/Primary?MaxWidth=80&MaxHeight=45&Format=$format"
        $r=Request $path $subjects[$owner].Headers
        $memory=[IO.MemoryStream]::new([byte[]]$r.Bytes,$false);$image=$null;$matches=$false;$actualFormat=''
        try{
            $image=[Drawing.Image]::FromStream($memory)
            $actualFormat=$image.RawFormat.ToString()
            $pixel=$image.GetPixel(40,22)
            $matches=$image.Width -eq 80 -and $image.Height -eq 45 -and $(if($owner -eq 'a'){$pixel.B -gt 200 -and $pixel.R -lt 30}else{$pixel.R -gt 200 -and $pixel.B -lt 30})
        }catch{}finally{if($image){$image.Dispose()};$memory.Dispose()}
        $negative=Request $path $subjects[$other].Headers
        $rows.Add(@{Label='C image output format paired control';Format=$format;ActualDecodedFormat=$actualFormat;Owner=$owner;Status=$r.Status;DecodedOwnerContent=$matches;ForeignStatus=$negative.Status;IsolationPass=($r.Status -eq 200 -and $matches -and $negative.Status -eq 404 -and $negative.Text -eq 'Item not found.')})
    }
}
foreach($format in @('srt','vtt','ass','ssa')){
    foreach($owner in @('a','b')){
        $other=if($owner -eq 'a'){'b'}else{'a'}
        $s=$subjects[$owner]
        $path="Videos/$($s.VideoId)/$($s.SourceId)/Subtitles/$($s.SubtitleIndex)/Stream.$format"
        $r=Request $path $s.Headers
        $text=[Text.Encoding]::UTF8.GetString($r.Bytes)
        $matches=$text.Contains("PrivateSubtitle_${owner}_native_media") -and -not $text.Contains("PrivateSubtitle_${other}_native_media")
        $negative=Request $path $subjects[$other].Headers
        $rows.Add(@{Label='C subtitle output format paired control';Format=$format;Owner=$owner;Embedded=($Mode -eq 'Embedded');Status=$r.Status;ContainsOwnerContent=$matches;ForeignStatus=$negative.Status;IsolationPass=($r.Status -eq 200 -and $matches -and $negative.Status -eq 404 -and $negative.Text -eq 'Item not found.')})
    }
}
