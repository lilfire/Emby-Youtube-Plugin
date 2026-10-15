$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Push-Location $repo
try{
    & dotnet run --project verification/FollowUp/F/StoreChecks.csproj -c Release
    if($LASTEXITCODE){throw 'Windows F store checks failed'}
    Copy-Item (Join-Path $PSScriptRoot 'bin/store-results.json') (Join-Path $PSScriptRoot 'WINDOWS-STORE-EVIDENCE.json')
    & dotnet publish verification/FollowUp/F/StoreChecks.csproj -c Release -r linux-x64 --self-contained true -o verification/FollowUp/F/bin/linux-glibc
    if($LASTEXITCODE){throw 'Linux F build failed'}
    $name='emby-youtube-f-store'
    if($name -in @(docker container ls -a --format '{{.Names}}')){throw 'F container name already occupied'}
    $application=Join-Path $PSScriptRoot 'bin/linux-glibc'
    $mount='type=bind,source='+$application+',target=/audit,readonly'
    try{
        & docker run --name $name --network none --entrypoint /bin/sh --mount $mount emby/embyserver:latest -c 'mkdir -p /lib64 /tmp/f-app /tmp/f-work; ln -s /lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; cp /audit/* /tmp/f-app/; chmod +x /tmp/f-app/PersonalYouTubeVerification; cd /tmp/f-work; id; umask; /tmp/f-app/PersonalYouTubeVerification'
        if($LASTEXITCODE){throw 'Linux F checks failed'}
        & docker cp ($name+':/tmp/f-work/verification/FollowUp/F/bin/store-results.json') (Join-Path $PSScriptRoot 'LINUX-STORE-EVIDENCE.json')
        if($LASTEXITCODE){throw 'Linux evidence copy failed'}
        $image=(& docker inspect $name --format '{{.Image}}')
    }finally{
        & docker rm $name|Out-Null
        if($LASTEXITCODE){throw 'F container cleanup failed'}
    }
    @{Image=$image;Uid=0;Umask='0022';Network='none';Entry='Standalone harness referencing production assembly, not running Emby server';
      ContainerGone=($name -notin @(docker container ls -a --format '{{.Names}}'));
      LinuxPluginHash=(Get-FileHash (Join-Path $application 'Emby.YouTubePlugin.dll')).Hash;
      WindowsPluginHash=(Get-FileHash (Join-Path $repo 'bin/Release/net6.0/Emby.YouTubePlugin.dll')).Hash
    }|ConvertTo-Json -Depth 4|Set-Content (Join-Path $PSScriptRoot 'STORE-METADATA.json') -Encoding UTF8
}finally{Pop-Location}
