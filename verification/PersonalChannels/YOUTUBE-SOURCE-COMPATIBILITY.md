# YouTube-kilden er ikke den lokale MP4-kilden

Undersokt 2026-10-12 i den isolerte Emby 4.10.1.0-prosessen.
Dette endrer ingen produksjonskode eller hovedserverkonfigurasjon.

## Kode og faktisk innlastet produksjonsmetode

YouTubeChannel.Mapping.cs, MakeMediaSources, lager en kilde med YouTube
watch-URL, Protocol=Http, DirectPlay=true, DirectStream=false,
Transcoding=false og RequiresOpening/RequiresClosing=false.
Dette gjelder ogsa metodens isLive-variant med hensyn til opening/closing;
isLive styrer IsInfiniteStream. Live-varianten er her kodeinspeksjon.

PlaybackIntentInterceptor.NormalizeYouTubeMediaSources beholder watch-URL-en,
deaktiverer serverens direct stream/transcoding og fjerner TranscodingUrl.
Hvis IsLikelyNativeTheaterClient gjenkjenner native Theater uten en
gjenkjent nettlesermotor, settes ogsa DirectPlay=false.

En liten admin-beskyttet testprobe i fixture-pluginen kalte den faktisk
innlastede produksjonsmetoden MakeMediaSources med det syntetiske video-ID-et
shared00001, deretter den faktiske detektoren med IRequest og normalizeren
med dens resultat. Ingen foresporsel til YouTube, API-nokkel, bibliotek-
mutasjon eller avspilling var nodvendig for denne kontrollen.

Tre GET-kall til proben hadde folgende resultat:

| Innsendte testheadere | Native-detektor | DirectPlay etter normalisering | DirectStream / Transcoding | RequiresOpening / RequiresClosing |
| --- | --- | --- | --- | --- |
| Emby Web, Chrome-lignende User-Agent | false | true | false / false | false / false |
| Emby Theater, syntetisk native User-Agent uten nettlesermotor | true | false | false / false | false / false |
| Emby Theater, Chrome-lignende User-Agent | false | true | false / false | false / false |

I native-tilfellet var alle tre annonserte avspillingsmaater avslatt og
ingen TranscodingUrl til stede. I alle tilfeller var Path fortsatt en
YouTube watch-URL. Rapport: bin/youtube-source-normalization-results.json.
Kjoringen fullforte med exit 0, og normaliseringsutfallet ble eksplisitt
kontrollert etterpa mot Web-positivkontrollen og native-tilfellet.

Den forste probeversjonen feilet ved statisk binding mellom pluginenes
assembly-load-kontekster. Proben ble endret til aa bruke allerede innlastet
produksjonsassembly fra AppDomain; produksjonsmetodene ble ikke endret.
Feilet oppsett er ikke regnet som et avspillingsresultat.

## Betydning for kravet og videre kontroller

Dette beviser den navngitte produksjonsmetodens oppforsel for disse test-
headerne. Det er ikke en fysisk Theater-, Windows- eller Xbox-apptest, og
skal ikke brukes som paastand om at hver app med et slikt navn er native.
Nettlesermotoren er del av detektorens skille og ble kontrollert separat.

Kravet om fungerende personlige YouTube-biblioteker i alle klienttyper har
derfor et konkret uavklart kompatibilitetspunkt i dagens avspillingsmodell.
Passerende lokale MP4-/HLS-kontroller gir ikke en positiv kontroll av denne
YouTube-kilden i en native klient. En serverrespons som ikke tilbyr noen
avspillingsmaate kan heller ikke godkjennes bare fordi fremmed tilgang
blir avvist. Dette er et tilgjengelighets-/kompatibilitetspunkt, ikke en
nytt pavist personvernlekkasje.

Vanlig YouTube-kilde annonserer ikke RequiresOpening eller RequiresClosing.
Det gir ikke grunnlag for aa kreve en LiveStreamId i den vanlige annonsert
klientflyten. Det er fortsatt ikke bevis for at alle LiveStreams-ruter er
utilgjengelige for kjente private referanser; direkte rutekall og eventuelle
andre kildeleverandorer ma vurderes separat.

For aa lukke kravet trengs en faktisk positiv YouTube-avspillingskontroll
for hver aktuell klientfamilie og en avspillingsmaate for klienter som
dagens kode gjenkjenner som native uten nettlesermotor. En iframe i web og
en lokal MP4 brukes ikke som erstatning for dette kravet.

Alle journalforte testbrukere/biblioteker/filer ble ryddet, fixture/guard
fjernet, og autoritativ etterkontroll fant null EmbyServer-testprosesser.
Full skjerming og all-klient-kompatibilitet er fortsatt ikke godkjent.
