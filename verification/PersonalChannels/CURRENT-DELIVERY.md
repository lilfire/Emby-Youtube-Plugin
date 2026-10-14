# Leveransestatus: personlig YouTube

Oppdatering 2026-10-14: Alfaen er nå også installert og aktivert på Lilflix etter
uttrykkelig brukerbestilling. Oppstart, DLL-hash, verktøy, alle tilgangskontroller
og innstillingsavlesning bestod. Se [utrullingsrapporten](LILFLIX-ALPHA-DEPLOYMENT.md).
Formuleringene nedenfor om ingen utrulling beskriver statusen før dette.

2026-10-14: **Lukket alfa 2.0.10-alpha.1 er ferdig og klar for kontrollert test.** Full skjerming er fortsatt ikke bevist. Ingen utrulling til hovedserveren eller offentlig utgivelse er utført.

Gjeldende pakke: [2.0.10-alpha.1](bin/packages/2.0.10-alpha.1-20261014T102002670.zip). Manifeststatus er `closed-alpha-ready`; DLL SHA256 er `2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC`.

Stue-TV med Emby AndroidTv 1.8.54g viste video, fremdrift og aktiv lydutgang etter retting av original.mp4-ruten. Samme siste DLL bestod ekte Google/to kanaler, egne/fremmede native strømmer, omstart, Buffering-avbrudd/gjenoppretting og sletting i Docker. Chrome-flyten og administratorlagringen bestod. Android mobil og øvrige klienter er uverifisert.

Godkjenningskontrollen er fullført i [CLOSED-ALPHA-ACCEPTANCE.md](CLOSED-ALPHA-ACCEPTANCE.md). TV/nettverk er tilbakeført, Windows-fixturen ryddet/stoppet og Docker-testprofilen slettet/testcontaineren stoppet. Hovedserverens plugin og konfigurasjon er uendret.

## Tidligere status og undersøkelser (historisk)

Avsnittene nedenfor beskriver tidligere trinn; de er ikke gjeldende leveransestatus.

Gjeldende status: kandidat 2.0.10-alpha.1 er pakket med rettet
administratorlagring. Chrome-avspilling, kanalbytte, profilsletting og
kvotefeilmelding er prøvd. Dagens DLL bestod ekte Google, to kanaler, native
strømmer, omstart, sletting og faktisk Buffering-avbrudd med gjenoppretting
i Docker. Android/Android TV-avspilling og siste godkjenningsaudit avventes.
Se CLOSED-ALPHA.md, BROWSER-ALPHA-RESULT.md og DOCKER-ALPHA-*-RESULT.json.
Eldre statusavsnitt nedenfor beskriver historikken.

Aktivt mål er nå **lukket alfa**, etter at brukeren avsluttet målet om bevis
for full skjerming. Se [CLOSED-ALPHA.md](CLOSED-ALPHA.md) for konkrete krav og
aktuell status. Lagring er nå koblet til en produksjonsjobb når alfaen er
aktivert; omtalen av «bare testadapter» lenger ned er historisk. Den isolerte
HTTP-lagring → jobb → vanlig bibliotek → video-kjeden består med simulert
Google-transport og ekte YouTube-media. Kanalbytte med beholdt nøkkel, native
opprydding, sletting, faktisk omstart og et faktisk prosessavbrudd i Preparing
er nå testet på Windows. Administrator- og felles lagringsoppsett er lagt til.
Docker-testserveren har nå pluginen og fungerende verktøy. En vanlig bruker
lagret en ekte nøkkel og fikk to videoer i et native bibliotek uten adapter;
eierstrømmer ga 200, B ga 404 og så ikke roten. Ugyldig nøkkel tilbakekalte
gamle referanser og gir konkret feil. Gyldig nøkkel er satt tilbake, men har
nå brukt opp Google-kvoten. Positiv gjenoppretting med siste DLL, flere kanaler,
navn/metadata, faktisk klientflyt og utgivelsespakke gjenstår. Siste status og
avgrensninger står i CLOSED-ALPHA.md; ingen testutgivelse er klar ennå.

## Bibliotekoversikten: siste retting

Produksjonskontroll alene avdekket at `Library/VirtualFolders/Query` viste
A sitt private bibliotek til B. `PersonalYouTubeItemListGate` filtrerer nå
den native biblioteklisten før antall og paginering, for både denne ruten og
`Library/VirtualFolders`. Filtreringen bruker den autentiserte kontoen;
administratorens bibliotekadministrasjon beholder sin oversikt. Dette
forutsetter at serveradministratoren er betrodd.

Den samlede testen uten opprettelsespausen bestod med 43 observasjoner:
ekte mediebuffer, publisering, omstart, egne/fremmede kontoer, manipulert
UserId, direkte bibliotek-ID, antall, paginering og profilsletting. Google
Data API-responsene var simulerte. Den eksperimentelle tilgangskontrollen
ble deaktivert ved oppstart av testen. Ingen klientapp er testet her.

Opprettelsesvinduet er nå kontrollert med parallelle forespørsler: den
samlede kjøringen bestod med 52 observasjoner og faktisk omstart. Opprettelse
holder A sin overføringslås; A sin listeforespørsel var fortsatt uferdig mens
roten var pauset. B sin liste og begge kontoners direkte metadataforespørsler
ble kontrollert mens pausen fortsatt var aktiv. Etter frigjøring fikk A en
200-liste uten Preparing-roten. Dette tester svarets innhold, ikke hver byte
eller header mens A ventet. Testkontrollens tilgangsfiltrering var deaktivert
både før opprettelse og etter omstart.

Den gamle sekvensielle testen ventet på A sin lås og brukte dermed opp
opprettelsespausen. Det mislykkede forsøket er bevart i
`bin/inflight-library-filter-failure.json`; det erstattes ikke med et økt
tidsavbrudd. Tidligere mislykkede kandidater inkluderte rekursiv
oversiktsfiltrering og konflikt med testkontrollen. Evidens for den samlede
kjøringen: `bin/evidence/20261013T192428659-creation-lease-discovery`.
Full skjerming og automatisk livssyklus gjenstår fortsatt.

## Direkte oppdatering av avspillingsdata

En ny kontroll fant at `POST /Users/{UserId}/Items/{ItemId}/UserData`
aksepterte B sitt kall mot A sin private video. Produksjonskontrollen
inneholdt ikke denne DTO-en. `PersonalYouTubeServiceReferenceGate` dekker
nå `UpdateUserData` sitt faktiske `ItemId`, med kontroll av den native
PlaystateService.Post-metodens signatur og IL-hash. Denne metoden løser
ItemId, henter brukerdata og lagrer endringene; DTO-feltet Key brukes ikke
som alternativ kilde i den inspiserte metoden. Eksisterende kontroll av
autentisert konto, UserId, profil og overføringslås gjelder denne inngangen.

Den samlede produksjonstesten bestod med 57 observasjoner: A sitt positive
kall gir 204 og forventet Played, PlayCount og PlaybackPositionTicks i
native brukerdata. B, B som hevder A, A som hevder B og en slettet profil
får 404. Begge kontoners native tilstand forblir uendret ved avvisning.
Dataene ble lest på nytt etter en faktisk serveromstart og var fortsatt
riktige. Testen inkluderer den parallelle opprettelsespausen, ekte buffer
og publisering; Google-katalogtransporten er simulert. Rapport:
`bin/production-user-data-probe-results.json`.

Referansekontrollen omfatter nå 18 konkrete DTO-er og listekontrollen 10.
Regresjonen for Views/Latest bestod med 26 observasjoner og null
isolasjonsfeil. Profil-/katalogkomponentkontrollene bestod med 197.
Dette er avgrenset evidens for disse inngangene, ikke en universell garanti.

## Neste godkjenningspunkt

A lagrer egen nøkkel og kanal, får virkelige YouTube-videoer i et vanlig
Emby-bibliotek og spiller av. B kan ikke oppdage eller hente A sitt innhold,
heller ikke ved direkte referanser. Dette ene godkjenningspunktet er en milepæl,
ikke en erstatning for hele kravet om alle klienter og full skjerming.

## Faktisk implementert

- Personlig innstillingsside og autentisert lagring av nøkkel og kanalvalg.
- Native opprettelseskontekst, varige eierbindinger og tilgangskontroller for
  dokumenterte deler av Emby. Tidligere isolerte tester gjelder sine oppgitte
  versjoner og ruter, ikke automatisk den samlede løsningen.
- `PersonalYouTubeCatalog` henter en videoside fra en lagret kanal med profilen
  sin egen nøkkel. Resultatet bærer eier, samling, generasjon og revisjoner.
  Den bruker ingen globale YouTube-innstillinger eller delte svarmellomlagre.
  Sletting/endring før, mellom eller etter API-kall avviser resultatet.
  En nøkkel eller kanalliste som er byttet ut i et kopiert snapshot avvises.
- `PersonalYouTubeNativePublisher.CreatePreparingLibrary` oppretter et ekte
  native Emby-bibliotek gjennom den verifiserte produksjonskroken og binder
  roten før metoden returnerer. Journalen beholder Preparing: medlemmene og
  videobuffringen må være klare før aktivering. Den isolerte adapteren bruker
  nå denne produksjonsmetoden, ikke sin tidligere kopi av opprettingskoden.
- Brukeren har godkjent lokal videobuffer. En ekte offentlig YouTube-prøvevideo
  er hentet og slått sammen til H.264/AAC MP4. Native serverutlevering av denne
  filen er verifisert med egne/fremmede brukere, sletting og omstart.
- `PersonalYouTubeVideoBuffer` er nå produksjonskomponenten for selve
  medienedlastingen. Den kontrollerer katalogens eier, generasjon, revisjoner,
  kanal og video-ID, og skriver i en unik jobbmappe under den samme eieren.
  Den starter servervalgte yt-dlp/ffmpeg/Node med strukturerte argumenter,
  uten globale konfigurasjonsfiler, nettlesercookies eller API-nøkler.
  Tids-/størrelsesgrense, profilsletting og avbrudd stopper jobben og rydder
  dens staging. Vellykkede filer beholdes som interne, upubliserte resultater.

## Koblinger som mangler

Oppdatert 2026-10-13: den samlede første publiseringstesten bestod nå med
44 observasjoner og prosesskode 0. Den faktiske produksjonskjeden
`PersonalYouTubeInitialRefresh` → katalog → buffer → native publiserer
ble kalt av den isolerte administratoradapteren. Profilen hadde en syntetisk
personlig nøkkel; katalogtransporten var simulert og kontrollerte at riktig
lagret nøkkel og kanal ble brukt. Selve YouTube-medienedlastingen,
indekseringen, eierbindingen og videoutleveringen var virkelige.

Bibliotekstypen er eksplisitt `homevideos`. Virtuell og fysisk mappestruktur
etableres i en avgrenset native indekseringskjede før medlemsbinding og
aktivering. Tidligere feil med tom indeks og doble filmidentiteter beskriver
utviklingsforsøk; de siste to samlede kjøringene bestod. Ingen universell
produksjonsgrense eller ferdig klientkompatibilitet påstås av dette.

Testadapteren bruker Emby sin allerede innlastede produksjonsassembly.
Den tidligere minnefeilen i rapportskriving er fortsatt registrert som et
mislykket forsøk; finally-oppryddingen er styrket. Den siste oppryddingen
bekrefter at brukere, biblioteker og prøvemedier er borte. Separat sluttkontroll
viser null prosesser for testserverens eksakte binær, ingen PID-fil og fravær
av profilmappe, fixture-DLL og fixture-journal. Se
`bin/buffered-publication-final-cleanup.json`.

1. Koble første oppdateringsjobb til profilendring og omstart. Katalogen har
   nå en produksjonskaller i `PersonalYouTubeInitialRefresh`, men jobben er
   foreløpig bare kalt av testadapteren. Virkelig Google Data API-henting med
   en personlig nøkkel gjenstår. Den eksisterende felleskanalen bruker fortsatt
   global nøkkel.
2. Implementer oppdatering av en allerede aktiv samling, trygg sletting,
   gjenoppretting og vedvarende jobbstatus. Den første publiseringen validerer
   profilen og binder medlemmer før synlighet, men er ikke en full livssyklus.
3. Implementer verktøyhåndtering, samlet serverdiskbudsjett og faktisk
   appavspilling. Første jobbs videobudsjett og totale bytebudsjett er eksplisitte;
   vellykkede stagingfiler ryddes etter publisering og ved senere jobbfeil.
   Private dynamiske videokilder er foreløpig avvist. Den nye ekte
   YouTube-prøvevideoen beviser en bufferet kilde gjennom serverruten, men
   ikke en komplett personlig oppdateringsjobb eller faktisk TV-app.
4. Verifiser den samlede servertilgangen og klientkjeden, inklusive øvrige
   ruter, mutasjoner, synkronisering og relevante revokeringshendelser.

## Verifisering av den nye hentekomponenten

`dotnet run --project verification/PersonalYouTubeStore/PersonalYouTubeVerification.csproj -c Release --no-restore`
bestod 2026-10-13, med 197 kontroller totalt. Ni gjelder kataloghenting.
HTTP-transporten var simulert: dette viser personlig nøkkel-/kanalvalg,
feilhåndtering og invalidasjon, ikke ekte Google-tilgang eller klientavspilling.
Resultatet er `verification/PersonalYouTubeStore/bin/results.json`.
Ingen API-nøkler fra hovedserveren eller ekte Google-kall ble brukt.

## Native publisering og ekte YouTube-buffer

Den ovenstående setningen gjelder katalogkomponentens simulerte test.
Deretter ble en virkelig prøvevideo hentet fra YouTube med kontrollsumverifisert
offisiell yt-dlp 2026.08.19 og Emby sin ffmpeg. Prøvevideo-ID: DTi8wZ1a1TA.
Format 134+140 ble slått sammen; ffprobe viser H.264, AAC, 640x360,
9,939 sekunder og 237886 byte. SHA256:
`104BADBFDAE1F8F6089DB3F9BDDFFD3EA3192CD323E77F1D22CB6192B43B7AA0`.
Dette bruker ikke Data API-nøkkelen til selve medienedlastingen.

`Test-NewUnregisteredPrivateRoot.ps1 -InFlight -ReserveIdentity -CreationContext`
bestod med 37 observasjoner og faktisk omstart. Testen sjekker riktig binding
og avslag mens biblioteket er Preparing. Aktivering i denne testen gjøres
fortsatt eksplisitt gjennom den isolerte adapteren.

`Test-ProductionVideoStreams.ps1 -RequireIsolation -BufferedYouTube` bestod
med 66 observasjoner. A sin kilde er den ekte bufferede videoen, B sin kilde
er fortsatt en syntetisk kontroll. Faktisk videoutlevering sjekkes med
filhash, HEAD, byteområde og ETag, med fremmede referanser og profiler som
slettes. Testen bruker eksisterende produksjonskontroller, ikke fixture-
tilgangskontrollen. Det er en servertest, ikke en gjennomført appavspilling.

Den første native kjøringen avdekket en låsing fordi publisereren holdt
profillagerets monitor over native callbacks. Den er rettet til å bruke
eierlåsen mot Save/Delete uten å blokkere profilavlesning. Den etterfølgende
kjøringen bestod. En mellomliggende test forventet en ubundet rot; denne
forutsetningen er oppdatert til å sjekke den nye produksjonsbindingen.

Verktøyet er foreløpig bare installert i den isolerte testmappen. Distribusjon
og kjøring i Linux/Docker er ikke implementert eller verifisert.

Uforanderlige kopier av de to rapportene, testvideoen, probe-resultatet,
binærene og de utførte kildene ligger i
`bin/evidence/20261013T160300953-buffered-youtube/`. Kontrollsummer er lest
tilbake. Begge testprosessene avsluttet med kode 0 etter fixture-opprydding.
Serveren er stoppet; profilmappe, fixture-DLL, PID-fil og fixture-journal er
fraværende. Ingen separat ny avlesning av native bruker-/bibliotektilstand
etter avslutningen påstås av dette manifestet.

## Produksjonskomponenten for buffring

`dotnet run --project verification/PersonalYouTubeStore/PersonalYouTubeVerification.csproj -c Release --no-restore -- --buffer-youtube`
bestod med 207 kontroller. Ti gjelder den nye bufferkomponenten. Den faktiske
produksjonsklassen henter den offentlige prøvevideoen med lyd og bilde og
stanser både en startet avbrutt jobb og en startet jobb ved profilsletting.
Midlertidige jobbfiler er ryddet, og B sin profil/nøkkel beholdes. Hele
verifiseringsmappen slettes av testens avslutning; `TestDataGone` er sant.

Kataloginput for denne testen er kontrollert testdata, ikke en ekte Google
Data API-respons. Komponenten har ennå ingen produksjonsjobb som kaller den.
Hvert ferdig bufferresultat må kontrolleres mot profilen igjen ved native
publisering. Størrelsesgrensen gjelder en jobb; samlet serverdiskkvote er
ikke implementert. Plattformkontrollen gjelder Windows, ikke Linux/Docker.
Kilde, binærer og resultat er kopiert og kontrollsumverifisert i
`bin/evidence/20261013T160936138-production-video-buffer/`.

Den sammenkoblede første jobben, publisereren og de to siste testresultatene
er bevart i `bin/evidence/20261013T164847684-initial-refresh/` sammen med
utførte kilder og binærer. Kopihasher er lest tilbake, og den installerte
isolerte produksjonsbinæren matcher bygget. Arkivet gjelder det oppgitte
simulerte Data API-et og den virkelige media-/publiseringskjeden; det er
fortsatt ikke bevis for full skjerming.

API-strukturen følger Googles dokumentasjon:
https://developers.google.com/youtube/v3/sample_requests
og https://developers.google.com/youtube/v3/docs/playlistItems.
