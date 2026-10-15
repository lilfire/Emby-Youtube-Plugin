# Only emit generic roles and permission bits, never account names/SIDs or file contents.
$fRules=@()
foreach($fKind in @('Key','Profile')){
    $fPath=if($fKind -eq 'Key'){Join-Path $profileRoot 'encryption.key'}else{Join-Path $profileRoot ($subjects.a.UserId+'.json')}
    $fAcl=Get-Acl -LiteralPath $fPath
    foreach($fRule in $fAcl.Access){
        $fSid=$fRule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        $fRole=switch($fSid){'S-1-1-0'{'Everyone'} 'S-1-5-11'{'AuthenticatedUsers'} 'S-1-5-32-545'{'BuiltinUsers'} 'S-1-5-32-544'{'Administrators'} 'S-1-5-18'{'System'} default{'OtherPrincipal'}}
        $fRules+=@{File=$fKind;Role=$fRole;Rights=[string]$fRule.FileSystemRights;Type=[string]$fRule.AccessControlType;Inherited=$fRule.IsInherited;Protected=$fAcl.AreAccessRulesProtected}
    }
}
@{Rules=$fRules;ProductionCreated=$true;Platform='Windows x64'}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $fChapter 'WINDOWS-PERMISSIONS.json') -Encoding UTF8
