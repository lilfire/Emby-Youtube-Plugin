# Native avledede bilde- og undertekstkilder

Senere inspeksjon 13. oktober 2026: den delte
`bin/native-asset-processing-inspection.json` er oppdatert til 57 metodekropper,
med cache-root og MD5-provider. Tallet 55 nedenfor er historisk. Se
[PRODUCTION-IMAGE-CACHE-RECIPE.md](PRODUCTION-IMAGE-CACHE-RECIPE.md) for den
nye lokale cacheoppskriftskontrollen og dens åpne innholds-/kildekrav.

Oppdatering 13. oktober 2026: Dette er en historisk inspeksjon før asset-
binding. Se [PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
for den nye produksjonsbindingen og bevarte `bound-`-rapporter. Den gamle
image-derived-rapporten nevnt nedenfor ble overskrevet av et mislykket
installasjonsløp (Completed=false) og kan ikke lenger støtte en bestått
PNG-test. Bruk `bin/bound-production-media-assets-image-derived-source-trace-results.json`
for det nåværende positive 51-observasjonsbeviset. Beskrivelsen av delt
mutabelt leseralternativ nedenfor gjelder før rettelsen; dagens trace viser
separate leseralternativer. Komplett cacheproveniens gjenstår.

12. oktober 2026. Isolert Windows Emby 4.10.1.0, lokale syntetiske A/B-filer,
produksjonsprofiler/native bindinger og eksperimentell guard deaktivert.
Dette identifiserer faktiske koblingspunkter for videre kildebinding. Det
implementerer ikke bindingen og beviser ikke full skjerming.

## Native metodeinspeksjon

`Test-ProductionMediaAssets.ps1 -InspectProcessing -RequireIsolation` fullfører
51 observasjoner. Faktisk lastet native IL er lagret i
`bin/native-asset-processing-inspection.json`; livsløpsrapporten ligger i
`bin/production-media-assets-processing-inspection-results.json`.

Inspektoren finner fire konkrete native familier: ImageService, ImageProcessor,
SubtitleService og SubtitleEncoder. 55 metodekropper er lest, inkludert
utvalgte async MoveNext-kropper og hjelpemetoder. Truncated=false gjelder
den avgrensede køen med dybdegrense fire; dette er ikke en full audit av alle
eksterne kall, kodeveier eller serverinnganger. Ingen runtime bruker-/token-
verdier leses eller skrives i denne IL-inspeksjonen.

Den inspiserte kjeden viser:

- ImageService.GetImage setter ImageProcessingOptions.Image og Item fra
  native bilde-/elementinformasjon og kaller IImageProcessor.ProcessImage.
  Prosessoren returnerer Tuple<string,string,DateTimeOffset>; Item1 brukes
  som StaticFileResultOptions.Path ved GetStaticFileResult.
- ImageProcessor.ProcessImage har native cacheoppslag og GetCacheFilePath,
  i tillegg til kilde-/bildehjelpere. En sjekk av at resultatstien bare ligger
  under en cachemappe kan ikke alene bevise dens relasjon til autorisert kilde.
- SubtitleService.GetSubtitles kaller ISubtitleEncoder.GetSubtitleJob med
  innholdskilde og valgt MediaStream. Konverteringsjobben har OutputPath.
  SubtitleEncoder.GetSubtitles leser også dette OutputPath-resultatet.

Utvalgte SHA-256-hasher av faktisk lastet IL:

| Metode | Hash |
| --- | --- |
| ImageProcessor.ProcessImage(options, token), tuple-resultat | F7FEFE139B5BD9049FE7DEC85A3490D6ADEC300CC3E4F401951726A21714B7AB |
| ImageService.GetImage MoveNext | 94B70D1ACA162B79FD9CAD5E1B6311A4E184366F0C7A51CFD59D7CA70AFAEFDB |
| ImageProcessor.GetCacheFilePath | 6099FEDB8EC28B3BF08D9D055EC3160991107083A62FCD98506478261505A628 |
| SubtitleEncoder.GetSubtitleJob | 648D30A8D9F44E7D8BF0F4A0BDBEDB7DE587BEA890F3AC304F610E3AD885648A |
| SubtitleService.GetSubtitles MoveNext | 8CD930F4DDBEBADDC3B8C30CAC5CE036E2CE1A99E43103DF1730A5507BEDA9AF |

Dette er inspeksjonshasher, ikke ferdig installerte produksjonskontrakter.

## Faktisk transformasjon og levering

`Test-ProductionMediaAssets.ps1 -TraceSource Image -TraceDerived -RequireIsolation`
fullfører 51 observasjoner i
`bin/production-media-assets-image-derived-source-trace-results.json`.
Det merkede kallet bruker MaxWidth=80, MaxHeight=45 og Format=png.
HTTP 200 leverer 197 byte; dekoding bekrefter PNG, akkurat 80x45 og den
forventede blå A-fargen. Dette skiller seg fra originalens 160x90/363 byte.

`Test-ProductionMediaAssets.ps1 -TraceSource Subtitle -TraceDerived -RequireIsolation`
fullfører 51 observasjoner i
`bin/production-media-assets-subtitle-derived-source-trace-results.json`.
Stream.vtt gir HTTP 200 og 63 byte med WEBVTT og privat A-markør uten B-markør.
Originalen er ekstern SRT på 71 byte.

Begge faktiske fabrikker får en filsti som er forskjellig fra den etablerte
originalstien. Tracene har fire hendelser hver: StaticFileResultOptions ved
fil-/nested-fabrikk, og native FileWriter ved inner-/ytterresultat. FileWriter
har fortsatt tomt _filePath; leseren beholder samme mutable options-objekt.
Den tidligere native lesermetoden/hashen er uendret. Ingen produksjonsbundet
separat ReaderOptions-bevis observeres for disse asset-rutene.

Den ekstra avledede forespørselen tester bare A sin tillatte transformasjon.
De resterende 50 observasjonene kontrollerer de eksisterende originale PNG/
SRT-rutene gjennom fremmede/anonyme/manglende kilder, sletting og omstart.
Dette er ikke et eget bevis for fremmede/anonyme avledede forespørsler eller
deres samtidighet. Begge prosesser fullfører med exit 0 og rapportene er
lest tilbake. Fixture-bygget passerer uten advarsler/feil.

Sluttkontrollen i `bin/native-derived-asset-source-cleanup.json` er lest
tilbake: syntetiske kontoer, biblioteker, filer og fixture er fjernet,
profiler/journaler er borte og den isolerte Emby-prosessen er faktisk stoppet.

## Konkret neste implementeringskrav

Kildebeviset må omfatte faktisk request/eier og native valgt bilde-/mediestrøm,
kopierte kilde-/transformasjonsalternativer, faktisk prosessor-/jobbresultat,
og den endelige filfabrikken/leseren. Resultatstien må knyttes til det samme
forespørselsbeviset og valideres ved konstruksjon, åpning og skriverkontroll.
Cachetreff og cacheproduksjon må kontrolleres, inkludert hva native oppslag
garanterer om kildens identitet. Mappetilhørighet alene er ikke et kildebevis.

Beviset må også dekke originalfilenes snarveier uten å kreve at hver fil går
gjennom en transformasjon. Nedskalering/konvertering skal fortsatt fungere
for de avtalte vanlige klientene. Videre arbeid må prøve faktisk feilvalg/
mutasjon, fremmede avledede kall og revokering; de observerte riktige A-filene
utelukker ikke slike feil. Andre varianter, native mutasjoner, bruker-/token-
revokering, serverbuilds og alle faktiske klientfamilier gjenstår.
