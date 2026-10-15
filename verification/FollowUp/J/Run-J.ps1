param([string]$Image='emby/embyserver:latest')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Native([scriptblock]$Action) { & $Action; if($LASTEXITCODE){throw 'J command failed'} }
Push-Location $repo
$name='emby-youtube-j-platform'
$volume='emby-youtube-j-persistence'
$reserved=$false
try {
    if($name -in @(docker container ls -a --format '{{.Names}}') -or $volume -in @(docker volume ls --format '{{.Name}}')){throw 'J resource already occupied'}
    $reserved=$true
    Native { dotnet run --project verification/FollowUp/J/J.csproj -c Release -- (Join-Path $PSScriptRoot 'WINDOWS-EVIDENCE.json') }
    Native { dotnet run --project verification/FollowUp/J/J.csproj -c Release -- inventory $repo (Join-Path $repo 'verification/WatchState/bin/emby-isolated/server/system') (Join-Path $PSScriptRoot 'WINDOWS-NATIVE-INVENTORY.json') }
    Native { dotnet publish verification/FollowUp/J/J.csproj -c Release -r linux-x64 --self-contained true -o verification/FollowUp/J/bin/linux }
    $mount='type=bind,source='+(Join-Path $PSScriptRoot 'bin/linux')+',target=/audit,readonly'
    Native { docker volume create $volume | Out-Null }
    $imageId=(& docker image inspect $Image --format '{{.Id}}')
    $script='set -eu; mkdir -p /lib64 /tmp/j-app /persist/tools /persist/data; ln -s /lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; cp /audit/* /tmp/j-app/; chmod +x /tmp/j-app/PersonalYouTubeVerification; /tmp/j-app/PersonalYouTubeVerification /persist/linux-evidence.json; cp /bin/busybox /persist/tools/busybox; chmod 755 /persist/tools/busybox; echo synthetic-j-data > /persist/data/marker; sha256sum /persist/tools/busybox /persist/data/marker > /persist/before.sha; /persist/tools/busybox --help >/dev/null; stat -c %a:%u:%g /persist/tools/busybox /persist/data/marker > /persist/modes; cp /system/Emby.Server.Implementations.dll /persist/Emby.Server.Implementations.dll'
    # No server data mounts, no network, no existing container modification.
    Native { docker run --name $name --network none --entrypoint /bin/sh --mount $mount --mount ('type=volume,source='+$volume+',target=/persist') $Image -c $script }
    $firstId=(& docker inspect $name --format '{{.Id}}')
    Native { docker cp ($name+':/persist/linux-evidence.json') (Join-Path $PSScriptRoot 'LINUX-EVIDENCE.json') }
    New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'bin/linux-native') | Out-Null
    Native { docker cp ($name+':/persist/Emby.Server.Implementations.dll') (Join-Path $PSScriptRoot 'bin/linux-native/Emby.Server.Implementations.dll') }
    Native { docker rm $name | Out-Null }
    $recreate='set -eu; sha256sum -c /persist/before.sha; /persist/tools/busybox --help >/dev/null; grep -qx synthetic-j-data /persist/data/marker; id -u; cat /persist/modes; test ! -e /tmp/j-app/PersonalYouTubeVerification'
    $readback=(& docker run --name $name --network none --entrypoint /bin/sh --mount ('type=volume,source='+$volume+',target=/persist') $Image -c $recreate)
    if($LASTEXITCODE){throw 'Container recreation readback failed'}
    $secondId=(& docker inspect $name --format '{{.Id}}')
    if($firstId -eq $secondId){throw 'Container not recreated'}
    Native { docker rm $name | Out-Null }
    Native { dotnet run --project verification/FollowUp/J/J.csproj -c Release -- inventory $repo (Join-Path $PSScriptRoot 'bin/linux-native') (Join-Path $PSScriptRoot 'LINUX-NATIVE-INVENTORY.json') }
    Native { docker volume rm $volume | Out-Null }
    @{Completed=$true;ImageId=$imageId;RecreatedDifferentContainer=$true;Network='none';ServerStarted=$false;
      Persistence='busybox executable and synthetic data on named volume, not yt-dlp/Node/FFmpeg or native Emby state';Readback=@($readback);
      ContainerGone=($name -notin @(docker container ls -a --format '{{.Names}}'));
      VolumeGone=($volume -notin @(docker volume ls --format '{{.Name}}'));
      Commit=(& git rev-parse HEAD);HarnessSHA256=(Get-FileHash (Join-Path $PSScriptRoot 'Program.cs')).Hash
    }|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'PLATFORM-METADATA.json') -Encoding UTF8
} finally {
    if($reserved) {
        if($name -in @(docker container ls -a --format '{{.Names}}')) { & docker rm -f $name | Out-Null }
        if($volume -in @(docker volume ls --format '{{.Name}}')) { & docker volume rm $volume | Out-Null }
    }
    Pop-Location
}
