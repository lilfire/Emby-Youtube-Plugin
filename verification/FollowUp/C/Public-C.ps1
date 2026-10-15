# A is an ordinary native library with no private journal registration.
# B remains bound to its real personal profile and native root.
function Phase($phase,$aActive){
    foreach($kind in @('image','subtitle')){
        Asset "$phase public A" 'a' 'a' $kind $true
        Asset "$phase public A foreign authenticated actor" 'b' 'a' $kind $true
        Asset "$phase private B" 'b' 'b' $kind $true
        Asset "$phase private B foreign actor" 'a' 'b' $kind $false
        Asset "$phase private B anonymous" 'anonymous' 'b' $kind $false
    }
}
