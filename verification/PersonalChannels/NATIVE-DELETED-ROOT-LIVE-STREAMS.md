# Gjenværende native strøm etter privat biblioteksletting

12. oktober 2026. Isolert Emby 4.10.1.0, vanlige kontoer A/B,
syntetiske lokale videoer. Produksjonspluginen og hovedserveren er urørt.

`Test-NativeMemberGrowthDeletion.ps1 -RequireDurability -DeleteWholeRoot
-WithLiveStreams` bestod 35 observasjoner og native tilstandskontroller.
Testen bruker den faktiske native MediaSourceManager/Open/MediaInfo/
Close-kjeden og `_openStreams`-registeret, med en avgrenset syntetisk
IMediaSourceProvider/ILiveStream som metadataadapter.

## Faktisk gjenværende ressurs

Begge kontoer åpnet egen strøm med 200 og fikk korrekt egen
kildemetadata med 200. Native register-readback bekreftet én A-strøm
og én B-strøm. B fikk 404 på A sin MediaInfo og Close med kjent
LiveStreamId/PlaySessionId, og A fikk fortsatt korrekt metadata
etter B sitt lukkeforsøk.

Etter innskanning av ny A-video og native adminsletting av hele A-
roten (204) var rot og video borte fra katalogen. Eierskapsconfig var
uendret og det var ikke gjort noe nytt Guard Enable/snapshot. Den
åpne A-strømmen var likevel fortsatt i det faktiske native registeret.
A kunne fortsatt lese dens metadata med 200 og det private videonavnet.
Dette er faktisk gjenværende servermetadata, ikke bare en gammel ID
som er borte fra Emby.

B fikk 404 på denne strømmen både ved MediaInfo og Close. Native
A-strømtall og provider-close-tall forble uendret under B sine forsøk.
B fikk korrekt egen strømmetadata med 200 og kunne lukke egen strøm
med 204. Det er derfor ikke en generell blokkering av alle strømmer.

At A fortsatt kan lese sin tidligere legitimt åpnede serverstrøm er
ikke en lekkasje mellom kontoer. Dette forsøket beviser ikke full
tilbakekalling av allerede åpne strømmer for den opprinnelige eieren.
Godtatt omfang er servertilgang mellom Emby-kontoer; eventuell strengere
tilbakekallingsatferd ved sletting trenger egen produktbeslutning.

## Etter faktisk omstart

Guard var Enabled/Ready med ny BootId og den slettede referansen var
fortsatt klassifisert privat/i karantene. Bare B sin eksisterende
kilde ble forberedt for registrering av den native testprovideren.
B-kildens nye wrapped token var identisk med det gamle. B kunne åpne
egen strøm og få riktig egen metadata med 200.

A sin gamle LiveStreamId var ikke lenger i native registeret. B sine
MediaInfo/Close-kall med den gamle ID-en fikk 204. Separate kall med
en tilfeldig ukjent ID fikk samme 204; MediaInfo-svarene var tomme.
Dette er observert native fraværsatferd, ikke tilgang til A sin gamle
kilde. Ingen A-navn/path ble observert i B sine svar.

Det lagrede A-OpenToken ble ikke reutstedt. B sitt forsøk på åpning
uten ItemId fikk 404. A sitt forsøk uten ItemId fikk 400 fordi den
native fixture-kilden ikke lenger kunne finnes. Verken native A-
strømtall eller provider-open-tall økte. B sin allerede åpne egen
strøm hadde fortsatt korrekt metadata med 200 etter begge forsøkene,
og egen Close fikk 204. Native register var tomt ved sluttkontrollen.

Dette dekker ett faktisk lagret åpningstoken for en slettet kilde,
ikke aldri-utstedte tokens eller alle leverandørers kildeoppløsning.

## Evidens og grenser

`bin/native-growth-root-live-stream-results.json` har Completed=true,
native katalogsletting/readback, guard-ready/restart, uendret config/
godkjenningsdigest, varig karantene og de 35 observasjonene.
`bin/native-growth-root-live-stream-state-results.json` har true for
AStreamRetainedImmediatelyAfterRootDelete, ForeignStreamChecksNoMutation,
OldDeletedTokenNoMutation og FinalNativeStreamsEmpty.

Første kjøring stoppet ved forventet 404 versus faktisk tom 204 på
en gammel ID etter omstart. Den er separat bevart som
`native-growth-root-live-stream-first-incomplete.json` og tilhørende
state-first-incomplete; den regnes ikke som bestått. Den korrigerte
testen sammenligner med faktisk ukjent-ID-atferd.

Provideren gjør ikke CopyToAsync og denne kjøringen beviser ikke
videobyter eller full transportavspilling. Ready Sync-filer, andre
leverandører, aldri-utstedte tokens, samtidige sletting/åpning-kall,
nyoppretting/ID-gjenbruk og faktisk YouTube-avspilling i alle klienter
er fortsatt ikke bevist her. Tidligere transporttester gjelder andre
tilstander og må ikke brukes som bevis for denne slettingssituasjonen.

Medier, testkontoer/biblioteker, fixture, guard, registre/tempfiler og
journal er fjernet og serverprosessen stoppet. Alle felter i
`bin/native-growth-root-live-stream-cleanup.json` er true.
