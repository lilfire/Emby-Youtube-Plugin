# Personlig YouTube — 2.0.11-alpha.1

Dette er versjonen for lukket alfa. Bruk kontrollerte prøvekanaler og
prøvebrukere. Se KNOWN-LIMITS.md for den konkrete verifiseringsomfanget.

## Krav og installasjon

1. Bruk Emby Server 4.10.1.0. De inspiserte tilgangskontrollene er knyttet til
   denne serverimplementeringen. En annen versjon kan hindre arbeideren i å starte.
2. Ta sikkerhetskopi av Emby-konfigurasjonen og den installerte
   `Emby.YouTubePlugin.dll`. Stopp Emby før DLL-en erstattes.
3. Pakk ut kandidaten, kontroller filene mot `manifest.json`, og kopier
   `Emby.YouTubePlugin.dll` og `thumb.png` til serverens `plugins`-mappe.
   DLL-en inneholder Harmony; SDK-DLL-er skal ikke kopieres inn.
4. Installer yt-dlp, Node.js 24 LTS og FFmpeg/ffprobe på serveren. De leveres
   ikke i pluginpakken. Bruk offisielle utgivelser og kontroller SHA256.
   Kjør `yt-dlp --version`, `node --version` og `ffmpeg -version` i det
   aktuelle servermiljøet; en eksisterende fil er ikke bevis på at den virker.
5. Start Emby. Åpne administratorens YouTube-innstillinger, fyll ut de tre
   absolutte verktøystiene og aktiver «Personal YouTube — closed alpha».
   Begynn med få videoer og små størrelsesgrenser. Start Emby på nytt.
6. Kontroller administratorstatus via `GET /YouTubePlugin/PersonalServerStatus`
   med vanlig Emby-autentisering: Creation, References og Lists skal ha
   Installed=true, og WorkerRunning skal være true. Ingen nøkler inngår i svaret.

## Docker

Stiene må være synlige **inne i containeren**, for eksempel
`/config/personal-tools/yt-dlp`, `/config/personal-tools/node` og
`/config/personal-tools/ffmpeg`. Behold verktøyene i en vedvarende montering,
så de overlever at containeren opprettes på nytt. FFprobe skal ligge ved FFmpeg.

Bufferprosessen fjerner Embys arvede LD_LIBRARY_PATH/LD_PRELOAD ved oppstart
av eksterne Linux-verktøy. Den endrer ikke serverprosessens eget miljø.
Verktøy som trenger andre biblioteksstier kan startes gjennom en administrator-
styrt wrapper som setter sitt eget miljø.

Pluginens personlige data lagres under Emby DataPath i `youtube-personal`.
Ta også vare på hele `youtube-personal` ved oppdatering. Rotregisteret
`private-source-scopes.json` og `private-source-scopes.required` må kopieres
sammen med journal og bindinger mens serveren er stoppet. Ikke bland filer
fra ulike sikkerhetskopier.

Serverbudsjettet omfatter personlige medier og staging, med logisk budsjett
til begge kopier under publisering. Det reserverer ikke fysisk diskplass
og erstatter ikke operativsystemets
diskkvote; behold ledig plass til Emby og andre medier. Arbeidet serialiseres
mellom brukere. Deaktivering stopper jobbstart etter omstart; eksisterende
samlinger slettes gjennom brukerens innstillinger.

## Test som vanlig bruker

1. Åpne YouTube fra brukermenyen i Emby-webklienten.
2. Legg inn egen YouTube Data API v3-nøkkel og kanal-ID-er som begynner med UC.
3. Velg «Lagre og oppdater». Vent til statusen viser at biblioteket er klart.
4. Åpne «YouTube» som et vanlig bibliotek og spill av en video.
5. Bytt til en annen testkonto og kontroller at samlingen ikke vises der.
6. Endre kanalvalg og oppdater. Den tidligere samlingen erstattes.
7. Velg «Slett samlingen» og bekreft. Vent til jobben viser Deleted før
   administratoren bekrefter at biblioteket og de bufrede mediene er fjernet.

Nøkkelen vises ikke igjen. Et tomt nøkkelfelt beholder den lagrede nøkkelen.
YouTube-kvoten deles på Google-prosjektnivå; flere brukeres nøkler fra samme
prosjekt gir ikke uavhengige budsjetter. Oppbrukt kvote gir en forklarende feil.
Nøkkelen brukes til katalogdata. Videostrømmen skaffes av yt-dlp og buffers
lokalt før native Emby-publisering. Innloggingskrevende eller utilgjengelige
videoer kan feile; pluginen bruker ikke nettlesercookies.

## Tilbakeføring

Før en eldre plugin installeres eller alfa-DLL-en fjernes, slett alle
personlige samlinger gjennom testbrukernes YouTube-side og vent på Deleted.
Kontroller native biblioteksoversikt og mediemapper. En eldre DLL kan mangle
tilgangskontrollene for biblioteker som alfaen opprettet.

Deleted alene beviser ikke full opprydding. De senere undersøkelsene har
påvist restdata og gamle avledede referanser i Sync/live/cache og etter
kontosletting. Ta med slettede kontoers samlinger og disse datakildene i
kontrollen; behold alfaen hvis dette ikke kan avklares. Se
[J sin installasjons-/tilbakeføringsplan](../../FollowUp/J/INSTALLATION-PLAN.md).
En komplett native tilbakeføring er fortsatt uverifisert.

Stopp Emby, gjenopprett tidligere DLL og konfigurasjon, og start Emby igjen.
Behold sikkerhetskopien av `youtube-personal` og dens eierhistorikk til du
har kontrollert tilbakeføringen. Ikke slett vilkårlige mediemapper eller
andre brukeres biblioteker manuelt. Ved mislykket opprydding: behold alfaen
og undersøk jobbstatusen før tilbakeføring.

Verktøykilder: [yt-dlp](https://github.com/yt-dlp/yt-dlp),
[Node.js](https://nodejs.org/en/download),
[FFmpeg-bygg brukt i Docker-testen](https://github.com/yt-dlp/FFmpeg-Builds).
