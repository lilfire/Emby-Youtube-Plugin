# Profilsletting ved native skriverinngang

Isolert Emby 4.10.1.0, 12. oktober 2026. Hovedserveren er urørt.

## Faktisk kjede og moteksempel

Runtime-inventaret `bin/native-egress-inventory.json` viser at den faktiske StreamWriter implementerer IAsyncStreamWriter og IHasHeaders. WriteToAsync tar IResponse og CancellationToken og returnerer Task. Metodens IL-hash er 6958BC6F05CD86EC1762FAF3AC2D12967D5C92C413A02E9A111A3374A9BA1C35. Den første inspeksjonen lastet en eldre fixture uten disse feltene; den ble erstattet etter bygg og kontrollert omstart, og brukes ikke som evidens.

NativeListWriteGate registrerer den faktiske skriveren etter produksjonens Finish og pauser dens WriteToAsync-inngang for syntetisk A. Ingen native resultater eller skriveargumenter endres. Det er en begrenset timingkrok med 25 sekunders maksimal pause.

`Test-ProductionItemLists.ps1 -WriteRace` fullførte 41 observasjoner. Mens skriveren var pauset, fungerte B sin liste. Profilsletting for A fullførte, Deleted ble lest tilbake og pausen var fortsatt aktiv. Etter frigivelsen ga A sitt svar 200, total=1, ett element og privat navn. `bin/production-item-list-write-race-results.json` har IsolationPass=false. Resultatkontroll før HTTP-kjeden var altså ikke tilstrekkelig for dette senere vinduet.

## Produksjonsendring og effekt

Produksjonens Finish knytter den native skriveren til forespørselens autentiserte scope i en ConditionalWeakTable. Samme skriver kan ikke gjenbrukes i et annet scope. Ukjent resultatkontrakt i den beskyttede GetItems-familien avvises. Skriverkoblingen innebærer ingen endring av innhold, telling, paging eller headers.

En ny prefix på den faktiske WriteToAsync-metoden leser registrerte sperrer på nytt før originalmetoden får kjøre. Hvis forespørselens query-dekning ikke dekker en aktuell sperre, eller kontrollen feiler, returneres en faulted Task med generisk ResourceNotFoundException. Ukoblede skrivere følger normal native kjede. Installasjonen verifiserer signatur, IL-hash og faktisk egen Harmony-prefix; Snapshot inkluderer denne prefixen i PatchLost-kontrollen.

Timingkroken kjører med prioritet 1000, før produksjonskontrollen med prioritet 800. `-WriteRace -RequireRaceSafe` fullførte 42 observasjoner: den samme holdte forespørselen ga 404, ingen liste og intet privat navn. Produksjonens snapshot viste Installed=true, Writes=12 og WritesDenied=1 før omstart. B fungerte under pausen, etter sletting og etter omstart. Begge native brukere hadde EnableAllFolders=true, og eksperimentell fixture-skjerming var av. Rapport: `bin/production-item-list-write-protected-results.json`.

Komponentkjøringen fullførte 178 kontroller og fjernet sine testdata. Den faktiske skrivekroken bevises av HTTP-testen, ikke av komponentkjøringen.

Resultat-racen `-ResultRace -RequireRaceSafe` ble gjentatt med den nye skrivekroken og fullførte 42 observasjoner, fortsatt 404 uten privat navn etter sletting. `Test-ProductionNativeBindings.ps1 -PublicationJournal -ActualAccess` fullførte 235 observasjoner med både Preparing-omstart og senere omstart verifisert. Denne regresjonen har fixture-skjermingen på og er ikke ekstra bevis for produksjonskroken alene.

`bin/production-item-list-write-cleanup.json` bekrefter at den isolerte prosessen er stoppet og native testbrukere, biblioteker, media, profiler, fixture, klientjournal og modus er fjernet. Den tidligere umiddelbare stoppmarkøren beholdes separat fra den senere prosesskontrollen.

## Fortsatt åpne krav

Dette håndhever ved skriverinngangen, før originalmetoden starter. Sletting etter den siste kontrollen mens native skriving eller byteutlevering allerede pågår er ikke løst eller bevist. Et faulted write-task er målt å bli HTTP 404 i denne serverbuilden; andre builds er ikke bekreftet.

Nye uregistrerte elementer etter inventar, andre listefamilier, rå/batch/socket/DLNA-innganger, bruker-/tokenrevokering, offlinejobber og personlig YouTube-publisering/klientkjede gjenstår. Det er fortsatt ingen full skjermingsgaranti.
