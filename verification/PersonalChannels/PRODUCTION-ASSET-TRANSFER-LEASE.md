# Profilsletting som venter på godkjent bilde-/undertekstskriver

Oppdatering 13. oktober 2026: Historisk test før asset-leserbinding.
[PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver nåværende binding og videre tester av avledede ressurser.
Vurdering av manglende binding nedenfor gjelder utgangspunktet.

12. oktober 2026. Isolert Windows Emby 4.10.1.0, syntetiske Primary-PNG og
eksterne SRT-filer, brede native bibliotekrettigheter, produksjonsprofiler/
bindinger og eksperimentell guard deaktivert og lest tilbake.

## Verifisert rekkefølge

Timing-fixturen kan nå pause den faktiske FileWriter etter produksjonens
tilgangskontroll: fixture-prefix har prioritet 100, produksjons-prefix 800.
Timing-rekkefølgen kan ikke endres i en allerede installert fixture uten
omstart. Den konkrete A-responsen spores fra autentisert service-resultat
til faktisk WriteToAsync, og bare den merkede syntetiske forespørselen pauser.

Begge nye tester bekrefter følgende:

1. FileWriter er faktisk satt på vent etter kontrollen, og HTTP er ufullført.
2. B henter sine egne bilde-/undertekstfiler mens A venter.
3. Asynkron A-profilsletting når faktisk eierens sperre: Held=true og
   Waiting=1. Slettingskallet er fortsatt ufullført, og profilreadback er Draft.
   Timing-pauseren er fortsatt Active, uten TimedOut, og svaret venter.
4. B kan lagre nye kanalvalg med faktisk økt revisjon mens A-slettingen venter.
5. Ved eksplisitt frigjøring får det allerede godkjente A-svaret HTTP 200 med
   egen SHA-korrekt PNG eller egen SRT-markør. Produksjons-WritesDenied øker
   ikke: dette er et svar som holder tillatelsens sperre før mutasjonen.
6. Den ventende slettingen fullfører etter frigjøringen. Deleted leses tilbake,
   Held=false og Waiting=0. Nye kall med de gamle referansene avvises.
7. Faktisk omstart bekreftes med ny BootId; A er fortsatt skjult og B sine
   egne ressurser fungerer. Fremmede, anonyme og blandede kilde-ID-er avvises.

Dette supplerer den motsatte rekkefølgen i
[PRODUCTION-ASSET-WRITE-REVOCATION.md](PRODUCTION-ASSET-WRITE-REVOCATION.md):
når sletting allerede er fullført før skriverkontrollen, får svaret 404.
Her venter selve slettingen på den allerede godkjente skriveren.

## Reproduksjon

`Test-ProductionMediaAssets.ps1 -WriterRace Image -AfterWriteCheckRace -RequireIsolation`
fullfører 58 observasjoner i
`bin/production-media-assets-image-write-lease-results.json`.

`Test-ProductionMediaAssets.ps1 -WriterRace Subtitle -AfterWriteCheckRace -RequireIsolation`
fullfører 58 observasjoner i
`bin/production-media-assets-subtitle-write-lease-results.json`.

Begge prosessene fullførte med exit 0. Completed, sperre-/profilreadback,
B-revisjon, tillatte kildebytes og frigitt sperre er kontrollert i rapportene.
Fixture-bygget passerer uten advarsler/feil. Produksjonskoden krevde ingen
ny rettelse: den eksisterende skriverkontrollen beholder eierens sperre og
pakker den native skrivetasken med Complete før sperren frigjøres.

Før-kontroll-bilderegresjonen fullfører fortsatt 56 observasjoner med 404
og én ny produksjons-WritesDenied når slettingen allerede er fullført.
Sluttkontrollen i `bin/production-asset-transfer-lease-cleanup.json` er lest
tilbake: syntetiske kontoer, biblioteker, filer og fixture er fjernet,
profiler/journaler er borte og den isolerte serverprosessen er faktisk stoppet.

## Gjenværende krav

Pausen ligger ved native skriverinngang etter tilgangskontroll, før original
skriver utfører I/O. Små fullfilssvar er prøvd; dette er ikke en kontroll av
vilkårlige senere bytegrenser, lange/avbrutte overføringer eller avbrutt klient.
Testen beviser ikke uavhengig binding av den faktiske avledede bilde-/SRT-kilden
eller cache. HEAD/304/range og øvrige formater/ruter, native mutasjoner,
bruker-/tokenrevokering og alle klientfamilier gjenstår. Allerede utleverte
lokale kopier faller utenfor den avtalte servergarantien. Full skjerming er
fortsatt ikke bevist, og hovedserveren er ikke endret i denne runden.
