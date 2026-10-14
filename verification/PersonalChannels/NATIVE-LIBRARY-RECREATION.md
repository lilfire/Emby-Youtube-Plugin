# Slettet privat bibliotek opprettet på nytt for en annen konto

Undersøkt 2026-10-12, isolert Emby 4.10.1.0. Ingen endringer i produksjonspluginens kildekode eller hovedserveren. Skjerming gjelder tilgang mellom kontoer på serveren; tidligere lokale kopier på en delt enhet er utenfor den avtalte testen.

## Resultat

Samme biblioteksnavn med **ny fysisk mappe** bestod de målte kontrollene. Samme navn med **gjenbrukt fysisk mappe** ga et reproduserbart funksjonsavvik: B fikk ikke metadata for sin nye video, selv om B fikk korrekt PlaybackInfo og hele den riktige videofilen. Ingen undersøkte fremmedkall ga A eller en anonym klient tilgang til B sin video.

Dette er et avvik i den eksperimentelle skjermingen, ikke et bevis for at den opprinnelige bibliotekbegrensningen er tilstrekkelig, og heller ikke en observerbar lekkasje mellom kontoene i disse testene.

## Oppsett og kontroller

Testskript: [Test-NativeRootRecreation.ps1](Test-NativeRootRecreation.ps1).

1. Bekreftet at vanlige A og B kunne lese egne opprinnelige videoer, og at B ble nektet A sin video.
2. Slettet A sitt bibliotek gjennom den native administratoroperasjonen. SDK-oppslag bekreftet at gammel rot og video var borte. Eierskapskonfigurasjonens hash var uendret under slettingen.
3. Opprettet samme biblioteksnavn for B, med en ny syntetisk videofil og enten ny mappe eller samme fysiske mappe som tidligere A. Den gamle A-filen ble fjernet i varianten med gjenbrukt mappe.
4. Leste tilbake B sin native bibliotekpolicy, med de to egne bibliotek-GUID-ene og uten EnableAllFolders. Konfigurerte eierskapet i testprototypen til B.
5. Testet nye rot- og videoreferanser som både numerisk ID og GUID, gammel A-video, PlaybackInfo og rå nedlasting. Kontrollerte B sitt opprinnelige bibliotek som positiv kontroll.
6. Gjentok kontrollene etter faktisk serveromstart og ny guard-BootId. SDK-kontroller registrerte native synlighet, videoens samlingsrot og foreldremappens private status.

De endelige rapportene inneholder hver 37 observasjoner: 35 HTTP-kall og to diagnostiske SDK-observasjoner. `Completed=true` betyr at forsøket ble fullført, ikke at alle forventninger bestod.

| Måling, før og etter omstart | Ny mappe | Gjenbrukt mappe |
|---|---|---|
| B egen nye rot, numerisk ID/GUID | 200 | 200 |
| B egen nye video, numerisk ID/GUID | 200 med riktig videonavn | **404, fire avvik totalt** |
| B egen PlaybackInfo | 200, riktig filkilde | 200, riktig filkilde |
| B egen rå videofil | 200, 11 071 bytes, korrekt SHA-256 | 200, 11 071 bytes, korrekt SHA-256 |
| A nye rot-/videoreferanser og PlaybackInfo | 404 | 404 |
| A og anonym klient rå ny videofil | 404, null responsbytes | 404, null responsbytes |
| A/B gammel slettet A-video | 404 | 404 |
| B opprinnelig egen video | 200, riktig videonavn | 200, riktig videonavn |

Rapporter: `bin/native-root-recreation-results.json` og `bin/native-root-recreation-reused-folder-results.json`. Tidligere smalere kjøringer er bevart separat og telles ikke som ekstra dekning.

## Identiteter og årsak

Begge varianter fikk nye numeriske rot-/video-ID-er og ny bibliotekrot-GUID. Ved gjenbruk av fysisk mappe ble **foreldremappens GUID gjenbrukt**, selv om dens numeriske ID var ny. Ved ny fysisk mappe var også foreldremappens GUID ny.

I varianten med gjenbrukt mappe viste SDK-kontrollene begge ganger:

- Den nye videoen var kjent privat og ikke satt i karantene.
- Foreldremappen var kjent privat og satt i karantene.
- Native `IsVisible(B)` og `IsVisibleStandalone(B)` var begge sanne.
- Videoens native samlingsrot var B sitt nye bibliotek, hvis GUID fantes i B sin tilbake­leste bibliotekpolicy.

Dette avgrenser feilen til prototypens håndtering av foreldremappens historiske identitet, fremfor en manglende B-policy eller generell native usynlighet. Kildekoden bevarer gamle referanser som karantene og kontrollerer også `ParentId` i metadataresponsen. At en slettet samlings gamle foreldremappe-GUID kolliderer med den nye samlingens mappe, forklarer kombinasjonen av metadataavslag og fungerende PlaybackInfo/nedlasting. Det siste årsaksleddet er en slutning fra disse readbackene og filterkoden; testen instrumenterte ikke det enkelte DTO-avslaget.

## Konsekvens for løsningen

Den planlagte løsningen må ha en egen, varig samlingsidentitet og en eksplisitt generasjon ved sletting/gjenoppretting. Eierskap og historiske referanser må knyttes til samling/generasjon, og native bibliotek-, mappe- og videoidentiteter må bindes og valideres mot denne. En global tabell som bare mapper Emby-GUID til eier eller karantene er ikke tilstrekkelig til å håndtere legitim gjenbruk uten funksjonsavvik.

En ny fysisk mappe per samling/generasjon er en konkret kandidat: den testede varianten unngikk kollisjonen og bestod. Dette er ennå ikke et fullstendig bevis eller en ferdig produksjonsløsning. Andre former for identitetsgjenbruk, konkurrerende endringer, eksisterende strømmer/sync-ressurser og klientkompatibilitet trenger fortsatt dekning. Ingen fysiske TV-/mobilklienter eller reell YouTube-avspilling ble testet her.

## Opprydding

Begge testene slettet syntetiske brukere, biblioteker og videofiler og fjernet testpluginen og dens tilgangsregistre. Uavhengig readback etter siste kjøring er lagret i `bin/native-root-recreation-cleanup.json`. Standardoppryddingen målte `ServerStopped` umiddelbart ved prosessavslutning; den separate sluttkontrollen bekrefter faktisk fravær av EmbyServer-prosessen.
