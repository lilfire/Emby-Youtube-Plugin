# Statisk GetVideoStream: konto, mediekilde og ventende svar

Etterfølgende binding av faktisk native leser og separat filalternativ-kopi
er dokumentert i [PRODUCTION-STATIC-SOURCE-BINDING.md](PRODUCTION-STATIC-SOURCE-BINDING.md).
Den lukker den prøvde interne filstifeilen; øvrige kilde-/klientkrav består.

12. oktober 2026. Isolert Windows Emby 4.10.1.0, syntetiske ikke-administrative
A/B-kontoer og lokale prøvevideoer med personlige profiler/native bindinger.
Eksperimentell PrivacyGuard er deaktivert og lest tilbake. Hovedserveren er
ikke endret av denne verifiseringen. Full skjerming er fortsatt ikke bevist.

## Konkret lekkasje

`bin/production-video-stream-diagnostic-results.json` fullførte 19 observasjoner
før GetVideoStream ble lagt til produksjonskontrollen. Begge kontoer fikk den
andres hele prøvevideo gjennom `/Videos/{Id}/stream.mp4?Static=true&MediaSourceId=...`:
HTTP 200, 11071 byte og SHA identisk med fremmed kildefil. HEAD ga 200 med
filinformasjon, range ga 206 med 128 byte, og matching ETag ga 304 med validator.
Produksjonens tjenesteteller økte ikke for disse rutene. Fullført diagnostikk
er dermed evidens for lekkasje, ikke et bestått isolasjonsbevis.

Egen video-ID kombinert med fremmed MediaSourceId ga native 400 uten fremmed
filinnhold i denne diagnostikken; vi påviste ikke videolekkasje i denne kombinasjonen.
Den trenger likevel eksplisitt provenienskontroll og konsistente private avslag.

## Produksjonsendring

`Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream` er nå den ellevte
eksplisitt kontrollerte DTO-en. Den faktiske autentiserte kontoen må ha tilgang
til det registrerte private native elementet. DTO-verdier kopieres til
tilgangspredikatet før native kjøring, og predikatet kontrolleres under
eiersperren, etter native resultat og ved faktisk skriverinngang.

For statiske private kilder brukes native GetAllItemsForMediaSources med den
faktiske User. Kilden må finnes blant elementets native kandidater gjennom
GetDefaultMediaSourceId og ha samme gyldige private eierskap. Ved tom kilde-ID
må alle native kandidater være tillatt; ingen eller over 128 kandidater avslås.
Fremmed og manglende kilde-ID gir samme generiske 404 uten filheadere.
Kilde-ID-en behandles ikke som en tilgangsnøkkel.

Den interne native kandidatmetoden brukes gjennom en verifisert
refleksjonskontrakt fordi SDK-metoden ikke er offentlig. En første direkte
SDK-bruk ga kompileringsfeil og en test kjørte derfor den eldre DLL-en; den
ufullstendige testen er ikke grunnlag for denne rettelsens bevis. Gjeldende
build passerer uten advarsler. Installasjon krever disse faktiske IL-hashene:

- GetAllItemsForMediaSources: `D5DB52411B126F017217D8D1CE66E60A324D522F2F33D5B6FF0F4BA01D486E81`.
- GetDefaultMediaSourceId: `CD50AC8D2CB3110C3F0E52B356F4CAA4E6CE3422F3BF34E3042FE6A522C6DB22`.

Den eksisterende felles skriverkontrollen beskytter FileWriter og
EmptyHttpResult ved faktisk utsending. Ved nektelse frigjøres åpnet kilde og
private headere fjernes fra det underliggende HTTP-svaret.

## Native verifisering

`Test-ProductionVideoStreams.ps1 -StreamWriteRace Full`, `Head`, `Range` og
`Conditional` fullfører 76 observasjoner hver. Rapportene ligger i
`bin/production-video-stream-{full,head,range,conditional}-write-results.json`.

- Begge aktive eiere får SHA-korrekt egen fullfil og egen standardkilde uten
  MediaSourceId. Stream-HEAD får 200, null byte og korrekt filstørrelse.
  Range får de nøyaktige 128 kildebyte med korrekt Content-Range.
  Matching ETag gir 304 uten kropp og med samme tillatte validator.
- Fremmed fullfil/HEAD/range/ETag og blandet/manglende kilde-ID får generisk
  404 uten filheadere. Hvert avslag krever én faktisk produksjonskontroll
  og én prefix-nektelse. Dette kontrolleres også etter sletting og omstart.
- Den faktiske native skriveren for A holdes før produksjonens skrivekontroll.
  A-sletting fullføres og leses tilbake mens HTTP-kallet fortsatt venter.
  Etter frigjøring kreves 404, eksakt generisk feiltekst (null kropp ved HEAD),
  feilsvarets Content-Length 16 og ingen private filheadere.
- Produksjonskroken må stå Installed og registrere akkurat én skrivernektelse.
  Kildehåndtak må være lukket slik at prøvefilen kan åpnes eksklusivt.
- B beholder sin fullfil, standardkilde, HEAD, range og ETag før/under/etter
  sletting samt etter faktisk serveromstart. A kan ikke hente sine beholdte
  native referanser etter profilsletting, også etter omstart.

Stream-HEAD støttes her. Dette skiller seg fra den native GetDownload-ruten,
der HEAD er ustøttet og ga 404 allerede uten private profiler/bindinger.

Etter utvidelsen til elleve DTO-er passerer matching-ETag-nedlastingsregresjonen
83 observasjoner, GET PlaybackInfo 75, listeskrivesperren 44 og komponentene
186. Endelig opprydding er lest tilbake i `bin/production-static-video-cleanup.json`:
syntetiske brukere, biblioteker, medier og fixture er borte, profiler og
journaler er borte, og den isolerte prosessen er faktisk stoppet. Tidligere
ServerStopped=false ved avslutning er bevart sammen med endelig true.

## Vesentlige begrensninger

Private GetVideoStream med Static=false eller LiveStreamId er foreløpig
avvist. Dynamisk/live/transkodet proveniens og deres skrivere må implementeres
og verifiseres for å oppnå den avtalte klientstøtten. Dette er en uferdig
produksjonsimplementering i isolert verifisering, ikke en utrullingsklar plugin.

Dette beviser ikke alle alternative versjoner, kildebytter, innsetting/reparenting,
journal-/tokenendringer, nettverkspakker allerede sendt, avbrudd, lange overføringer,
andre HTTP-varianter eller alternative rutestier. Audio, HLS/transkoding,
bilder/undertekster, Sync/offline, øvrige innganger, faktisk personlig
YouTube-henting/publisering og alle klientfamilier gjenstår. Andre serverbuilds,
Linux og Docker er fortsatt ikke verifisert.

Kontrollen binder ennå ikke den faktiske skriverens filsti/innholdsfabrikk
separat til kandidatens proveniens ved samtidige kilde- og cacheendringer.
SHA-kontrollene beviser de normale prøvefilene i kjøringene; denne bredere
koblingen er et eksplisitt gjenværende krav.
