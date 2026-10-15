$endpoint='PersonalChannelsFixture/DVideoBoundary'
$target=@{ItemId=[long]$subjects.a.VideoId;ForeignItemId=[long]$subjects.b.VideoId}
$arm=$target.Clone();$arm.Phase=$BoundaryPhase
Call $endpoint $admin Post $arm|Out-Null
$message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,"$base/$(StreamPath 'a')")
foreach($key in $subjects.a.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$subjects.a.Headers[$key])|Out-Null}
$message.Headers.TryAddWithoutValidation('X-Isolated-D-Boundary','pause')|Out-Null
$pending=$client.SendAsync($message)
$mutated=$false;$restoreFile=$null;$fileBytes=$null;$fileTime=$null
try{
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    do{$pause=Call $endpoint;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
    if(-not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'D actual native boundary not reached'}
    $rows.Add(@{Label='D actual native boundary reached';Phase=$BoundaryPhase;Mutation=$BoundaryMutation;HttpPending=$true})
    if($BoundaryMutation -in @('Path','Parent')){
        $input=$target.Clone();$input.Mutation=$BoundaryMutation
        $changed=Call $endpoint $admin Post $input;$mutated=$true
        $rows.Add(@{Label='D actual native metadata mutation readback';Mutation=$BoundaryMutation;PathIsForeign=$changed.PersistedPathIsForeign;ParentIsForeign=$changed.PersistedParentIsForeign})
        if($BoundaryMutation -eq 'Path' -and -not $changed.PersistedPathIsForeign -or $BoundaryMutation -eq 'Parent' -and -not $changed.PersistedParentIsForeign){throw 'Native mutation readback failed'}
    }elseif($BoundaryMutation -eq 'Token'){
        $r=Request ('Auth/Keys/'+$subjects.a.Headers['X-Emby-Token']) $admin Delete
        if($r.Status -notin @(200,204)){throw 'Boundary token revoke failed'}
        $rows.Add(@{Label='D token revoke completed during native boundary';Status=$r.Status})
    }else{
        $restoreFile=if($BoundaryMutation -eq 'File'){$subjects.a.SourcePath}else{Join-Path $profileRoot 'native-reference-bindings.json'}
        $resolved=[IO.Path]::GetFullPath($restoreFile)
        $expected=[IO.Path]::GetFullPath($(if($BoundaryMutation -eq 'File'){$subjects.a.SourcePath}else{Join-Path $profileRoot 'native-reference-bindings.json'}))
        if($resolved -ne $expected -or -not(Test-Path -LiteralPath $resolved)){throw 'Unexpected boundary mutation file'}
        $fileBytes=[IO.File]::ReadAllBytes($resolved);$fileTime=[IO.File]::GetLastWriteTimeUtc($resolved)
        try{
            $replacement=if($BoundaryMutation -eq 'File'){[IO.File]::ReadAllBytes($subjects.b.SourcePath)}else{[Text.Encoding]::UTF8.GetBytes('{invalid-d-journal}')}
            [IO.File]::WriteAllBytes($resolved,$replacement);[IO.File]::SetLastWriteTimeUtc($resolved,$fileTime)
            $rows.Add(@{Label='D native boundary file mutation';Mutation=$BoundaryMutation;WriteSucceeded=$true;ReplacementHashReadback=((Get-FileHash -LiteralPath $resolved).Hash -eq (Hash $replacement))})
        }catch [IO.IOException]{
            $rows.Add(@{Label='D native boundary file mutation';Mutation=$BoundaryMutation;WriteSucceeded=$false;WindowsSharingLock=$true})
        }
    }
    if($BoundaryMutation -eq 'Journal'){
        DResult 'D corrupt bindings independent B owner' (StreamPath 'b') $subjects.b.Headers Get 'b'|Out-Null
    }else{OwnStreams 'D native boundary independent B' 'b'}
}finally{Call $endpoint $admin Post @{Release=$true}|Out-Null}
try{
    $response=$pending.GetAwaiter().GetResult()
    try{
        $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $entity=@((@($response.Headers|ForEach-Object Key)+@($response.Content.Headers|ForEach-Object Key))|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
        $rows.Add(@{Label='D actual native boundary HTTP result';Phase=$BoundaryPhase;Mutation=$BoundaryMutation;Status=[int]$response.StatusCode;Bytes=$bytes.Length;MatchesA=((Hash $bytes) -eq $subjects.a.SourceHash);MatchesB=((Hash $bytes) -eq $subjects.b.SourceHash);EntityHeaderCount=$entity.Count;GenericDenial=([Text.Encoding]::UTF8.GetString($bytes) -in @('Item not found.','Items not found.'))})
    }finally{$response.Dispose()}
}finally{
    if($mutated){$input=$target.Clone();$input.Mutation='Restore';$restored=Call $endpoint $admin Post $input;if(-not $restored.Restored){throw 'Native restore readback failed'}}
    if($restoreFile -and $fileBytes){
        if((Get-FileHash -LiteralPath $restoreFile).Hash -ne (Hash $fileBytes)){[IO.File]::WriteAllBytes($restoreFile,$fileBytes)}
        [IO.File]::SetLastWriteTimeUtc($restoreFile,$fileTime)
        if((Get-FileHash -LiteralPath $restoreFile).Hash -ne (Hash $fileBytes)){throw 'Boundary file restore hash failed'}
    }
    $message.Dispose()
}
if($BoundaryMutation -eq 'Token'){
    DDenied 'D boundary completed token revoke'
}else{
    DResult 'D native boundary restored A source' (StreamPath 'a') $subjects.a.Headers Get 'a'|Out-Null
    DResult 'D native boundary restored foreign control' (StreamPath 'a') $subjects.b.Headers|Out-Null
}
