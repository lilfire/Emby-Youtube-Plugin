# Native bilder, undertekster og HLS

Undersokt 2026-10-12 (Europe/Oslo) pa isolert Emby 4.10.1.0.
Produksjonspluginen og hovedserveren er uendret. Kravet gjelder tilgang mellom
Emby-kontoer pa serveren, ikke allerede lagrede lokale kopier.

## Oppsett og gyldige positive kontroller

To vanlige brukere hadde hvert sitt native bibliotek, en seks sekunders MP4,
en PNG og en ekstern engelsk SRT. A hadde blatt videobilde/bilde, B rodt.
Hver SRT hadde et eget syntetisk tekstmerke.

Bildene ble generert lokalt og lastet opp med administratorens native
[ImageService](https://dev.emby.media/reference/RestAPI/ImageService/postItemsByIdImagesByType.html)
for testbeskyttelsen ble aktivert. API-dokumentasjonen spesifiserer base64
og administratortilgang. Ingen privat innholdstilgang for administrator ble
lagt til i guarden for aa gjennomfore testen.

HLS brukte en faktisk PlaySessionId fra autentisert POST PlaybackInfo.
Hver bruker fikk mastermanifest, mediemanifest og forste MPEG TS-segment via
manifestenes egne lenker. Eventuelle token/API-key-parametere ble fjernet
for lenker ble brukt i fremmede og anonyme foresporsler. Dermed ble ikke
eierens legitimasjon brukt som bevis for en annen aktors tilgang.

## Resultater

`Test-NativeMediaAssets.ps1` fullforte med exit 0 og 60 HTTP-kontroller.
Rapport: `bin/native-media-assets-results.json`.

For begge eiere, for og etter bekreftet restart, ble fem ressurser kontrollert
som eier, annen bruker og anonym: PNG, SRT, HLS-master, HLS-mediemanifest og
forste segment. Det gav 20 positive eierkontroller og 40 negative kontroller.

| Ressurs | Eier | Annen bruker og anonym |
| --- | --- | --- |
| PNG | 200, 363 byte; SHA256 lik eget faktisk opplastet bilde i alle fire kontroller. | 404; ingen vellykket filrespons eller private markornavn. |
| SRT | 200, 71 byte og eget tekstmerke i alle fire kontroller. | 404 uten private markornavn. |
| HLS master-/mediemanifest | 200 og gyldig EXT-M3U-signatur i alle atte kontroller. | 404 uten private markornavn. |
| Forste HLS-segment | 200; 17672 eller 18612 byte, med MPEG TS-syncbyte 0x47 i alle fire kontroller. | 404; ingen vellykket segmentrespons eller private markornavn. |

Negative HTTP-feil i denne harnessen registrerer Bytes=0 fordi den ikke leser
feilresponsens raastrom. Tallet er ikke en direkte maler av HTTP-feilbodyens
lengde. Feilmeldingen ble separat kontrollert for private markornavn.

Den separate kjoringen `-ProbeSourceMismatch` fullforte med exit 0 og 64
rapportoppforinger: de samme 60 kontroller og fire sammenligninger, hver med
to HTTP-foresporsler. Det er 68 HTTP-kall som inngaar i disse kontrollradene,
ikke 64 unike ruter. Setup, innlogging og kontroll-API-er kommer i tillegg.
Rapport: `bin/native-media-assets-source-mismatch-results.json`.

I kilde-sammenligningene ble egen video-ID kombinert med den andre eierens
faktiske mediekilde-ID, og sammenlignet med en ikke-eksisterende kilde-ID.
Undertekstruten gav 200 med tomt innhold i begge tilfeller, lik normalisert
respons og ingen fremmed tekstmarkor. Dette ble provd for begge aktorer
for/etter restart. Det er et avgrenset bevis for denne undertekstruten med
disse filkildene, ikke for HLS-kildemismatch eller alle typer mediekilde-ID.

## Feilet testoppsett er beholdt

De forste forsokene fikk ikke en positiv videosegmentrespons. Det neste
diagnostiserte forsoket registrerte 400 paa segmentlenken med tom
PlaySessionId. Endringen var i foresporslene fra testharnessen: native
PlaybackInfo POST og dens faktiske PlaySessionId ble brukt. Testguarden ble
ikke endret for aa faa HLS-kontrollene til aa passere.

Rapporter for de ufullstendige kjoringene er beholdt som
`bin/native-media-assets-first-segment-failure.json` og
`bin/native-media-assets-empty-play-session-failure.json`. De er ikke
regnet som bestatte segmentkontroller.

## Avgrensning og opprydding

Dette er faktisk native utlevering av disse filene i testmodellen. Det er
ikke test av alle bilde-/undertekstaliaser, HEAD, mutasjoner, hele HLS-videoen,
andre kodeker, alternate-media-source-kombinasjoner eller LiveStreamId-ruter.
En TS-signatur beviser filformat og nyttelast, ikke bilde-/lyddekoding eller
at en bestemt TV-/mobilapp spiller filen. Slike klientkontroller gjenstar.

Oppryddingen fullforte med exit 0 og readback av journalforte brukere,
biblioteker og jobber. Journalforte MP4-/PNG-/SRT-filer, guard og testplugin
ble fjernet. En egen endelig prosesskontroll bekreftet null testservere.
Ingen reelle YouTube-nokler eller tilgangstokens er lagret i testresultatene.
Full skjerming er fortsatt ikke godkjent.
