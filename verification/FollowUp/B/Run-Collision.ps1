$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scripts=Join-Path $repo 'verification/PersonalChannels'
$out=Join-Path $PSScriptRoot 'bin'
if(Get-Process EmbyServer -ErrorAction SilentlyContinue){throw 'Reserve the stopped isolated fixture first'}
if(Get-NetTCPConnection -LocalPort 18096 -State Listen -ErrorAction SilentlyContinue){throw 'Port occupied'}
foreach($reuse in @($false,$true)){
    try{
        & (Join-Path $scripts 'Test-NativeRootRecreation.ps1') -ReuseFolder:$reuse
    }finally{
        $name=if($reuse){'native-root-recreation-reused-folder-results.json'}else{'native-root-recreation-results.json'}
        Copy-Item (Join-Path $scripts ('bin/'+$name)) (Join-Path $out $(if($reuse){'collision-reused.json'}else{'collision-fresh.json'}))
        $deadline=[DateTime]::UtcNow.AddSeconds(12)
        do{if(-not(Get-Process EmbyServer -ErrorAction SilentlyContinue)){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
        @{ServerStopped=-not[bool](Get-Process EmbyServer -ErrorAction SilentlyContinue);NativeCleanup=(Get-Content (Join-Path $scripts 'bin/native-client-cleanup.json') -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $out $(if($reuse){'collision-reused-cleanup.json'}else{'collision-fresh-cleanup.json'})) -Encoding UTF8
    }
}
