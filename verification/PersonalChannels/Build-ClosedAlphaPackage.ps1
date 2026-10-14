param([string]$Version='2.0.10-alpha.1',[ValidateSet('candidate-not-approved','closed-alpha-ready')][string]$Status='candidate-not-approved')
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$packages=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin/packages'))
New-Item -ItemType Directory -Path $packages -Force | Out-Null
$candidate=Join-Path $packages ($Version+'-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfff'))
New-Item -ItemType Directory -Path $candidate | Out-Null
$sources=@{'Emby.YouTubePlugin.dll'='bin/Release/net6.0/Emby.YouTubePlugin.dll';'thumb.png'='thumb.png';'LICENSE'='LICENSE';'INSTALL.md'='verification/PersonalChannels/alpha-package/INSTALL.md';'KNOWN-LIMITS.md'='verification/PersonalChannels/alpha-package/KNOWN-LIMITS.md'}
foreach($name in $sources.Keys){Copy-Item -LiteralPath (Join-Path $repository $sources[$name]) -Destination (Join-Path $candidate $name)}
$assembly=[Reflection.AssemblyName]::GetAssemblyName((Join-Path $candidate 'Emby.YouTubePlugin.dll'))
if($assembly.Version.ToString() -ne '2.0.10.0'){throw 'Build the alpha version before packaging'}
$entries=@($sources.Keys|Sort-Object|ForEach-Object{@{Name=$_;SHA256=(Get-FileHash -LiteralPath (Join-Path $candidate $_)).Hash;Bytes=(Get-Item -LiteralPath (Join-Path $candidate $_)).Length}})
@{Version=$Version;AssemblyVersion=$assembly.Version.ToString();Status=$Status;Files=$entries}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $candidate 'manifest.json') -Encoding UTF8
$zip=$candidate+'.zip'
Compress-Archive -Path (Join-Path $candidate '*') -DestinationPath $zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
$opened=[IO.Compression.ZipFile]::OpenRead($zip)
try{
    if(@($opened.Entries).Count -ne $entries.Count+1){throw 'Unexpected packaged files'}
    foreach($entry in $entries){
        $packed=@($opened.Entries|Where-Object FullName -eq $entry.Name)
        if($packed.Count -ne 1){throw 'Missing packaged file'}
        $stream=$packed[0].Open();$sha=[Security.Cryptography.SHA256]::Create()
        try{$digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
        if($digest -ne $entry.SHA256){throw 'Packaged checksum mismatch'}
    }
}finally{$opened.Dispose()}
Write-Output $zip
