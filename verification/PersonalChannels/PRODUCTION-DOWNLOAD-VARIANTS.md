# GetDownload: range, HEAD og betinget GET

12. oktober 2026. Isolert Windows Emby 4.10.1.0, lokale prøvevideoer og
syntetiske vanlige kontoer. Eksperimentell PrivacyGuard er deaktivert og
lest tilbake. Dette supplerer [PRODUCTION-DOWNLOAD-REVOCATION.md](PRODUCTION-DOWNLOAD-REVOCATION.md);
det beviser ikke full skjerming eller andre medieinnganger.

## Native referanse og kompatibilitetsfeil

`Test-NativeDownloadVariantBaseline.ps1` kontrollerer serveren uten personlige
profiler eller bindinger. Rapporten `bin/native-download-variant-baseline-results.json`
fullfører tre observasjoner: SHA-korrekt GET med 11071 byte, HEAD 404 uten
kropp og uten tjenesteinngang, og GET med korrekt If-None-Match gir 304 uten kropp.

Den første private HEAD-verifikatoren krevde 200 og feilet. Det var en feil
i testforventningen: HEAD støttes ikke på denne native ruten i denne builden.
Den ufullstendige rapporten er bevart i `bin/production-download-head-incomplete-results.json`.
Vi har ikke innført HEAD-støtte eller bevist den på andre ruter/builds.

Privat betinget GET ble derimot feilaktig blokkert med 404. Native svaret var
`Emby.Server.Implementations.Services.EmptyHttpResult`; den tidligere produksjons-
registreringen godtok bare StreamWriter og FileWriter. Det ufullstendige beviset
er bevart i `bin/production-download-conditional-incomplete-results.json`.

Runtime-inspeksjon viser at EmptyHttpResult implementerer IAsyncStreamWriter,
IHttpResult og IHasHeaders. Produksjonskontrollen beholder nå den originale
native skriveren og dens 304-semantikk, med samme ferske tilgangspredikat,
eiersperre, skriverregistrering og headeropprydding ved avslag som de andre
skriverne. Alle tre prefix/postfix/finalizer-settene verifiseres ved installasjon
og statusavlesning. EmptyHttpResult.WriteToAsync har IL-hash
`78E5066A9C7F4D3FAB5C9C6A7E275F7048B50F4A8713D28ADFC851183FA5F454`.

## Range og betinget GET

`Test-ProductionServiceGate.ps1 -DownloadVariant Range -RequireRaceSafe`
passerer 83 observasjoner i `bin/production-download-range-results.json`.
A sin tillatte forespørsel får 206 med de nøyaktige første 128 kildebyte og
Content-Range `bytes 0-127/11071`. B sin range til A får 404 uten filheadere,
med én kontroll og ett avslag fra produksjonsprefixen. A sin faktiske FileWriter
holdes før tilgangskontrollen, profilsletting fullføres og leses tilbake,
deretter frigjøres skriveren: 404, 16 byte generisk tekst, ingen privat navn
eller filheadere, én faktisk produksjonsskrivernektelse og kildehåndtak lukket.

`Test-ProductionServiceGate.ps1 -DownloadVariant Conditional -RequireRaceSafe`
passerer 83 observasjoner i `bin/production-download-conditional-results.json`.
A sin tillatte matching-ETag-forespørsel får 304 uten kropp. Samme ETag fra B
mot A gir 404 og én faktisk produksjonsprefix-nektelse. Den faktiske native
EmptyHttpResult-skriveren holdes mens A-sletting fullføres; ved frigjøring får
A 404 med generisk tekst, uten ETag eller øvrige filheadere. Produksjonskroken
registrerer én skrivernektelse. Dette er en virkelig 304-kandidat, ikke et
ubetinget GET som bare tilfeldigvis hadde en betinget header.

B beholder SHA-korrekt fullfil, egne GET/POST PlaybackInfo-kilder og sin egen
range/304 før, under og etter sletting samt etter faktisk omstart. B sine
range-byte og Content-Range kontrolleres mot B-kilden. B sine 304-svar har
samme ETag som den tillatte B-filen og ingen A-filnavn i headere.

## HEAD

`Test-ProductionServiceGate.ps1 -DownloadVariant Head -RequireRaceSafe`
fullfører 78 observasjoner i `bin/production-download-head-results.json`.

Den private HEAD-testen kontrollerer A og B mot begge kontoers native video-ID
i tre faser: aktive profiler, etter A-sletting og etter omstart. Alle tolv
kall får native 404, null byte, ingen privat filnavn eller filheadere.
Produksjonens tjenesteteller øker ikke; dette er den native rutens avvisning,
ikke et vellykket HEAD-svar eller en race ved HEAD-skriving.

## Gjenværende krav

Etter at EmptyHttpResult ble lagt til passerer regresjonene for full nedlasting
76 observasjoner, GET PlaybackInfo 75 og ventende listesletting 44. Endelig
opprydding er lest tilbake i `bin/production-download-variants-cleanup.json`:
syntetiske brukere/biblioteker/media/fixture er borte, personlig profilmappe og
journaler er borte, og den isolerte Emby-prosessen er faktisk stoppet. Tidligere
ServerStopped=false under prosessavslutning er bevart sammen med endelig true.

Ett rangeintervall og én matching-ETag-variant beviser ikke alle HTTP-varianter,
pakker som allerede er sendt, avbrudd, lange samtidige overføringer eller
alle endringer i native eierskap/journal/token. Progressive/HLS/transkoding,
bilder/undertekster, Sync/offline og andre serverinnganger gjenstår, sammen med
reell personlig YouTube-publisering og alle klientfamilier. Linux/Docker og
andre serverbuilds er fortsatt ikke verifisert.
