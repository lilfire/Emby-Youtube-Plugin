# Biblioteksletting ved native lagring av konvertert Sync-fil

Undersøkt 2026-10-12 på isolert Emby 4.10.1.0. Kun testprototype og testskript er endret; produksjonsplugin og hovedserver er uendret.

## Resultat

Den fullførte konverteringsvarianten hadde 28 observasjoner: 22 HTTP-kontroller, fire native jobb-/elementoppslag og to kontroller av fysisk utdatafil. De testede tilgangskontrollene bestod. Native jobb og direkte jobbelement var borte både etter overlappet og etter faktisk omstart. **Den konverterte filen var fortsatt fysisk til stede i begge fasene.**

Dette er konkret evidens for at native jobb-/biblioteksletting ikke innebærer fysisk fjerning av alle avledede filer. Ingen undersøkte kall ga den andre kontoen eller en anonym klient tilgang til den gjenværende filen. Fravær av native jobb/element betyr samtidig at forsøket ikke beviser skjerming av en beholdt, fungerende Sync-referanse.

## Bekreftet overlapp

Testskript: [Test-NativeSyncPrepareRace.ps1](Test-NativeSyncPrepareRace.ps1), kjørt med `-Converted`.

Den eksisterende tidsproben ble utvidet med en konverteringsvariant. Den endrer ikke native status, kilde, jobb eller utdatafil. Den pauser `SyncManager.UpdateSyncJobItemInternal` bare når det virkelige argumentet har riktig syntetisk A-kilde og `ReadyToTransfer`, med eksisterende MP4-utdata under den isolerte serverens `data/sync` og forskjellig bane fra kildefilen. Proben frigjør sin egen lås før ventingen og har en automatisk grense på 25 sekunder.

Native oppretting av konverteringsjobben returnerte 200 før pausepunktet. Serverens faktiske SyncPrepare ble deretter startet. Ved pausepunktet ble følgende bekreftet:

- Native utdatafil var til stede: 12 405 bytes.
- `ffprobe` viste MPEG-4-video, seks sekunder, og utdatahash var forskjellig fra H.264-kilden.
- Den syntetiske A-roten ble slettet gjennom native administratoroperasjon.
- Direkte SDK-oppslag viste at både rot og kildevideo var borte **mens tidsproben fremdeles var Active og ikke TimedOut**.
- Eierskapskonfigurasjonens SHA-256 var uendret under slettingen.
- Proben ble eksplisitt frigjort, uten timeout, og native worker/SyncPrepare avsluttet.

Den nye klientprofilen ble satt opp på samme måte som i den vellykkede [konverterte filtesten](NATIVE-CONVERTED-SYNC-FILES.md). Et tidligere forsøk uten denne profilen fikk en native konverteringsfeil og nådde ikke pausepunktet. Det ble ikke slettet noe bibliotek i dette forsøket, og det regnes ikke som bestått samtidighetsdekning. Rapporten er beholdt som `bin/native-converted-sync-root-race-no-profile-incomplete.json`.

## Tilgang og tilstand etter frigjøring og omstart

Rapport: `bin/native-converted-sync-root-race-results.json`.

| Kontroll | Etter overlapp | Etter omstart |
|---|---|---|
| A/B/anonym, gammelt A-jobboppslag | 404 | 404 |
| A/B/anonym, gammel A-jobbelementliste | 404 | 404 |
| A/B/anonym, gammel A-filreferanse | 404, null rå bytes | 404, null rå bytes |
| Direkte native GetJob / GetJobItem | Begge borte | Begge borte |
| Konvertert A-utdata på disk | Fortsatt til stede | Fortsatt til stede |
| B egen overlevende Original-fil | 200, 11 071 bytes, riktig SHA-256 | 200, 11 071 bytes, riktig SHA-256 |

B sin fil ble også bekreftet før overlappet. Tre komplette B-hentinger og seks rå filavslag er dermed dokumentert. Legitimiteten til Sync-funksjonen ble observert før omstart. Skriptet krevde Enabled/Ready og ny guard-BootId etter omstart før siste kontrollrunde.

Original-varianten ble kjørt på nytt etter utvidelsen av tidsproben. Den fullførte med 26 observasjoner, bekreftet overlapp, omstart og eksplisitt frigjøring uten timeout. Rapport: `bin/native-sync-prepare-root-race-results.json`. Dette er regresjonskontroll for en konkret endring, ikke ny universell dekning.

## Betydning for løsningen

Pluginens varige samlings-/generasjonsmodell må også håndtere avledede filer når native jobb og kilde har forsvunnet. Fysisk opprydding trenger egne, validerte filbindinger. Man kan ikke basere den på at GetJob/GetJobItem fremdeles finnes eller anta at native sletting fjernet filen. Dette forsøket implementerer ikke en slik produksjonsmodell.

Forsøket gjelder ett faktisk skrivepunkt for MPEG-4-konvertering på denne serverversjonen. Sletting tidligere under ffmpeg-kjøringen, andre profiler, slettet/gjenopprettet eier, andre utleveringsruter og faktiske klientapper er fortsatt utenfor den verifiserte dekningen. Full skjerming er ikke bevist.

## Opprydding

Testskriptet fjernet den eksakt registrerte konverterte utdatafilen etter å ha bekreftet at banen var under isolert `data/sync` og filens SHA-256 var uendret. Ingen rekursiv sletting ble brukt. Syntetiske brukere, biblioteker, kilder og testplugin ble fjernet. Separat sluttkontroll etter begge kjøringer: `bin/native-converted-sync-root-race-cleanup.json` bekrefter ingen aktive EmbyServer-prosesser, ingen klientjournal og ingen gjenværende Sync-filer.
