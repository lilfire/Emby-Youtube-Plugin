# Produksjonsavgjørelse fra faktisk native referanse

Implementert og kontrollert på isolert Emby 4.10.1.0 den 12. oktober 2026. Hovedserveren er urørt.

## Ny produksjonskode

PersonalYouTubeNativeAccess henter faktisk native element, bibliotekrøtter, fysisk foreldrekjede og konfigurerte kildestier fra ILibraryManager. Den sender faktiske ID/GUID-par og kildesteder til produksjonsjournalens avgjørelse. Foreldresyklus, manglende forelder, for mange forfedre og motstridende GUID-er for samme forelders native ID nektes; oppløsningen stopper ikke bare og behandler resten som offentlig.

DecideRequest henter User fra IAuthorizationContext.GetAuthorizationInfo(request).User. En DTO-UserId, DeviceId eller påstått eier bestemmer ikke brukeren. DecideReference/DecideItem er interne koblingspunkter for native hooks som allerede har den autentiserte User. Manglende eller deaktivert bruker får ingen privat eierautoritet.

Når native GetItemById ikke finner et element, bruker avgjørelsen nå DecideAbsentReference i produksjonsjournalen. Den vurderer varige native bindinger, reserverte GUID-er og journalførte aktive rotidentiteter. En kjent identitet blir Denied, også for eieren; fravær gir aldri Allowed. En ukjent identitet forblir Unknown bare etter at nødvendige registre er lest. Numeriske stavemåter normaliseres, og GUID både med og uten bindestreker vurderes mot den samme varige identiteten.

Testbroens FindOwner bruker nå denne produksjonsoppløsningen fremfor en egen kopi av foreldrekjede/kildestedslogikken. FindOwner er fortsatt en eksperimentell eierklassifisering; dens utledede eier er ikke autentiseringsautoriteten for en produksjonsforespørsel. En separat probe kjører produksjonens DecideRequest med den faktiske forespørselen for å verifisere dette skillet.

## Evidens

Ti nye komponentkontroller dekker reserverte, bundne og pensjonerte native referanser som er fraværende, alternative GUID-/numeriske stavemåter, ukjente referanser og at Active aldri tillater et fraværende element. Komponentkjøringen har nå 160 kontroller, Completed=true og TestDataGone=true.

`Test-ProductionNativeBindings.ps1 -PublicationJournal -ActualAccess` bruker faktiske A/B-native røtter/videoer og faktiske ordinære tokens. Den undersøker Preparing, faktisk Preparing-omstart, Active, profilsletting, senere omstart og ny generasjon, deretter faktisk sletting av native A-rot/video og enda en omstart. Den siste utvidelsen har 235 observasjoner i `bin/production-native-actual-access-results.json`. Den tidligere kjøringen med beholdte native elementer og 182 observasjoner er bevart separat.

Produksjonsavgjørelsen kjøres gjennom en probe hvis Reference-felt ikke håndheves på forhånd som en ItemId av fixture-kroken. Dermed må egne Allowed og fremmede Denied komme fra den nye avgjørelsen. Numeriske video-ID-er og GUID med/uten bindestreker kontrolleres. UserId-forfalskning lar ikke B låne A sin autoritet eller omvendt, og B sitt eget innhold fungerer selv med A-UserId i query.

Emby avviser en anonym forespørsel til proben med 401 før avgjørelsen kjøres. Disse observasjonene er merket NativeAuthenticationRejected og ProductionPolicyInvoked=false og regnes ikke som produksjonens null-brukeravgjørelse. En separat administrasjonsbegrenset probe sender eksplisitt null User til den samme produksjonskomponenten mot faktisk native element; den må gi Denied. Det første forsøket forventet feilaktig at den anonyme probeforespørselen ville nå policyen og er bevart som `bin/production-native-actual-access-anonymous-incomplete.json`. Det teller ikke som en bestått kontroll.

NativeReferenceStatus bekrefter at A sin faktiske native rot og video er borte etter native bibliotekssletting. Produksjonsavgjørelsen nekter gamle numeriske/GUID-aliaser før og etter faktisk omstart. B sine metadata, bibliotekslisting og videobytes/hash kontrolleres positivt gjennom hele livsløpet. Dette er mer enn et avslag mot en fortsatt eksisterende kilde.

Opprettingsregresjonen `Test-NewUnregisteredPrivateRoot.ps1 -InFlight -CreationContext` har også passert med 37 observasjoner og den nye oppløsningen: produksjonskroken reserverer GUID før native synlighet, alle seks kontroller i pre-source-pausen nektes, og samme rot virker for A etter aktivering, med B nektet. Etter den siste strammingen av tvetydige foreldre-ID/GUID-er ble den utvidede 235-kjøringen kjørt på nytt og passerte.

Sluttopprydding er lest tilbake i `bin/production-native-actual-access-cleanup.json`: alle fem kontroller er true for stoppet server og fjernet klientjournal, profiler, fixture-DLL og modusfil.

## Gjenstående arbeid

NativeAccess er ennå ikke en universell produksjonsgrense. Lister/counts/paging, mutasjoner, bilder, avledede filer, strøm-/jobbtoken og alle øvrige innganger må kobles til faktisk autentisert bruker og gjennomgås. HTTP-/socket-håndhevingen i native testene er fortsatt eksperimentell. Produksjonspubliserer, recovery og faktisk YouTube-kjede/klientfamilier står åpne. Full skjerming er fortsatt ikke bevist.
