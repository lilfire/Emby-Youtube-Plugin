param([switch]$RequireIsolation,[ValidateSet('None','Image','Subtitle')][string]$WriterRace='None',[switch]$AfterWriteCheckRace,[switch]$HttpVariants,[ValidateSet('None','Image','Subtitle')][string]$TraceSource='None',[switch]$InspectProcessing,[switch]$TraceDerived,[switch]$InjectSourceMismatch,[switch]$DerivedAssets,[switch]$ProbeProducerOutput,[switch]$ProbeCachePath)
if($ProbeCachePath -and -not $ProbeProducerOutput){throw 'Cache path fault uses the producer probe with its actual B output control'}
if($DerivedAssets -and $TraceSource -ne 'None'){throw 'Derived lifecycle matrix must run separately from source tracing'}
if($ProbeProducerOutput -and (-not $DerivedAssets -or $WriterRace -ne 'None' -or $HttpVariants)){throw 'Producer output probe requires a separate derived lifecycle matrix'}
if($InjectSourceMismatch -and ($TraceSource -eq 'None' -or $TraceDerived)){throw 'Original asset mismatch requires an original source trace target'}
if($TraceDerived -and $TraceSource -eq 'None'){throw 'Derived trace requires an asset source target'}
if($AfterWriteCheckRace -and $WriterRace -eq 'None'){throw 'After-check test requires an asset writer target'}
# Actual local image/SRT bytes with production bindings, no experimental guard.
. (Join-Path $PSScriptRoot 'NativeReadyHelpers.ps1')
$profileRoot=Join-Path $root 'data/data/youtube-personal'
if(Test-Path $profileRoot){throw 'Media asset test requires absent isolated profiles'}
function AssetPath($subject,$kind){
    if($kind -eq 'image'){
        $path="Items/$($subject.VideoId)/Images/Primary"
        if($DerivedAssets){$path+='?MaxWidth=80&MaxHeight=45&Format=png'}
        return $path
    }
    $format=if($DerivedAssets){'vtt'}else{'srt'}
    return "Videos/$($subject.VideoId)/$($subject.SourceId)/Subtitles/$($subject.SubtitleIndex)/Stream.$format"
}
function PayloadMatches($bytes,$kind,$owner){
    if($kind -eq 'subtitle'){
        $text=[Text.Encoding]::UTF8.GetString([byte[]]$bytes)
        $other=if($owner -eq 'a'){'b'}else{'a'}
        return $text.Contains("PrivateSubtitle_${owner}_native_media") -and -not $text.Contains("PrivateSubtitle_${other}_native_media") -and (-not $DerivedAssets -or $text.TrimStart([char]0xfeff).StartsWith('WEBVTT'))
    }
    if(-not $DerivedAssets){
        $sha=[Security.Cryptography.SHA256]::Create()
        try{return [BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes)).Replace('-','') -eq $subjects[$owner].ImageHash}finally{$sha.Dispose()}
    }
    # Decode the actual response; a status or nonempty payload is not enough.
    Add-Type -AssemblyName System.Drawing
    $memory=[IO.MemoryStream]::new([byte[]]$bytes,$false);$image=$null
    try{
        $image=[Drawing.Image]::FromStream($memory)
        if($bytes.Length -le 8 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $image.Width -ne 80 -or $image.Height -ne 45){return $false}
        foreach($point in @(@(0,0),@(40,22),@(79,44))){
            $pixel=$image.GetPixel($point[0],$point[1])
            $valid=if($owner -eq 'a'){$pixel.B -gt 200 -and $pixel.R -lt 30 -and $pixel.G -lt 30}else{$pixel.R -gt 200 -and $pixel.B -lt 30 -and $pixel.G -lt 30}
            if(-not $valid){return $false}
        }
        return $true
    }catch{return $false}finally{if($image){$image.Dispose()};$memory.Dispose()}
}
function Asset($phase,$actor,$owner,$kind,$allowed){
    $s=$subjects[$owner]
    $path=AssetPath $s $kind
    $headers=if($actor -eq 'anonymous'){@{}}else{$subjects[$actor].Headers}
    $r=Request $path $headers
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$r.Bytes)).Replace('-','')}finally{$sha.Dispose()}
    $text=[Text.Encoding]::UTF8.GetString($r.Bytes)
    $matches=PayloadMatches $r.Bytes $kind $owner
    $entity=@($r.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
    $generic=$r.Text -eq 'Item not found.' -and $r.Bytes.Length -eq 15
    $pass=if($allowed){$r.Status -eq 200 -and $matches}else{$r.Status -eq 404 -and $generic -and -not $matches -and -not $text.Contains('PrivateNativeVideo_') -and -not $text.Contains('PrivateSubtitle_') -and $entity.Count -eq 0}
    $rows.Add(@{Label="$phase $actor target $owner $kind";Allowed=$allowed;Status=$r.Status;Bytes=$r.Bytes.Length;MatchesPrivateSource=$matches;GenericDenial=$generic;EntityHeaderCount=$entity.Count;IsolationPass=$pass})
    if($allowed -and -not $pass){
        $state=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $rows.Add(@{Label='Production source state at failed asset positive control';AssetSources=$state.AssetSources;StaticSources=$state.StaticSources})
        throw 'Own media asset positive control failed'
    }
    if($TraceSource -ne 'None' -and $phase -eq 'Active' -and $actor -eq 'a' -and $owner -eq 'a' -and $kind -eq $TraceSource.ToLowerInvariant()){
        $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $foreign=if($InjectSourceMismatch){[long]$subjects.b.VideoId}else{0}
        Call 'PersonalChannelsFixture/NativeStaticFactoryTrace' $admin Post @{OwnerUserId=$s.UserId;ItemId=[long]$s.VideoId;ForeignItemId=$foreign;Asset=$TraceSource}|Out-Null
        $marked=$headers.Clone();$marked['X-Isolated-Static-Factory']=if($InjectSourceMismatch){'inject'}else{'trace'}
        $tracePath=if($TraceDerived){if($TraceSource -eq 'Image'){$path+'?MaxWidth=80&MaxHeight=45&Format=png'}else{$path.Replace('Stream.srt','Stream.vtt')}}else{$path}
        $traced=Request $tracePath $marked
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$tracedHash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$traced.Bytes)).Replace('-','')}finally{$sha.Dispose()}
        $derivedValid=$false
        if($TraceDerived -and $TraceSource -eq 'Image'){
            Add-Type -AssemblyName System.Drawing
            $memory=[IO.MemoryStream]::new([byte[]]$traced.Bytes,$false)
            $image=$null
            try{
                $image=[Drawing.Image]::FromStream($memory)
                $pixel=$image.GetPixel(0,0)
                $derivedValid=$traced.Bytes.Length -gt 8 -and $traced.Bytes[0] -eq 137 -and $traced.Bytes[1] -eq 80 -and $image.Width -eq 80 -and $image.Height -eq 45 -and $pixel.B -gt 200 -and $pixel.R -lt 30 -and $pixel.G -lt 30
            }finally{if($image){$image.Dispose()};$memory.Dispose()}
        }
        if($TraceDerived -and $TraceSource -eq 'Subtitle'){
            $text=[Text.Encoding]::UTF8.GetString($traced.Bytes)
            $derivedValid=$text.TrimStart([char]0xfeff).StartsWith('WEBVTT') -and $text.Contains('PrivateSubtitle_a_native_media') -and -not $text.Contains('PrivateSubtitle_b_native_media')
        }
        if(-not $InjectSourceMismatch -and ($traced.Status -ne 200 -or (-not $TraceDerived -and $tracedHash -ne $hash) -or ($TraceDerived -and -not $derivedValid))){throw 'Traced asset positive source changed'}
        $trace=Call 'PersonalChannelsFixture/NativeStaticFactoryTrace'
        if($InjectSourceMismatch){
            $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
            $entities=@($traced.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
            $delta=$after.StaticSources.IoCalls-$before.StaticSources.IoCalls
            $safe=$trace.Injected -eq 1 -and $traced.Status -eq 404 -and $traced.Text -eq 'Item not found.' -and $traced.Bytes.Length -eq 15 -and $entities.Count -eq 0 -and $delta -eq 0 -and $after.StaticSources.Installed -and $after.AssetSources.Installed
            $rows.Add(@{Label='Actual injected asset source mismatch';Kind=$TraceSource;Injected=$trace.Injected;Status=$traced.Status;Bytes=$traced.Bytes.Length;EntityHeaderCount=$entities.Count;IoCallsDelta=$delta;IsolationPass=$safe})
            if(-not $safe){throw 'Actual injected asset source mismatch not isolated'}
        }
        $rows.Add(@{Label='Actual asset static factory trace';Kind=$TraceSource;Status=$traced.Status;Bytes=$traced.Bytes.Length;OwnSourceMatches= -not [bool]$InjectSourceMismatch;Derived=[bool]$TraceDerived;DerivedValid=$derivedValid;Events=$trace.Events;Installed=$trace.Installed})
        if(-not $trace.Installed -or @($trace.Events).Count -eq 0){throw 'Actual marked asset did not reach traced factory methods'}
    }
    if($HttpVariants){
        if($allowed){
            if(-not $r.ETag){throw 'Allowed asset has no native ETag positive control'}
            $s[('ETag_'+$kind)]=$r.ETag
            $s[('Length_'+$kind)]=$r.Bytes.Length
            $s[('FullHash_'+$kind)]=$hash
            $s[('Prefix_'+$kind)]=[Convert]::ToBase64String([byte[]]($r.Bytes[0..31]))
        }
        $validator=$s[('ETag_'+$kind)]
        if(-not $validator){throw 'Asset native validator baseline missing'}
        foreach($variant in @('Head','Conditional','Range')){
            $variantHeaders=$headers.Clone()
            if($variant -eq 'Conditional'){$variantHeaders['If-None-Match']=$validator}
            if($variant -eq 'Range'){$variantHeaders.Range='bytes=0-31'}
            $method=if($variant -eq 'Head'){'Head'}else{'Get'}
            $v=Request $path $variantHeaders $method
            $entities=@($v.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
            $valid=if($allowed){
                if($variant -eq 'Head'){$v.Status -eq 200 -and $v.Bytes.Length -eq 0 -and $v.ContentLength -eq $s[('Length_'+$kind)] -and $v.ETag -eq $validator}
                elseif($variant -eq 'Conditional'){$v.Status -eq 304 -and $v.Bytes.Length -eq 0 -and $v.ETag -eq $validator}
                else{
                    if($v.Status -eq 206){$v.Bytes.Length -eq 32 -and $v.ContentRange -eq "bytes 0-31/$($s[('Length_'+$kind)])" -and [Convert]::ToBase64String([byte[]]$v.Bytes) -eq $s[('Prefix_'+$kind)]}
                    else{
                        $sha=[Security.Cryptography.SHA256]::Create()
                        try{$rangeHash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$v.Bytes)).Replace('-','')}finally{$sha.Dispose()}
                        $v.Status -eq 200 -and $rangeHash -eq $s[('FullHash_'+$kind)]
                    }
                }
            }else{
                $generic=if($variant -eq 'Head'){$v.Bytes.Length -eq 0}else{$v.Text -eq 'Item not found.' -and $v.Bytes.Length -eq 15}
                $v.Status -eq 404 -and $generic -and $entities.Count -eq 0 -and -not $v.PrivateAHeader -and -not $v.PrivateBHeader
            }
            $rows.Add(@{Label="$phase $actor target $owner $kind $variant";Allowed=$allowed;Variant=$variant;Status=$v.Status;Bytes=$v.Bytes.Length;EntityHeaderCount=$entities.Count;ContentLength=$v.ContentLength;ContentRange=$v.ContentRange;RangeApplied=($variant -eq 'Range' -and $v.Status -eq 206);IsolationPass=$valid})
            if($allowed -and -not $valid){throw "Own asset HTTP variant failed: $kind $variant"}
        }
    }
}
function Phase($phase,$aActive){
    foreach($kind in @('image','subtitle')){
        Asset $phase 'b' 'b' $kind $true
        Asset $phase 'a' 'a' $kind $aActive
        Asset $phase 'b' 'a' $kind $false
        Asset $phase 'a' 'b' $kind $false
        Asset $phase 'anonymous' 'a' $kind $false
        Asset $phase 'anonymous' 'b' $kind $false
    }
    foreach($actor in @('a','b')){
        $other=if($actor -eq 'a'){'b'}else{'a'}
        foreach($kind in @('image','subtitle')){
            $s=$subjects[$actor]
            $prefix=if($kind -eq 'image'){(AssetPath $s $kind)+$(if($DerivedAssets){'&'}else{'?'})+'MediaSourceId='}else{"Videos/$($s.VideoId)/"}
            $format=if($DerivedAssets){'vtt'}else{'srt'}
            $suffix=if($kind -eq 'image'){''}else{"/Subtitles/$($s.SubtitleIndex)/Stream.$format"}
            $foreign=Request ($prefix+$subjects[$other].SourceId+$suffix) $s.Headers
            $missing=Request ($prefix+'mediasource_999999999'+$suffix) $s.Headers
            $same=$foreign.Status -eq 404 -and $missing.Status -eq 404 -and $foreign.Text -eq $missing.Text -and $foreign.Bytes.Length -eq 15
            $entity=@($foreign.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
            $rows.Add(@{Label="$phase $actor own item foreign $kind source";Status=$foreign.Status;MissingStatus=$missing.Status;SameGenericDenial=$same;EntityHeaderCount=$entity.Count;IsolationPass=($same -and $entity.Count -eq 0)})
        }
    }
}
try{
    & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -MediaAssets|Out-Null
    $fixture=Get-Content (Join-Path $PSScriptRoot 'bin/native-client-state.json') -Raw|ConvertFrom-Json
    foreach($actor in @('a','b')){
        $u=@($fixture.Users|Where-Object Owner -eq $actor)[0]
        $lib=@($fixture.Libraries|Where-Object Owner -eq $actor)[0]
        $login=Call 'Users/AuthenticateByName' @{Authorization="MediaBrowser Client=`"Production assets`", Device=`"Isolated`", DeviceId=`"assets-$actor`", Version=`"1`""} Post @{Username=$u.Name;Pw=''}
        if($login.User.Id -ne $u.UserId -or $login.User.Policy.IsAdministrator){throw 'Wrong ordinary asset subject'}
        $subjects[$actor]=@{UserId=$u.UserId;VideoId=$lib.VideoId;Headers=@{'X-Emby-Token'=$login.AccessToken};ImageHash=(Get-FileHash (Join-Path $lib.Folder "fixture-primary-$actor.png") -Algorithm SHA256).Hash}
        $subjects[$actor].Profile=Call 'YouTubePlugin/MyProfile' $subjects[$actor].Headers Post @{ExpectedRevision=0;Channels=@('UC'+('a'*22))}
        $boundResponse=Request 'PersonalChannelsFixture/ProductionNativeBindings' $admin Post @{RootKey=[long]$lib.LibraryId;OwnerUserId=$u.UserId}
        if($boundResponse.Status -ne 200){
            $items=Call "Items?ParentId=$($lib.LibraryId)&Recursive=true" $admin
            $rows.Add(@{Label='Binding setup failed';Status=$boundResponse.Status;Members=@($items.Items|Select-Object Name,Type)})
            throw 'Controlled asset binding setup rejected its members'
        }
        $bound=$boundResponse.Text|ConvertFrom-Json
        if(-not $bound.Registered){
            $rows.Add(@{Label='Controlled native binding member inspection';VideoPresent=$bound.VideoPresent;Members=$bound.Members})
            throw 'Private production binding missing'
        }
        $policy=(Call "Users/$($u.UserId)").Policy
        $policy.EnableAllFolders=$true
        Call "Users/$($u.UserId)/Policy" $admin Post $policy|Out-Null
        $policy=(Call "Users/$($u.UserId)").Policy
        if(-not $policy.EnableAllFolders -or $policy.IsAdministrator){throw 'Broad ordinary native policy not established'}
    }
    $gate=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($gate.ExperimentalEnabled -or -not $gate.Production.Installed){
        $rows.Add(@{Label='Production asset boundary installation failed';State=$gate})
        throw 'Production-only asset boundary not established'
    }
    $rows.Add(@{Label='Production bindings active, ordinary native folder rights broad, experimental guard off';Installed=$true;ExperimentalEnabled=$false})
    foreach($actor in @('a','b')){
        $info=Call "Items/$($subjects[$actor].VideoId)/PlaybackInfo" $subjects[$actor].Headers Post @{}
        $source=@($info.MediaSources)[0]
        $sub=@($source.MediaStreams|Where-Object {$_.Type -eq 'Subtitle' -and $_.IsExternal})
        if(-not $source.Id -or $sub.Count -ne 1){throw 'Actual external subtitle source not established'}
        $subjects[$actor].SourceId=$source.Id;$subjects[$actor].SubtitleIndex=$sub[0].Index
    }
    Phase 'Active' $true
    if($ProbeProducerOutput){
        Call 'PersonalChannelsFixture/NativeImageProducerProbe' $admin Post @{OwnerUserId=$subjects.a.UserId;ForeignOwnerUserId=$subjects.b.UserId;ItemId=[long]$subjects.a.VideoId;ForeignItemId=[long]$subjects.b.VideoId;CachePathFault=[bool]$ProbeCachePath}|Out-Null
        $controlBefore=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $controlHeaders=$subjects.b.Headers.Clone();$controlHeaders['X-Isolated-Image-Producer']='producer-control'
        $controlResult=Request (AssetPath $subjects.b 'image') $controlHeaders
        $probe=Call 'PersonalChannelsFixture/NativeImageProducerProbe'
        $controlAfter=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $recipes=$controlAfter.AssetSources.ImageRecipes-$controlBefore.AssetSources.ImageRecipes
        $recipeControl=$controlAfter.AssetSources.ImageRecipeVersion -eq 1 -and $recipes -ge 1
        if($controlResult.Status -ne 200 -or -not(PayloadMatches $controlResult.Bytes 'image' 'b') -or $probe.Controls -ne 1 -or -not $probe.DerivedForeignOutputCaptured){throw 'Actual authenticated own B producer output control missing'}
        $rows.Add(@{Label='Actual own B derived producer output captured';Status=200;Controls=$probe.Controls;OwnBContentVerified=$true;DerivedForeignOutputCaptured=$true;ImageRecipeVersion=$controlAfter.AssetSources.ImageRecipeVersion;ImageRecipesDelta=$recipes})
        if($RequireIsolation -and -not $recipeControl){throw 'Actual independent own B cache recipe control missing'}
        $before=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $injectHeaders=$subjects.a.Headers.Clone();$injectHeaders['X-Isolated-Image-Producer']='producer-inject'
        $injectedResult=Request (AssetPath $subjects.a 'image') $injectHeaders
        $probe=Call 'PersonalChannelsFixture/NativeImageProducerProbe'
        $after=Call 'PersonalChannelsFixture/ProductionServiceGate'
        $entities=@($injectedResult.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
        $delta=$after.StaticSources.IoCalls-$before.StaticSources.IoCalls
        $foreignContent=PayloadMatches $injectedResult.Bytes 'image' 'b'
        $safe=$probe.Injected -eq 1 -and $injectedResult.Status -eq 404 -and $injectedResult.Text -eq 'Item not found.' -and $injectedResult.Bytes.Length -eq 15 -and $entities.Count -eq 0 -and $delta -eq 0 -and -not $foreignContent -and $after.AssetSources.Installed -and $after.AssetSources.ImageRecipeVersion -eq 1
        $label=if($ProbeCachePath){'Actual image cache recipe output substitution'}else{'Actual image producer output substitution'}
        $rows.Add(@{Label=$label;Injected=$probe.Injected;Status=$injectedResult.Status;Bytes=$injectedResult.Bytes.Length;EntityHeaderCount=$entities.Count;IoCallsDelta=$delta;ContainsDecodedForeignBImage=$foreignContent;ImageRecipeVersion=$after.AssetSources.ImageRecipeVersion;ProducerDeniedDelta=($after.AssetSources.Denied-$before.AssetSources.Denied);ProductionWrappedBeforeProbe=$probe.ProductionWrappedBeforeProbe;IncomingTaskContract=$probe.IncomingTaskContract;IsolationPass=$safe})
        if($probe.Injected -ne 1){throw 'Controlled native producer output substitution was not reached'}
        if($RequireIsolation -and -not $safe){throw 'Controlled native producer output substitution was not isolated'}
    }
    if($InspectProcessing){
        $inspection=Call 'PersonalChannelsFixture/NativeAssetProcessingInspection'
        $inspection|ConvertTo-Json -Depth 10|Set-Content (Join-Path $PSScriptRoot 'bin/native-asset-processing-inspection.json') -Encoding UTF8
        $rows.Add(@{Label='Actual native asset processing inspection';Types=$inspection.Types;Methods=@($inspection.Methods).Count;Truncated=$inspection.Truncated})
        if(@($inspection.Methods).Count -eq 0){throw 'Native processing inspection found no methods'}
    }
    if($WriterRace -ne 'None'){
        $timingPath='PersonalChannelsFixture/NativeReferenceWriteGate'
        $writeBefore=Call 'PersonalChannelsFixture/ProductionItemList'
        Call $timingPath $admin Post @{OwnerUserId=$subjects.a.UserId;Asset=$WriterRace;AfterCheck=[bool]$AfterWriteCheckRace}|Out-Null
        $s=$subjects.a
        $path=AssetPath $s $WriterRace.ToLowerInvariant()
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,"$base/$path")
        foreach($key in $s.Headers.Keys){$message.Headers.TryAddWithoutValidation($key,[string]$s.Headers[$key])|Out-Null}
        $message.Headers.TryAddWithoutValidation('X-Isolated-Reference-Gate','before-write')|Out-Null
        $pending=$client.SendAsync($message)
        try{
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{$pause=Call $timingPath;if($pause.Active){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
            if(-not $pause.Active -or $pending.IsCompleted -or $pause.TimedOut){throw 'Actual asset writer did not pause'}
            $rows.Add(@{Label='Actual native asset writer paused';Kind=$WriterRace;ResultContract=$pause.ResultContract;HttpPending=$true;TimedOut=$false})
            Asset 'While A writer paused' 'b' 'b' 'image' $true
            Asset 'While A writer paused' 'b' 'b' 'subtitle' $true
            if($AfterWriteCheckRace){
                if(-not $pause.AfterCheck){throw 'Asset timing hook is not after production check'}
                $deleteMessage=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,"$base/YouTubePlugin/MyProfile/Delete")
                foreach($key in $s.Headers.Keys){$deleteMessage.Headers.TryAddWithoutValidation($key,[string]$s.Headers[$key])|Out-Null}
                $deleteMessage.Content=[Net.Http.StringContent]::new((@{ExpectedRevision=$s.Profile.Revision}|ConvertTo-Json),[Text.Encoding]::UTF8,'application/json')
                $deletionPending=$client.SendAsync($deleteMessage)
                $deadline=[DateTime]::UtcNow.AddSeconds(5)
                do{$lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($s.UserId)";if($lease.Waiting -ge 1){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
                $profile=Call 'YouTubePlugin/MyProfile' $s.Headers
                $pause=Call $timingPath
                if(-not $lease.Held -or $lease.Waiting -lt 1 -or $deletionPending.IsCompleted -or $profile.State -ne 'Draft' -or -not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'Asset deletion did not wait at actual writer lease'}
                $rows.Add(@{Label='Deletion waiting at actual asset owner lease';Held=$true;Waiting=$lease.Waiting;DeleteHttpPending=$true;PersistedState=$profile.State;Active=$true;TimedOut=$false})
                $saved=Call 'YouTubePlugin/MyProfile' $subjects.b.Headers Post @{ExpectedRevision=$subjects.b.Profile.Revision;Channels=@('UC'+('b'*22))}
                if($saved.Revision -ne $subjects.b.Profile.Revision+1){throw 'Independent B profile save failed'}
                $subjects.b.Profile=$saved
                $rows.Add(@{Label='B profile mutation succeeds while A asset deletion waits';RevisionAdvanced=$true})
            }else{
                $deleted=Call 'YouTubePlugin/MyProfile/Delete' $s.Headers Post @{ExpectedRevision=$s.Profile.Revision}
                $pause=Call $timingPath
                if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $s.Headers).State -ne 'Deleted' -or -not $pause.Active -or $pause.TimedOut -or $pending.IsCompleted){throw 'Asset deletion not persisted before writer release'}
                $rows.Add(@{Label='Actual A profile deletion persisted before asset writer release';Deleted=$true;HttpPending=$true;Active=$true;TimedOut=$false})
            }
        }finally{Call $timingPath $admin Post @{Release=$true}|Out-Null}
        $response=$pending.GetAwaiter().GetResult()
        try{
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $text=[Text.Encoding]::UTF8.GetString($bytes)
            $names=@($response.Headers|ForEach-Object {$_.Key})+@($response.Content.Headers|ForEach-Object {$_.Key})
            $entity=@($names|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
            if($AfterWriteCheckRace){
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$hash=[BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes)).Replace('-','')}finally{$sha.Dispose()}
                $match=PayloadMatches $bytes $WriterRace.ToLowerInvariant() 'a'
                $safe=[int]$response.StatusCode -eq 200 -and $match
            }else{$safe=[int]$response.StatusCode -eq 404 -and $text -eq 'Items not found.' -and $bytes.Length -eq 16 -and $entity.Count -eq 0 -and $response.Content.Headers.ContentLength -eq 16}
            $label=if($AfterWriteCheckRace){'Authorized asset response holding owner lease before mutation'}else{'Waiting asset response after completed profile deletion'}
            $rows.Add(@{Label=$label;Kind=$WriterRace;Status=[int]$response.StatusCode;Bytes=$bytes.Length;GenericBody=($text -eq 'Items not found.');EntityHeaderCount=$entity.Count;IsolationPass=$safe})
            if(-not $safe){throw 'Stale asset response not safely denied'}
        }finally{$response.Dispose();$message.Dispose()}
        $writeAfter=Call 'PersonalChannelsFixture/ProductionItemList'
        $delta=$writeAfter.WritesDenied-$writeBefore.WritesDenied
        $expectedDelta=if($AfterWriteCheckRace){0}else{1}
        $hookLabel=if($AfterWriteCheckRace){'Production writer hook result'}else{'Production writer hook denied stale asset'}
        $rows.Add(@{Label=$hookLabel;Installed=$writeAfter.Installed;DeniedDelta=$delta;ExpectedDelta=$expectedDelta})
        if(-not $writeAfter.Installed -or $delta -ne $expectedDelta){throw 'Unexpected production asset writer hook result'}
        if($AfterWriteCheckRace){
            $deleteResponse=$deletionPending.GetAwaiter().GetResult()
            try{
                $deleted=$deleteResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
                $lease=Call "PersonalChannelsFixture/TransferLease?OwnerUserId=$($s.UserId)"
                if([int]$deleteResponse.StatusCode -ne 200 -or $deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $s.Headers).State -ne 'Deleted' -or $lease.Held -or $lease.Waiting){throw 'Queued asset deletion not persisted after writer release'}
                $rows.Add(@{Label='Queued deletion persisted after asset writer lease released';Status=200;State=$deleted.State;Held=$lease.Held;Waiting=$lease.Waiting})
            }finally{$deleteResponse.Dispose();$deleteMessage.Dispose()}
        }
    }else{
        $deleted=Call 'YouTubePlugin/MyProfile/Delete' $subjects.a.Headers Post @{ExpectedRevision=$subjects.a.Profile.Revision}
    }
    if($deleted.State -ne 'Deleted' -or (Call 'YouTubePlugin/MyProfile' $subjects.a.Headers).State -ne 'Deleted'){throw 'A profile deletion not persisted'}
    Phase 'Deleted' $false
    $boot=(Call 'PersonalChannelsFixture/Guard').BootId
    & $control -Stop|Out-Null
    & $control|Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do{try{$ready=Call 'PersonalChannelsFixture/Guard';if($ready.Ready -and $ready.BootId -ne $boot){break}}catch{};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    if(-not $ready.Ready -or $ready.BootId -eq $boot){throw 'Actual asset server restart not verified'}
    $gate=Call 'PersonalChannelsFixture/ProductionServiceGate' $admin Post @{DisableExperimentalGuard=$true}
    if($gate.ExperimentalEnabled -or -not $gate.Production.Installed){throw 'Production-only asset restart not established'}
    $rows.Add(@{Label='Actual restart and experimental guard off';RestartVerified=$true})
    Phase 'Restarted' $false
    $failures=@($rows|Where-Object {$_.ContainsKey('IsolationPass') -and -not $_.IsolationPass})
    if($RequireIsolation -and $failures.Count){throw 'Production media asset isolation not achieved'}
    $completed=$true
}finally{
    $name=if($ProbeProducerOutput){'production-media-assets-image-producer-output-'+$(if($RequireIsolation){'protected'}else{'diagnostic'})+'-results.json'}elseif($InjectSourceMismatch){'production-media-assets-'+$TraceSource.ToLowerInvariant()+'-source-mismatch-results.json'}elseif($TraceDerived){'production-media-assets-'+$TraceSource.ToLowerInvariant()+'-derived-source-trace-results.json'}elseif($InspectProcessing){'production-media-assets-processing-inspection-results.json'}elseif($TraceSource -ne 'None'){'production-media-assets-'+$TraceSource.ToLowerInvariant()+'-source-trace-results.json'}elseif($HttpVariants){'production-media-assets-http-variants-results.json'}elseif($AfterWriteCheckRace){'production-media-assets-'+$WriterRace.ToLowerInvariant()+'-write-lease-results.json'}elseif($WriterRace -ne 'None'){'production-media-assets-'+$WriterRace.ToLowerInvariant()+'-write-results.json'}elseif($RequireIsolation){'production-media-assets-protected-results.json'}else{'production-media-assets-diagnostic-results.json'}
    if($gate.Production.AssetSources.Installed){$name='bound-'+$name}
    if($ProbeCachePath){$name=$name.Replace('producer-output','cache-output')}
    if($gate.Production.AssetSources.ImageRecipeVersion -eq 1){$name='recipe-'+$name}
    if($DerivedAssets){$name='derived-lifecycle-'+$name}
    @{Completed=$completed;DerivedAssets=[bool]$DerivedAssets;Observations=$rows.ToArray();Scope='Actual local Primary PNG and external subtitle; DerivedAssets selects decoded 80x45 PNG and WEBVTT for the entire own/foreign/anonymous lifecycle and source-ID matrix, optional HTTP variants and writer timing; production bindings and broad folder rights, experimental guard disabled; no universal asset or client proof'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot ('bin/'+$name)) -Encoding UTF8
    try{
        & (Join-Path $PSScriptRoot 'Start-NativeClientFixture.ps1') -Stop|Out-Null
        if(Test-Path $profileRoot){
            $dir=[IO.Path]::GetFullPath($profileRoot)
            $expected=[IO.Path]::GetFullPath((Join-Path $root 'data/data/youtube-personal'))
            if($dir -ne $expected -or -not $dir.StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe asset profile cleanup'}
            $names=@('encryption.key','native-reference-bindings.json','native-reference-bindings.required')+@($subjects.Values|ForEach-Object{$_.UserId+'.json'})
            $files=@(Get-ChildItem -LiteralPath $dir -Force)
            if(@($files|Where-Object {$_.PSIsContainer -or $_.Name -notin $names -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count){throw 'Unexpected retained asset profile file'}
            foreach($file in $files){Remove-Item -LiteralPath $file.FullName}
            Remove-Item -LiteralPath $dir
        }
    }finally{$client.Dispose()}
}
Write-Output ('Production media asset observations='+$rows.Count+'; isolation failures='+$failures.Count)
