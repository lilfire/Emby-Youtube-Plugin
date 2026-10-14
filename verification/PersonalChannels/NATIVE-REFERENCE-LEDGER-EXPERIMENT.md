# Varige private native referanser: slettet rot

12. oktober 2026. Avgrenset isolert prototype, Emby 4.10.1.0,
to vanlige kontoer, native HomeVideos-biblioteker og lokale testvideoer.
Produksjonskoden og hovedserveren er ikke endret.

## Endring i testprototypen

`NativeReferenceLedger.cs` lagrer native rot-GUID, rot-ID, eierens
bruker-GUID og observerte medlemsreferanser (numeric ID og GUID).
Ved oppstart merkes en registrert rot slettet dersom den ikke finnes
eller numeric rot-ID peker pa en annen GUID. En slettet samlings
referanser tilordnes sentinel -1, slik at ingen autentisert konto
matcher. En ukjent manglende konfigurert rot avvises fortsatt.

Et live skann skal ikke overskrive en lagret slettet identitet. En
gjenbrukt rot-GUID reaktiveres derfor ikke automatisk. Dette er en
konservativ prototyperegel; gjenoppretting eller nyoppretting pa samme
sted trenger egen test og produktbeslutning. Det er ikke bevist at
Emby alltid lager ny native identitet for en ny samling.

Lagring bruker tempfil, erstatning og eksakt readback. Korrupsjon,
strombrudd og parallelle admin-konfigurasjoner er ikke testet. Det er
en annen fil enn det eksisterende registeret for hash av OpenToken;
ingen API-nokler eller raw tokens lagres i dette registeret.

## Kontrollerte resultater

`Test-NativeRootDeletion.ps1 -RequireIsolation` bestod med 15
observasjoner. Faktisk native sletting returnerte 204; rotens fravaer
ble lest tilbake. B hadde korrekt egen video (ID og navn) med 200
bade etter sletting og etter faktisk prosessomstart. Eget PlaybackInfo
hadde riktig lokal filkilde med 200 i begge fasene. Etter omstart var
guard Enabled/Ready med ny BootId og Public server info svarte 200.

B sin gamle A-video, A sin egen slettede video og B sin gamle A-rot
ble nektet med 404. Ingen 404-svar inneholdt de private videonavnene.
Disk-readback bekreftet at A sin slettede samling fortsatt inneholdt
den gamle video-ID-en, mens B sin aktive samling beholdt B sin
bruker-GUID og egen video-ID.

Rapport: `bin/native-root-deletion-durable-results.json`.

Sammenligningsbygg med `LEGACY_NATIVE_ROOT` bruker den tidligere
feilen pa ukjent rot. Med samme forbedrede oppstartsventing ble
guard ikke klar innen 30 sekunder; alle fire etterkontroller fikk
503, inkludert B sin egen video. Loggen inneholdt den eksplisitte
`Unknown private library root`-feilen. Ingen raw logg er publisert.
Rapport: `bin/native-root-deletion-results.json`, 11 observasjoner.
Den opprinnelige 500-observasjonen ved forste HTTP-svar er separat
bevart i `bin/native-root-deletion-first-response-results.json`.

Forste kjording av det nye registeret brukte forste HTTP-svar som
beredskapskriterium og stoppet for tidlig med 500. Den kjordingen er
ikke bestatt og er bevart som
`bin/native-root-deletion-durable-first-incomplete.json`. Den
korrigerte testen venter pa Ready, Enabled og ny BootId (maks 30 s).

Det normale registerbygget er gjenopprettet. En ny navnebytte-
regresjon bestod med 19 innholdskontrollerte observasjoner. Begge
kontoer beholdt egen video og egen PlaybackInfo-kilde og fikk 404
pa fremmed video for/etter navnebytte og etter omstart. Rot-ID/GUID
og det nye visningsnavnet var stabile. Rapport:
`bin/native-reference-ledger-rename-regression-results.json`.

## Praktiske grenser og videre arbeid

Dette er 34 bestatte observasjoner for registerendringen, pluss
en separat 11-observasjoners feilsammenligning. Antallet er ikke
et bevis pa alle ruter eller klienter.

Registeret oppdateres forelopig ved Enable/oppstartsavstemming.
Library ItemAdded/Updated/Removed-handleren oppdaterer fortsatt
bare den eksisterende historikken i minnet. Nye medlemmer som
kommer etter siste lagrede snapshot trenger derfor en egen
verifikasjon ved sletting og omstart, og deretter en losning med
varig registrering for de kan eksponeres.

Dette beskriver snapshot-versjonen av eksperimentet. En senere
undersokelse paviste tap av privat historikk for et nytt medlem som
ble slettet for et nytt snapshot, og testprototypen har naa varig
ItemAdded/Updated/Removed-registrering. Growth/sletting/restart og
rot-sletting/navnebytte-regresjoner er bestatt. Se
[NATIVE-MEMBER-EVENT-PERSISTENCE.md](NATIVE-MEMBER-EVENT-PERSISTENCE.md)
for faktisk dekning og fortsatt uavklarte tidsvinduer/avledede ressurser.

Ingen gammel OpenToken, LiveStreamId, Ready Sync-fil, avbrutt scan,
samme-navn-gjenoppretting eller gjenbrukt native ID er testet i denne
kjordingen. Metadata-404 for et slettet item kan ogsa skyldes at
Emby har slettet itemet; disk-readback dokumenterer den private
klassifiseringen, men beviser ikke tilgang til eventuelle gjenværende
native ressurser. Aktive/stale avledede ressurser trenger egne
positive og negative kontroller.

Som tidligere var A-roten midlertidig eid av testadmin for selve
native admin-slettingen. B-roten beholdt B. Det er ikke en test av
kontinuerlig A-tilgjengelighet i det betrodde intervallet.

Opprettelse av nye bibliotek/samlinger ma dessuten samordnes med
varig privat klassifisering slik at en bakgrunnsskanning ikke
publiserer innhold for det er beskyttet. Det er ikke implementert
som produksjonsflyt her. Alle native klientfamilier og faktisk
YouTube-avspilling er fortsatt utenfor dette lokale eksperimentet.

Testbrukere, biblioteker, filer, plugin, guard, begge registerfiler,
native register-tempfil og journal ble fjernet, og fravaer lest
tilbake. Prosessen er stoppet. Se
`bin/native-reference-ledger-cleanup.json` (alle felter true).
