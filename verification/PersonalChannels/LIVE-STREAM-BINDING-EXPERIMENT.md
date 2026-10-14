# Eierbinding for LiveStreamId: avgrenset retting i testprototypen

Undersokt 2026-10-12 pa isolert Emby 4.10.1.0. Ingen produksjonsendring.
Den tidligere metadata-lekkasjen er bevart i
bin/native-live-stream-access-results.json; den skal ikke overskrives av
passerende rettingstester. Se LIVE-STREAM-OWNERSHIP.md for moteksemplet.

## Endret kontroll i den isolerte prototypen

PrivacyGuard har naa en separat, prosesslokal LiveStreamOwners-tabell.
En Harmony-postfix pa den faktiske native MediaSourceManager.OpenLiveStream
venter pa resultatet og registrerer strom-ID-en for den private kilden
for aapningsoppgaven fullfores til kalleren. Source.Path sammenlignes med
de faktiske lokale biblioteksvideoene, uavhengig av innsendt ItemId.
En uavklart kilde eller konflikt settes til eier -1, og avvik mellom
forespurt elementeier og faktisk kildeeier avvises.

LiveStreamId er ikke lenger unntatt fra foresporslenes referansekontroll.
FindOwner slaar opp strombindingen, og sammenligningen bruker autentisert
tokenkonto, ikke innsendt UserId eller PlaySessionId. Bindinger beholdes
i prosessen etter Close slik at gamle kjente referanser fortsatt kan
avvises. Ingen egen varig database er innfort i dette eksperimentet.

## Native kontroller for begge eiere

Test-NativeLiveStreamAccess.ps1 -RequireIsolation fullforte med exit 0
baade for og etter en verifisert serverrestart med Enabled/Ready=true og
ny BootId. Hver kjoring hadde 18 observasjoner; totalt 36:

| Kontroll | Forventet og observert, begge eiere, begge kjoringer |
| --- | --- |
| Egen native Open | 200 |
| Egne strommetadata | 200, riktig privat videonavn |
| Fremmed MediaInfo med gyldig LiveStreamId | 404, ingen privat markor |
| Anonym MediaInfo, strom-ID i body | 401, ingen privat markor |
| Fremmed Open med eierens ItemId/UserId | 404 |
| Fremmed MediaInfo med spoofet UserId i query | 404 |
| Fremmed Close med kjent LiveStreamId og eierens PlaySessionId | 404 |
| Eierens MediaInfo etter fremmed Close-forsok | 200, riktig privat videonavn |
| Egen Close | 204 |

Rapporter: bin/native-live-stream-protected-before-restart-results.json og
bin/native-live-stream-protected-after-restart-results.json. Begge har
Completed=true, RequiredIsolation=true, TestIsolationPassed=true og
LeakCount=0. Restart-kontrollen er lagret separat i
bin/native-live-stream-protected-restart-ready.json.

Forste rettingstest stoppet fordi testens statuskrav for anonym body-
foresporsel var feil: Emby avviser denne med 401 for DTO-kontrollen, som
i baseline. Fremmed autentisert tilgang var allerede 404. Denne feilslatte
forventningen er bevart i
bin/native-live-stream-protected-anonymous-expectation-failure.json.
Ingen guard ble endret for aa faa det anonyme kall til aa passere.

## Hva denne rettingen ikke beviser

- Leverandoren er syntetisk og lokal; den flytter ikke videobytes og er
  ikke dagens YouTube-leverandor eller en fysisk TV-/mobilklient.
- Kildeeier finnes ved lokal filsti. Delte YouTube-URL-er og andre
  medieleverandorer trenger en eieridentitet som ikke avhenger av filsti.
- Bindingen opprettes etter native Open. Malicios miks av egen ItemId og
  fremmed OpenToken trenger prekontroll og egne sideeffektkontroller;
  denne kjoringen brukte ikke en slik miks. Avslag etter aapning alene
  beviser ikke at native sideeffekter er forhindret.
- Restarttesten opprettet nye strommer etter restart. Den beviser ikke
  kontinuitet av gamle aktive strommer, varig eierskap eller alle gamle
  referansers oppforsel etter restart.
- Samtidig Open/Close, slettet eier og alternative innganger til native
  stromtabell er ikke kontrollert her. Bare den hookede Open-metoden og
  de navngitte rutene er omfattet.

Det tidligere paviste MediaInfo-hullet er lukket for disse konkrete
gyldige strommene i prototypen. Full skjerming er fortsatt ikke bevist.

Normal journalfort opprydding leste tilbake at brukere/biblioteker var
borte og fjernet mediefiler, fixture og guard. Den separate kontrollen
bin/native-live-stream-protected-cleanup.json bekrefter ServerStopped,
JournalGone, FixtureGone og GuardGone. Hovedserveren ble ikke endret.
