# HEAD, ETag og range for private bilde-/undertekstsvar

Oppdatering 13. oktober 2026: Dette er rapporten før asset-leserbinding.
[PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver ny binding og beståtte originale og avledede HTTP-/livsløpsmatriser.
Tidligere vurdering av helt manglende binding nedenfor er historisk;
komplett cacheproveniens og full skjerming gjenstår.

12. oktober 2026. Isolert Windows Emby 4.10.1.0 med syntetiske Primary-PNG
og eksterne SRT-filer. Vanlige A/B-kontoer har brede native bibliotekrettigheter,
produksjonsprofiler/native bindinger og eksperimentell guard avslått og lest
tilbake. Dette er HTTP-/livsløpskontroller, ikke full skjerming eller klientbevis.

## Kontrollerte varianter

`Test-ProductionMediaAssets.ps1 -HttpVariants -RequireIsolation` fullfører
158 observasjoner i `bin/production-media-assets-http-variants-results.json`.
Completed=true, null feilede IsolationPass og prosessens exit 0 er kontrollert.
Ingen produksjonsrettelse var nødvendig for disse konkrete variantene.

Den opprinnelige testen av fullfil og fremmede/manglende kilde-ID-er beholdes.
I tillegg brukes tre varianter for hvert bilde-/undertekstkall:

- HEAD: egne svar har HTTP 200, null kropp, samme ETag og korrekt full
  Content-Length fra den faktisk validerte fullfilen (PNG 363/SRT 71 byte).
- Matching If-None-Match: egne svar har HTTP 304, null kropp og riktig ETag.
- Range bytes=0-31: egne svar har HTTP 206, akkurat 32 byte, korrekt
  Content-Range og identiske bytes med fullfilens første 32 byte.

Verifikatoren kan også registrere et native 200-fullfilssvar dersom en server
ignorerer range, men det skjedde ikke i denne kjøringen: alle åtte tillatte
range-kall leverte 206 med riktig prefiks. Dette er én enkelt range, ikke
alle byteområder eller multipart-range.

De samme variantene prøves i begge A/B-retninger og anonymt. Både fremmede
og anonyme forespørsler bruker eierens faktisk gyldige ETag ved cachetesten.
Avslag er generisk 404 uten ETag, Last-Modified, Content-Disposition,
Content-Range eller Accept-Ranges. HEAD gir null kropp; betingede GET- og
range-avslag gir akkurat `Item not found.` på 15 byte. Private markører i
filheadere avvises også av verifikatoren.

Etter faktisk A-profilsletting brukes den tidligere gyldige A-ETag-en og
de gamle referansene fortsatt. A selv, B og anonym blir avvist. Dette gjentas
etter faktisk serveromstart med ny BootId og ny readback av avslått fixture-
guard. B sine egne fullfil-/HEAD-/304-/206-svar fungerer gjennom alle fasene.
Totalt gir de nye variantene 24 tillatte og 84 avslåtte observasjoner,
i tillegg til de tidligere 50 fullfil-/kilde-/oppsettsobservasjonene.

Sluttkontrollen i `bin/production-asset-http-variants-cleanup.json` er lest
tilbake: syntetiske kontoer, biblioteker, prøvefiler og fixture er fjernet,
profiler/journaler er borte og den isolerte Emby-prosessen er faktisk stoppet.

## Åpne krav

Dette er ikke en skriverpause/race for HEAD, 304 eller range. De tidligere
fullfil-racene er dokumentert i
[PRODUCTION-ASSET-WRITE-REVOCATION.md](PRODUCTION-ASSET-WRITE-REVOCATION.md) og
[PRODUCTION-ASSET-TRANSFER-LEASE.md](PRODUCTION-ASSET-TRANSFER-LEASE.md).
Last-Modified-betingelser, andre ranges/formater/bildetyper, transformerte
bilder, avledet kilde-/cachebinding, andre ressursruter, native mutasjoner,
bruker-/tokenrevokering og faktiske klientfamilier gjenstår. Full skjerming
er fortsatt ikke bevist. Hovedserveren er ikke endret i denne runden.
