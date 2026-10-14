# Faktisk leserkilde for Primary-PNG og ekstern SRT

Oppdatering 13. oktober 2026: Historisk inspeksjon før asset-binding.
[PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver installert separat leserbinding og kontrollerte originale
filstibytter. Vurderingen av manglende binding nedenfor gjelder utgangspunktet.
Komplett cacheproveniens og full skjerming er fortsatt ikke bevist.

12. oktober 2026. Isolert Windows Emby 4.10.1.0, syntetiske A/B-filer,
produksjonsprofiler/native bindinger, brede native bibliotekrettigheter og
eksperimentell guard deaktivert og lest tilbake. Dette er inspeksjon av
faktisk utførte fabrikker, ikke en ny produksjonsrettelse eller full skjerming.

## To faktiske runtime-tracer

`Test-ProductionMediaAssets.ps1 -TraceSource Image -RequireIsolation`
fullfører 51 observasjoner i
`bin/production-media-assets-image-source-trace-results.json`.

`Test-ProductionMediaAssets.ps1 -TraceSource Subtitle -RequireIsolation`
fullfører 51 observasjoner i
`bin/production-media-assets-subtitle-source-trace-results.json`.

Begge merkede HTTP-kall gir HTTP 200 med uendrede faktisk validerte kildebytes.
Bildets forventede native kilde kommer fra item.GetImageInfo(Primary, 0).Path;
før tracing kreves SHA-likhet med akkurat fixture-primary-a.png. Undertekstens
forventede kilde kommer fra den ene native eksterne Subtitle-strømmen; den
må ha akkurat den syntetiske en.srt-stien og privat A-markør. Arm er begrenset
til faktisk syntetisk ikke-administrativ A og dens forventede native video/
bibliotek. Asset-trace tillater ingen fremmed feilinnsprøytingskilde.

Begge spor viser samme kjede med fire hendelser per marked kall:

1. GetStaticFileResult(IRequest, StaticFileResultOptions) får den forventede
   native bilde-/undertekstfilen og ingen ContentFactory.
2. GetStaticResult(IRequest, StaticResultOptions) får samme konkrete
   StaticFileResultOptions, med ContentFactory over native closure
   HttpResultFactory+<>c__DisplayClass30_0.
3. Closure-feltet options er nøyaktig det samme mutable alternativobjektet
   som metadatafabrikken bruker. Stien matcher den forventede native kilden.
4. Inner- og ytterfabrikken returnerer FileWriter. _filePath er tomt, og
   ContentFactory beholder denne native closure. Det finnes ikke et separat
   produksjonsbundet ReaderOptions-bevis i disse to tracene.

Native leserdelegat er GetStaticFileResult b__0(Int64, Int64,
CancellationToken), med SHA-256 av IL:
`6EF1D70DA9C84A39140CC50C0166C4A8A9670A07ED10ECB324632061E649FC1B`.
Dette er den samme leseren som ble bundet for statisk video i
[PRODUCTION-STATIC-SOURCE-BINDING.md](PRODUCTION-STATIC-SOURCE-BINDING.md).
Produksjonens service-/skriverkontroll for assets er aktiv, men videorutens
request-/kildebevis blir ikke brukt på disse to asset-rutene.

Den øvrige testen kontrollerer fortsatt egne/fremmede/anonyme svar, blandede
kilde-ID-er, faktisk A-profilsletting og faktisk omstart. Completed=true,
51 observasjoner, fire tracehendelser og prosessenes exit 0 er lest tilbake
for begge løp. Fixture-bygget passerer uten advarsler/feil.

Sluttkontrollen i `bin/native-asset-source-cleanup.json` er lest tilbake:
syntetiske kontoer, biblioteker, filer og fixture er fjernet, profiler/
journaler er borte og den isolerte Emby-prosessen er faktisk stoppet.

## Hva funnet betyr for neste rettelse

En kontroll av FileWriter._filePath kan ikke bevise disse kildene. Service-
og skriverkontroll på riktig private element-ID må suppleres med et bevis
som også binder den faktisk brukte leseren til autorisert kilde.

For de to prøvde direkte filene er native forventet kilde nå identifisert.
Transformerte bilder, alternative undertekstformater og avledede cachefiler
krever videre inspeksjon av kilde- og transformasjonskjeden. En ny kontroll
som bare godtar originalfilen vil kunne ødelegge avtalte vanlige Emby-klienter;
disse avledede kildene må også støttes og verifiseres, ikke bare avvises som
en erstatning for den avtalte funksjonen.

Denne runden injiserer ingen asset-filstifeil og påviser derfor ikke en
faktisk A/B-asset-utlevering gjennom en slik feil. Delt mutabelt objekt er
observert; vanlig klientutnyttelse er ikke påvist. Faktisk avledet kilde-/
cachebinding, native mutasjoner og alle klientfamilier er fortsatt åpne
beviskrav. Full skjerming er ikke bevist, og hovedserveren er ikke endret.
