if($Mode -eq 'Content'){
    foreach($record in $cacheRecords){
        $path=Join-Path $cacheRoot $record.RelativePath
        $rows.Add(@{Label='C native cache after profile deletion and restart';Kind=$record.Kind;CacheStillExists=(Test-Path -LiteralPath $path);OriginalHashMatches=($(if(Test-Path $path){(Get-FileHash -LiteralPath $path).Hash}else{''}) -eq $record.OriginalHash)})
    }
}
foreach($kind in @('image','subtitle')){Asset 'C before account deletion B owner control' 'b' 'b' $kind $true}
function RevokedSessionMatrix($label){
    foreach($kind in @('image','subtitle')){
        foreach($variant in @('Get','Head','Conditional','Range')){
            $headers=$subjects.b.Headers.Clone()
            if($variant -eq 'Conditional'){$headers['If-None-Match']=$subjects.b[('ETag_'+$kind)]}
            if($variant -eq 'Range'){$headers.Range='bytes=0-31'}
            $method=if($variant -eq 'Head'){'Head'}else{'Get'}
            $r=Request (AssetPath $subjects.b $kind) $headers $method
            $text=[Text.Encoding]::UTF8.GetString($r.Bytes)
            $entities=@($r.HeaderNames|Where-Object {$_ -in @('ETag','Last-Modified','Content-Disposition','Content-Range','Accept-Ranges')})
            $rows.Add(@{Label=$label;Kind=$kind;Variant=$variant;Status=$r.Status;Bytes=$r.Bytes.Length;EntityHeaderCount=$entities.Count;IsolationPass=($r.Status -in @(401,403,404) -and $entities.Count -eq 0 -and -not $text.Contains('PrivateSubtitle_') -and -not(PayloadMatches $r.Bytes $kind 'b'))})
        }
    }
}
# Revoke only this ordinary synthetic session; never emit its key or URL.
$revoked=Request ('Auth/Keys/'+$subjects.b.Headers['X-Emby-Token']) $admin Delete
if($revoked.Status -notin @(200,204)){throw 'Synthetic session revocation rejected'}
RevokedSessionMatrix 'C revoked token old session'
$u=@($fixture.Users|Where-Object Owner -eq 'b')[0]
$login=Call 'Users/AuthenticateByName' @{Authorization='MediaBrowser Client="C assets", Device="Isolated", DeviceId="c-relogin-b", Version="1"'} Post @{Username=$u.Name;Pw=''}
if($login.User.Id -ne $subjects.b.UserId){throw 'Synthetic reauthentication identity mismatch'}
$subjects.b.Headers=@{'X-Emby-Token'=$login.AccessToken}
foreach($kind in @('image','subtitle')){Asset 'C new session after token revocation' 'b' 'b' $kind $true}
Call "Users/$($subjects.b.UserId)" $admin Delete|Out-Null
if(@((Call 'Users')|Where-Object Id -eq $subjects.b.UserId).Count){throw 'Synthetic account deletion readback failed'}
RevokedSessionMatrix 'C deleted account old session'
