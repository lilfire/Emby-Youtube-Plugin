# B – Sync/offline, strømreferanser, varsler og DLNA

Undersøkt 2026-10-14 på isolert **Windows Emby Server 4.10.1.0**, plugin
**2.0.10-alpha.1**, commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`.
Produksjons-DLL SHA-256:
`AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
Fixture-DLL SHA-256:
`F890627BFB0BD1438536C7C4EF2D79A75CDFB5B195228C30F19D143C22EFD0FD`.

**Konklusjon:** produksjonsintegrasjonen har påviste tilgangshull i Sync,
LiveStreams og kontrollert WebSocket-utlevering. B er ikke godkjent som
full skjerming. Mappe-GUID-avviket er reprodusert i den tidligere prototypen.
DLNA og fungerende live-transport mangler positive kontroller og godkjennes
ikke. Ingen produksjonsmodul, Lilflix-installasjon eller fysisk klient er endret.

## Testinngang og kildeavgrensning

[Run-B.ps1](Run-B.ps1) bruker den eksisterende produksjonsfixturens probeinngang
`PERSONAL_YOUTUBE_A_PROBE`; navnet er historisk. Selve B-proben og nye rapporter
ligger bare i B. Fixturen installerer dagens produksjonskontroller, registrerer
to syntetiske native Movie-røtter i `PersonalYouTubeNativeBindings` og setter
to vanlige kontoer til `EnableAllFolders=true`, med readback. Den eksperimentelle
privacy-guarden er deaktivert under hele produksjonsmatrisen, også etter omstart.

HTTP går til ekte Emby-ruter på den reserverte isolerte porten 18096.
Profilslettingen er produksjonens `POST YouTubePlugin/MyProfile/Delete`, med
tilbakelest Deleted-status. Native røtter/kildefiler beholdes for å prøve gamle
referanser; dette er ikke samme hendelse som native biblioteksletting.
Omstart er faktisk prosessomstart med ny fixture-BootId og kontroll av installerte
produksjonskroker. Privatmatrisen binder begge røtter; offentligmatrisen lar A
være vanlig ubundet native innhold mens B er privat.

Dette er produksjonskontroller rundt syntetiske native kilder, ikke hele kjeden
Google → yt-dlp → buffer → personlig publisering. Ingen Google, API-nøkler eller
ekte privat innhold brukes. Native Sync klargjør reelle Original- og konverterte
jobber. SupportsSync-klientene er syntetiske og er ikke fysiske nedlastingsapper.
Ingen funksjons-/lisenskontroll omgås; ReadyToTransfer og faktiske filer observeres.
Live-provideren er testadapteren `FixtureLiveSourceProvider`, ikke vanlig YouTube.

## Utførte prøver og funn

Begge produksjonsløp fullførte **213 observasjoner**, med henholdsvis **95 og
82 mislykkede boolske assertions**. Tallene inkluderer funksjons-/statusavvik
og manglende positive live-bytekontroller, og er ikke antall lekkasjer.
Seks DLNA-prober i hvert løp har null status for IsolationPass og telles ikke
som bestått eller mislykket skjermingsbevis. Fixturens konsolltall inkluderer
disse seks nullverdiene; [SUMMARY.json](SUMMARY.json) teller bare faktisk false.

| Inngang | Positiv kontroll | Negativ kontroll / resultat |
|---|---|---|
| Sync job / jobitem | Egen jobb og egne elementer med riktig privat videotittel | Andre kontoer kan lese privat jobb-/elementmetadata. |
| Sync Original-fil | Eier får 200, 11 071 bytes og kjent SHA-256 | Fremmed konto får samme komplette fil, også etter profilsletting og omstart. |
| Sync konvertert fil | Native ReadyToTransfer, ffprobe: MPEG-4, seks sekunder, 12 405 bytes; eierens respons har riktig utdatahash | Fremmed konto får komplette utdata før/etter profilsletting og etter omstart. A og B sine konverterte filer har forskjellige SHA-256. |
| Sync Ready / TargetId | Eier får eget privat navn for eget syntetisk mål | Fremmed konto kan hente Ready-data med kjent mål; TargetId gir ikke tilstrekkelig eierskapsgrense. |
| Sync oppretting | Fire egne native jobber, to profiler per eier | Begge kontoer får 200 og en faktisk ny jobb med fremmed kilde og manipulert UserId. Jobbene registreres i cleanup-journalen. |
| LiveStreams/Open | Egen faktisk native strøm med privat navn | Fremmed konto får 200 med eierens ItemId, OpenToken og UserId. Gamle A-tokens virker også etter profilsletting før omstart. |
| LiveStreams/MediaInfo | Eier får 200 med egen privat metadata | Fremmed konto får samme private navn/metadata før og etter profilsletting. |
| LiveStreams/Close | Eierens strøm har fungerende MediaInfo før fremmed Close | Fremmed konto får 204 ved kjent LiveStreamId/PlaySessionId; eierens etterfølgende MediaInfo blir 204 uten metadata. Påvist påvirkning av legitim strøm. |
| Live-referanse + statisk video | Egen native MediaInfo virker | Egen byteforespørsel gir 404; ingen fungerende positiv live-transport. Fremmed 404 er derfor ikke byte-skjermingsbevis. Dette går til D for kildekontrakten. |
| WebSocket LibraryChanged | Begge mottakere får en hel melding med unik kontrollstamp og egen video-ID | Begge får også den andre eierens private video-ID. Ekte SendMessageToUserSessions og native WebSocket-utlevering; kontrollert meldingsprodusent. |
| DLNA SOAP BrowseMetadata | Forsøkt eier, fremmed og anonym, begge videoreferanser | Alle seks gir 404 uten BrowseResponse. Ingen eierkontroll, derfor uverifisert; rutedeklarasjon er ikke fungerende DLNA. |

Anonyme Sync-filprøver gir 401 uten samsvar med private utdata. At autentisering
virker for anonym klient løser ikke tilgangen for en autentisert fremmed konto.
Begge Original-prøvevideoene bruker samme syntetiske byteinnhold; Original-hash
beviser filintegritet, men skiller ikke innholdets eier alene. Native jobb-/kilde-ID
og private navn gir kildekontekst. Konverterte A/B-utdata har ulike hasher.

Etter restart gir de gamle native LiveStreamId-ene 204 uten privat metadata og
gamle OpenToken-prøver 500 uten privat markør. Dette er ingen observert byte-
eller metadatalekkasje ved akkurat disse svarene, men heller ikke det forventede
rene avslaget. Nye strømmer, andre providers og transkodet transport trenger
separate prøver. Tidligere private strømmer overlever ikke denne prosessomstarten.

## Mappe-GUID-kollisjon: separat prototypereproduksjon

[Run-Collision.ps1](Run-Collision.ps1) kjører eksisterende native recreationskript
med ny og gjenbrukt fysisk mappe. Her er **eksperimentell PrivacyGuard aktiv**;
disse resultatene skal ikke tilskrives produksjonspluginen.

Begge løp fullførte 37 observasjoner med faktisk omstart. Ny mappe: null avvik.
Gjenbrukt mappe: fire metadataavslag for B sin nye video, to referanseformer
før/etter omstart. Ny rot-/video-ID og rot-GUID ble observert i begge løp.
Bare gjenbrukt fysisk mappe fikk **samme foreldremappe-GUID** som tidligere A.
Foreldremappen var kjent privat og satt i karantene; native IsVisible(B) og
IsVisibleStandalone(B) var sanne. B fikk fortsatt korrekt PlaybackInfo og
hele sin nye fil; A/anonym fikk ikke den filen. B sitt opprinnelige innhold virket.

Dette avgrenser funksjonsfeilen til historisk foreldremappeidentitet i prototypen,
ikke til manglende native biblioteksrettigheter. Koblingen fra karantene til det
enkelte DTO-avslaget er fortsatt en slutning fra readback og filterkode, ikke
instrumentert kontrollflyt. E må beholde konfliktavslag og bruke en ny fysisk
mappe per samling/generasjon; ikke overføre gamle GUID-bindinger til ny eier.
Produksjonsintegrasjon og Sync ved identitetsgjenbruk er fortsatt åpne.

## Fysiske filer og forslag til varig modell

I begge nye produksjonsløp var den konverterte A-filen tilgjengelig etter
profilsletting og omstart. Deretter ble den konkrete Sync-jobben slettet nativt:
DELETE ga 204, GET ga 204 uten jobb, og utdatafilen var borte. Dette motsier ikke
de eldre orphan-funnene: de prøvde native **rotsletting under klargjøring**, mens
denne prøven sletter en **ferdig jobb**. Fysisk fjerning er avhengig av hendelse/fase.
Den overlevende B-utdatafilen etter fixture-cleanup ble fjernet ved eksakt bane,
validert under isolert data/sync og med uendret hash. Ingen rekursiv sletting.

Forslag til koordinator/E/F/G: en varig ledger for hver avledet fil, bundet til
OwnerUserId, CollectionId, GenerationId, source-ID, job-/jobitem-ID, mål, profil,
kanonisk utdatafil og innholdsproveniens. Registrer hensikt før konvertering og
atomisk ferdigstillelse etter verifisert output. Bevar tombstone etter profil-/
kontosletting. Revalidér generasjon ved klargjøring, Ready-registrering og hver
utlevering. Ledgeren må virke uten native GetJob/GetJobItem. Opprydding må nekte
reparse points/symlinks og uventet filutskiftning, håndtere restart og bevare B.
Dette er et implementeringsforslag; modellen er ikke implementert eller bevist.

Forslag til koordinator/A/D: egne hashverifiserte native kontrakter for alle Sync-
DTO-er og deres faktiske factory-/skriverkjeder; bind mål/avledede referanser til
autentisert eier og aktiv generasjon før metadata, sideantall, mutasjoner og bytes.
OpenToken må bindes til kilde og eier før provider-kall, og LiveStreamId må bindes
til eier/generasjon/consumer for MediaInfo, Close og transport. HTTP-status og
etterfiltrering erstatter ikke kilde-/skriverbinding.

Forslag til koordinator: varsler må filtreres per mottaker før serialisering,
inkludert bibliotek-ID-er, status og telling. Meldinger med bare bortfiltrerte
private endringer må ikke avsløre aktivitet gjennom tomme hendelser. DLNA og
andre innganger uten entydig bruker må avvise private samlinger inntil en
verifisert identitets-/ressursmodell finnes. Dette er nødvendig støttepolicy,
ikke en sperre som dagens produksjonskode allerede håndhever.

## Rutekart, regenerering og opprydding

[ROUTES.csv](ROUTES.csv) har 73 deklarerte Sync-/LiveStreams-/DLNA-/Sessions-ruter,
med DTO, deklarerte identitetsfelt, handler og IL-hash fra serverens innlastede
inventar. LiveStreamId/OpenToken er separate beholdte referanser selv om A sitt
feltinventar ikke klassifiserer dem som UserId/ItemId. Inventaret er ikke bevis
for transitive native kjeder, alle runtime-aliaser eller fungerende DLNA.

Portable evidens: [privat](PRIVATE-EVIDENCE.json), [offentlig](PUBLIC-EVIDENCE.json)
og [GUID-reproduksjon](COLLISION-EVIDENCE.json). Kun sanitert evidens eksporteres;
rå inventar, maskinstier og fixture-journal ligger i ignorert bin. Avbrutte
utviklingskjøringer inngår ikke i tallene.

```powershell
dotnet build verification/PersonalChannels/PersonalChannels.csproj -c Release --no-restore
powershell -NoProfile -File verification/FollowUp/B/Run-B.ps1
powershell -NoProfile -File verification/FollowUp/B/Run-B.ps1 -PublicSource
powershell -NoProfile -File verification/FollowUp/B/Run-Collision.ps1
python verification/FollowUp/B/Build-Evidence.py
```

Bygg bestod uten advarsler/feil. Alle fire endelige løp har readback av slettede
testbrukere, biblioteker, mediefiler, fixture og guard. Produksjonsløpene fjernet
personlige profiler/bindinger og sine registrerte Sync-jobber/utdata. Separate
etterkontroller bekrefter ServerStopped=true. Det tidlige native cleanup-feltet
ServerStopped=false beholdes som historisk prosessavslutning, ikke sluttstatus.

Nye filer er bare B sine tester, rapport og portable evidens, pluss koordinatorens
oppdatering av TODO. Eksisterende lokale endringer i PersonalChannels og A er
gjenbrukt som testgrunnlag, ikke endret som del av B. Ingen commit, utrulling eller
endring av hovedserveren.

## Gjenstående støttebegrensninger

B sitt samlede ferdigkrav er ikke oppfylt. Cloud-/folder-sync, faktiske offline-
klienter, flere konverteringsprofiler, sletting under ffmpeg, kansellering,
prosesseavbrudd og kontosletting er ikke prøvd i produksjonsmatrisen. Historiske
Ready-skrivepunkt-racer er prototypetest, ikke disse nye produksjonsbevisene.
Naturlige bibliotek-/jobbvarsler, Sessions-meldinger, fjernstyring og DLNA med
gyldig discovery/positiv SOAP-/ressurskontroll gjenstår. Lokalt allerede nedlastede
kopier uten serverkontakt er utenfor serverens utleveringsgaranti.
