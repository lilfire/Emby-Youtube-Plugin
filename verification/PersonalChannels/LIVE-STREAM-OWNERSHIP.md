# LiveStream-ID: eierkontroll er et eget krav

Undersokt 2026-10-12, isolert Emby 4.10.1.0. Ingen produksjonsendring.

En adminbeskyttet, read-only fixtureprobe leste metodereferanser fra IL i
serverens faktisk innlastede MediaInfoService og MediaSourceManager,
inkludert async state machines. Proben leste ikke instansverdier, tokens,
medieinnhold eller strommer. Rapporten native-live-stream-surface.json har
PowerShell-konvolutten value/Count; value er listen med typer.

## Konkret observerte kjeder

- Post(GetLiveStreamMediaInfo) leser LiveStreamId og kaller
  IMediaSourceManager.GetLiveStreamMediaSource(string).
- GetLiveStreamMediaSource(string) kaller GetLiveStreamInfo(string) og
  returnerer ILiveStream.MediaSource.
- GetLiveStreamInfo(string) kontrollerer tom ID og bruker TryGetValue i
  den felles ConcurrentDictionary<string, ILiveStream> _openStreams.
- Post(CloseMediaSource) leser LiveStreamId og PlaySessionId og kaller
  IMediaSourceManager.CloseLiveStream(string, string).
- CloseLiveStreamInternal sin async-body bruker den samme stromtabellen,
  RemoveConsumer og ConsumerCount. Dette er ikke et runtime-bevis pa at
  en annen bruker kan stenge en aktiv strom.

Den direkte metadata-oppslagskjeden over inneholder ingen referanse til
autorisert bruker eller kontoeierskap. Dette gjelder disse metodene, ikke
en paastand om fravaer av alle eksterne request-filtre. Innlogging alene
beviser heller ikke at en autentisert fremmed bruker er riktig eier.

PrivacyGuard.cs IsItemReference unntar LiveStreamId og PlaySessionId fra
elementreferanser. Den isolerte testprototypen har ingen egen vedvarende
LiveStream-ID-til-eier-tabell. Etterfiltrering av MediaSourceInfo er ikke
bevist aa ha tilstrekkelig informasjon i dette tilfellet. Derfor er et
positivt privat-strom-oppslag etterfulgt av fremmed tilgang en nodvendig
test; den er naa utfort med en syntetisk lokal leverandor, se nedenfor.

Produksjonens YouTube-kilde annonserer RequiresOpening=false og
RequiresClosing=false (se YOUTUBE-SOURCE-COMPATIBILITY.md). Den opprinnelige
IL-inspeksjonen opprettet ingen strom. Den etterfolgende native testen
opprettet en gyldig strom med en syntetisk leverandor, men viser fortsatt
ikke at vanlig YouTube-avspilling bruker disse rutene.

## Konsekvens for losningen

Hvis den endelige avspillingsmodellen oppretter LiveStreams, ma kontrollen
knytte gyldig strom-ID til element/samling og autentisert eier og handheve
dette for metadata og endringer. Alternativt trengs bevis for at private
kilder ikke kan opprette eller eksponere slike strommer gjennom noen
tilgjengelig inngang. RequiresOpening=false alene er ikke dette beviset.

Kort bevisuttrekk og SHA256 for de undersokte serverassemblyene er lagret i
bin/native-live-stream-lookup-evidence.json. Hele referanseinventaret er
bin/native-live-stream-surface.json. Statisk IL-referenceinventar er ikke
komplett kontrollflytdekompilering eller en klient-/avspillingskontroll.

Fixture-opprydding leste tilbake at testbrukere og biblioteker var borte.
Etterkontrollen bin/native-live-stream-surface-cleanup.json bekrefter
ServerStopped, JournalGone, FixtureGone og GuardGone. Full skjerming er
fortsatt ikke bevist.

## Etterfolgende native test: konkret metadata-lekkasje i prototypen

Test-NativeLiveStreamAccess.ps1 fullforte med exit 0 og 12 observasjoner.
Rapport: bin/native-live-stream-access-results.json, Completed=true,
GuardReady=true, FullIsolationPassed=false, LeakCount=2.

For hver av de to private native videoene var resultatet:

| Handling | Eier | Den andre vanlige kontoen | Anonym |
| --- | --- | --- | --- |
| LiveStreams/Open, riktig privat ItemId | 200 | 404 | Ikke provd |
| LiveStreams/MediaInfo, eierens gyldige LiveStreamId | 200 | 200 | 401 |
| LiveStreams/Close | 204 | Ikke provd | Ikke provd |

Begge fremmede MediaInfo-svar inneholdt eierens eksakte syntetiske
videonavn, privat lokal mediefilsti og syntetiske kilde-ID. Eierens
positive kontroll viste de samme markorene. Fremmed Open-brukte eierens
UserId/ItemId og ble likevel nektet med 404: tokenets faktiske konto ble
brukt for den eksisterende elementkontrollen. MediaInfo angav bare den
kjente, gyldige strom-ID-en og passerte derfor en annen kontrollsti.

Dette er en faktisk metadata-lekkasje i testprototypen gjennom Embys ekte
native ruter. Det er ikke bevis for overforte videobytes, en vellykket
fremmed Close-operasjon, en fysisk klient eller dagens YouTube-flyt.

Oppsettet brukte en liten lokal IMediaSourceProvider/ILiveStream-adapter
i fixture-pluginen, avgrenset til de to journalforte private MP4-filene.
Et adminbeskyttet fixture-kall klargjorde den native kildelederens egen
innpakkede OpenToken og registrerte leverandoren; vanlig fil-PlaybackInfo
valgte bare statisk kilde. Deretter brukte eierens normale konto native
LiveStreams/Open med sin ekte PlaySessionId. Ingen strom ble injisert
direkte i _openStreams, ingen guard ble deaktivert og ingen ruterespons
ble erstattet. Leverandoren stotter metadata/open/close, ikke CopyToAsync;
denne testen prover derfor ingen videoutlevering.

Forste oppsettsforsok manglet dynamisk token, ble nektet av elementfilteret
ved admin-klargjoring, traff forskjellen mellom SDK/serverens provider-
interface, og gav deretter HTTP 400 fordi fixture-kilden manglet
LiveStreamId. Disse oppsettsfeilene teller ikke som privat tilgang eller
positiv avspilling. Testadapteren implementerer installert interface ved
DispatchProxy og setter en ny syntetisk strom-ID ved Open. Det endrer
ingen produksjons- eller Emby-metode.

Eierens Close gav 204 begge ganger. Etter normal journalfort opprydding
ble brukere/biblioteker/filer fjernet og fixture/guard avinstallert fra
testserveren. bin/native-live-stream-access-cleanup.json inneholder en
separat autoritativ prosess-/filkontroll. Ingen hovedserver ble endret.
