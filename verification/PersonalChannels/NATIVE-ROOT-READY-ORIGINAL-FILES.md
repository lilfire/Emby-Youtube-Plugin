# Native Ready Original-filer ved sletting av privat biblioteksrot

12. oktober 2026. Isolert Emby 4.10.1.0, to vanlige kontoer og
native HomeVideos-biblioteker med syntetiske lokale videoer.
Produksjonspluginen og hovedserveren er urørt.

`Test-NativeOwnerReadyFiles.ps1 -DeleteRoot` bestod med 31
observasjoner: 29 HTTP-kontroller og to native retention-readbacks.
En første kjøring er bevart separat. Den siste styrker kontrollen
ved å lese også HTTP-feilsvar som rå bytes; kjøringene telles ikke
som ulik scenariodekning.

Dette beskriver 31-observasjoners versjonen, nå bevart i
`bin/native-root-ready-files-raw-body-results.json`. Den gjeldende
hovedrapporten har senere fått fire direkte native elementkontroller
og har 35 observasjoner. Se
[NATIVE-ROOT-SYNC-ITEM-RETENTION.md](NATIVE-ROOT-SYNC-ITEM-RETENTION.md).

## Faktiske filer før sletting

Begge kontoer opprettet egen native Sync-jobb med Quality/Profile
Original. Native SyncPrepare klargjorde én ReadyToTransfer-jobitem
per jobb. Den faktiske sikkerhetsmanageren rapporterte legitimt
sync-feature-check med Allowed=true; testen omgår ikke lisenskravet.

A og B hentet egne komplette filer med 200. Begge var 11 071 bytes
og samsvarte med korrekt lokal kildefil ved SHA-256. B sitt forsøk
på A sin ferdige fil fikk 404 med null payload-bytes.

Testadmin forhåndsgodkjente den avgrensede native slettingen av A-
roten og utførte faktisk POST Library/VirtualFolders/Delete.
GetItemById-readback bekreftet at rot og video ikke lenger fantes
i katalogen. A sin konto ble beholdt, og SHA-256 av den lagrede
eierskapskonfigurasjonen var uendret. Ingen midlertidig admin-
tilordning eller nytt Guard Enable-snapshot ble brukt.

## Etter sletting og omstart

B, den fortsatt eksisterende A-kontoen ("old-a" i testetiketten)
og anonym klient fikk 404 på gammel A-jobb, jobitems-query og
filreferanse, både etter sletting og etter faktisk serveromstart.
Det er 18 avslag i de to fasene, pluss filavslaget før sletting.
Ingen av 404-svarene inneholdt de private videonavnene.

Alle sju avslåtte filforespørsler ble lest som rå responsbytes og
hadde **0 payload-bytes**. Dermed viser testen mer enn riktig
statuskode eller fravær av et navn i et tekstsvar.

B fikk fortsatt egen komplette Original-fil med 200 etter sletting
og etter omstart, med 11 071 bytes og korrekt SHA-256 begge ganger.
Det er fire komplette hash-verifiserte filer totalt i kjøringen.
B sine jobber/Ready-lister svarte 200 uten A-navnet; egen jobb/Ready-
liste hadde fortsatt B sitt forventede navn. Guard var Enabled/Ready
med ny BootId etter omstart.

## Viktig retention-begrensning

Admin-proben kalte faktisk native SyncManager.GetJob med gammel
A-jobb-ID. Jobben fantes **ikke** etter sletting eller etter omstart.
Dette er derfor et bevis for gamle referanser til en tidligere
ferdig fil når Emby har fjernet jobben, ikke for isolasjon av en
native jobb som blir liggende igjen.

Den opprinnelige mediefilen kan fortsatt ligge fysisk på disk etter
virtuell rot-sletting. Det er ikke i seg selv en gjenværende Ready-
jobb eller fungerende serverfilreferanse. Proben fastslår heller
ikke generell fravær av alle mulige foreldreløse jobitem-rader eller
andre API-referanser. Ingen retention-rad med Exists=false må
beskrives som en vellykket test av en beholdt Sync-ressurs.

Oppfølging: direkte GetJobItem bekrefter nå at den konkrete gamle
A-elementraden også er borte etter sletting og omstart. Dette lukker
readback-gapet for denne ID-en, men ikke generell fravær av
foreldreløse elementer under andre tilstander.

Rapport: `bin/native-root-ready-files-results.json`. Completed,
RootDeletionReadback, OwnerKeptWithUnchangedConfiguration,
RestartVerified og LegitimateFeatureCheck er true. Native retention
er false i begge readbacks. Første kjøring med tekst-/statuskontroller
er i `bin/native-root-ready-files-first-results.json`.

Fortsatt uavklart: faktisk beholdt/foreldreløs native Ready-ressurs,
parallelle klargjørings- og sletteoperasjoner, andre Sync-profiler,
andre strømtransportreferanser, nyoppretting/ID-gjenbruk og den
faktiske YouTube-funksjonen i alle klientfamilier. Full skjerming
er ikke bevist av denne begrensede kjøringen.

Testbrukere, biblioteker, Sync-jobber (readback i standard cleanup),
syntetiske medier, fixture, guard, registre/tempfiler og journal ble
fjernet. Serverprosessen er stoppet. Se
`bin/native-root-ready-files-cleanup.json` (alle felter true).
