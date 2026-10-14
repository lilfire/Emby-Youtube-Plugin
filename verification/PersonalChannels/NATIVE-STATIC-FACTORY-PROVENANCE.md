# Faktisk filkilde bak GetVideoStream

Historisk utgangspunkt. Den etterfølgende produksjonsrettelsen og nye tester
står i [PRODUCTION-STATIC-SOURCE-BINDING.md](PRODUCTION-STATIC-SOURCE-BINDING.md).
Tracen med delt mutabelt objekt er bevart som
`bin/native-static-factory-before-source-binding-results.json`; dagens
`production-static-factory-trace-results.json` kontrollerer den nye bindingen.

12. oktober 2026. Isolert Windows Emby 4.10.1.0, lokale syntetiske A/B-videoer,
personlige profiler og native bindinger. Eksperimentell PrivacyGuard er
deaktivert og lest tilbake. Dette er runtime-inspeksjon og kontrollert
feilinnsprøyting, ikke en ferdig produksjonsrettelse eller full skjerming.

## Faktisk kjede

`Test-ProductionVideoStreams.ps1 -TraceStaticFactory -RequireIsolation`
fullfører 67 observasjoner i `bin/production-static-factory-trace-results.json`.
Fem faktiske A-kall dekker fullfil, standardkilde, HEAD, range og matching ETag.
Verifikatoren krever fem filfabrikk-kall, fem nested-fabrikk-kall, åtte
FileWriter-resultater og to EmptyHttpResult-resultater (inner/outer).

Den faktiske kjeden er:

1. GetStaticFileResult(IRequest, StaticFileResultOptions) har riktig A-filsti,
   uten innholdsfabrikk ved inngang.
2. GetStaticResult(IRequest, StaticResultOptions) mottar samme konkrete
   StaticFileResultOptions-type med en native innholdsfabrikk. Delegatens
   target er HttpResultFactory.<>c__DisplayClass30_0. Dets `options`-felt
   peker på nøyaktig samme alternativ-objekt som nested-fabrikken fikk.
3. FileWriter har tom `_filePath`, men beholder innholdsfabrikken med det
   samme native closure-mønsteret og riktig A-filsti i det fangede objektet.
   Matching ETag gir i stedet EmptyHttpResult, uten skriverens filsti/fabrikk.

Dermed er kontroll av FileWriter._filePath alene ikke en løsning. Det mutable
alternativ-objektet og den faktiske innholdsfabrikken må inngå i proveniensen.
Vi har ikke bevist at dette objektet deles mellom forskjellige HTTP-kall.

`bin/native-static-factory-inventory.json` inneholder faktisk metodeinventar.
Native hashverdier er:

| Metode | IL-hash |
| --- | --- |
| GetStaticFileResult(IRequest, string, FileShareMode) | CBE4B67BE6995F21A3331396F66EA67694A7CD3ED053D398D249FDDB28899CDA |
| GetStaticFileResult(IRequest, StaticFileResultOptions) | 2F31DF16E9D4669F8D95C3945A1D88A705DF182AF7635397030FD0D061C8A782 |
| GetStaticResult med åtte argumenter | 66958E7EF5FE1631950F1B7B4B60C8F6A3D8374B9607FEB72AB0C5C414204395 |
| GetStaticResult(IRequest, StaticResultOptions) | 4C716F3B7CB1817B7B1B25FD24854AF16614FA227E09B1DA38D5F22A545ACB11 |
| Closure-leseren GetStaticFileResult.b__0 | 6EF1D70DA9C84A39140CC50C0166C4A8A9670A07ED10ECB324632061E649FC1B |

Closure-leseren returnerer Task<StreamHandler>, men har ikke egen
AsyncStateMachineAttribute i denne builden. Dens videre I/O-kall og eventuelle
async-implementeringer er ikke verifisert bare av denne kickoff-metodens hash.

## Kontrollert mismatch

`Test-ProductionVideoStreams.ps1 -InjectFactoryMismatch` fullfører åtte
diagnostiske observasjoner i
`bin/production-static-factory-mismatch-diagnostic-results.json`.
En adminaktivert fixture validerer syntetisk A-identitet og A/B sine faktiske
native filer/biblioteker. Et eksplisitt markeringsheader på A sitt eget kall
utløser akkurat én endring: nested-fabrikkens alternativ-objekt får B sin
prøvefilsti etter at native closure allerede er opprettet. Video-ID og
MediaSourceId forblir A sine gyldige referanser.

Gjeldende produksjonskontroll leverer da HTTP 200 med 11071 byte:
OwnSourceHashMatches=false, ForeignSourceHashMatches=true, to filheadere og
IsolationPass=false. B sine ordinære fullfil/standardkilde/HEAD/range/ETag
forblir riktige. Fullført diagnostikk betyr at misforholdet er reprodusert;
det betyr ikke at isolasjonen er bestått.

Dette viser et uoppfylt kildebindingskrav under en kontrollert intern feil.
Det viser ikke at en vanlig Emby-klient kan endre dette objektet eller
utnytte et slikt bytte. De tidligere vanlige konto-/slettingstestene er
fortsatt avgrenset evidens for sine kjøringer, ikke for dette mismatch-vinduet.

## Konkret rettelse som gjenstår

- Knytt den autentiserte private forespørselen til godkjent native kandidat,
  eier, generasjon og faktisk kilde før filfabrikken åpner data eller lager
  cache-/validatorinformasjon.
- Gi den faktiske leseren en egen bundet kildebeskrivelse; delte eller mutable
  metadataalternativer skal ikke kunne velge en annen fil etter godkjenning.
  Verifiser eller opprett den korrekte factory-delegaten med denne bindingen.
- Bind både FileWriter og EmptyHttpResult til samme kildebevis. Et 304-svar
  må ikke slippe kontrollen fordi leseren aldri blir kalt.
- Kontroller fersk tilgang ved faktisk åpning og utsending. Ved avslag må
  allerede åpne håndtak og private headere ryddes også når native factory-
  eller tjenestetask feiler før den registrerte skriveren blir kjørt.
- Krev avslag uten fremmed innhold i den injiserte testen og kontroller
  tilsvarende HEAD/range/304, avbrudd, bytte etter åpning og cache-/kildeendring.
  Behold de tidligere tillatte A/B-kallene og faktisk omstart.

Dette supplerer [PRODUCTION-STATIC-VIDEO-STREAMS.md](PRODUCTION-STATIC-VIDEO-STREAMS.md).
Dynamisk/live/transkodet proveniens, øvrige serverinnganger, personlig
YouTube-henting/publisering og alle klientfamilier gjenstår fortsatt.

Opprydding er lest tilbake i `bin/native-static-factory-cleanup.json`:
syntetiske brukere, biblioteker, medier og fixture er borte, profiler/journaler
er borte, og den isolerte prosessen er faktisk stoppet. Tidligere
ServerStopped=false ved avslutning er bevart sammen med endelig true.
