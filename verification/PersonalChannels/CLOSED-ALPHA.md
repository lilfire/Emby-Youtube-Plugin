# Lukket alfa

Status 2026-10-14: **2.0.10-alpha.1 er klar for lukket test i dokumentert omfang.** Godkjenningskontrollen er fullført. Ikke installert på hovedserveren; ingen offentlig utgivelse er utført.

Gjeldende pakke: [2.0.10-alpha.1](bin/packages/2.0.10-alpha.1-20261014T102002670.zip), manifeststatus `closed-alpha-ready`. DLL SHA256: `2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC`.

Stue-TV med Emby AndroidTv 1.8.54g viste faktisk video, fremdrift og aktiv stereo-lydutgang. Fysisk lyd er ikke hørt med mikrofon. En 404-feil for original.mp4 ble rettet og verifisert med sju HTTP-kontroller og faktisk TV-avspilling. Samme siste DLL bestod ekte Google/to kanaler, egne/fremmede strømmer, omstart, Buffering-avbrudd/gjenoppretting og sletting i Docker.

TV/nettverk er tilbakeført, Windows-fixturen ryddet og stoppet, og Docker-testprofilen slettet/testcontaineren stoppet. Hovedserverens plugin og konfigurasjon er uendret. Se [godkjenningskontrollen](CLOSED-ALPHA-ACCEPTANCE.md), [TV-resultatet](ANDROIDTV-ALPHA-RESULT.md) og [siste Docker-rapport](DOCKER-ALPHA-RELEASE-RESULT.json). Android mobil og øvrige klienter er uverifisert; full skjerming er ikke bevist.

## Tidligere verifisering (historiske notater)

Avsnittene nedenfor beskriver tidligere trinn. Formuleringer om ventende app-test, kvoteblokkering og eldre pakker er historiske; statusen ovenfor og godkjenningskontrollen gjelder nå.

Chrome-flyten er nå prøvd med vanlig bruker: eget menyvalg, kanallagring,
native bibliotek med lesbar metadata, faktisk avspilling og kanalbytte med
beholdt nøkkel. Slettebekreftelsen og avbryt er prøvd. Katalogtransporten var
simulert; mediet var en ekte YouTube-prøvevideo. Se BROWSER-ALPHA-RESULT.md.
Android/Android TV-test er klargjort og venter på konkret avspillingsresultat.

Administratorprøven fant og rettet manglende lagring av de nye alfa-feltene
i SaveConfiguration-endepunktet. Alle åtte feltene er bekreftet ved avlesning
fra serveren etter endring i Chrome; prøveverdiene er satt tilbake.

Docker-fixturen har nå DLL SHA256
`2CFC5C19E0EC5475019ACBA081D2DE1573EB7B00011B8D89BD24FB31B77D585B`.
Den personlige nøkkelen ble beholdt ved en ny jobb etter kvotefeilen. Ekte
Google og to videoer ga Ready med lesbar rot/tittel, eierstrømmer 200/MP4 og
B-strømmer 404. Faktisk containeromstart beholdt samme rot/videoer og tilgang.
Profilsletting fjernet nøkkel/kanaler, native rot, gamle referanser og den
aktuelle generasjonens medie-/bufferkatalog. Rapport:
DOCKER-ALPHA-LIFECYCLE-RESULT.json. Dette er HTTP-bevis, ikke appavspilling.

Versjon 2.0.10-alpha.1 har lokal ZIP-kandidat med installasjons- og
tilbakerullingsinstruks og verifiserte pakkehashverdier. Den er fortsatt merket
candidate-not-approved. Den oppdaterte ZIP-en inkluderer lagringsrettelsen.
Flere kanaler er nå prøvd med ekte Google: én video fra
hver kanal, korrekt native tittel, eierstrøm 200 og B 404. Et faktisk KILL
mens den varige jobbstatusen var Buffering ble automatisk gjenopprettet til
Ready med ett bibliotek og uten gamle referanser. Rapport:
DOCKER-ALPHA-MULTI-RECOVERY-RESULT.json. Avbrutt Preparing er verifisert på
Windows; Linux-avbruddet gjelder Buffering. Chrome viste konkret kvotefeil,
valideringsfeil for ugyldig kanal og faktisk profilsletting med bekreftelse.
Øvrige feilkoder er ikke individuelt prøvd i nettleseren. Administratorens
disponibelkonto er fjernet, mens prøvebiblioteket for Android er beholdt.
Oppdatert pakke: bin/packages/2.0.10-alpha.1-20261014T072544974.zip.
Pakken inneholder DLL-en med lagringsrettelsen og verifiserte filhashverdier.
Den faktiske apptesten og siste godkjenningsaudit gjenstår.

Detaljene nedenfor beskriver tidligere testtrinn; denne delen er gjeldende
status der eldre formuleringer sier at nettleser, metadata eller pakke mangler.

Milepælen er en installérbar alfa der en vanlig bruker lagrer egen nøkkel og
kanaler, får et vanlig Emby-bibliotek og kan spille av prøveinnhold uten
testadapteren. Den tidligere garantien om full skjerming er ikke en påstand
denne alfaen kan gi. Den skal testes med kontrollert prøveinnhold.

## Utført

- `PersonalYouTubeJobs` køer én jobb per eier, avbryter foreldede jobber og
  lagrer status uten nøkler, kanaler, nettadresser eller rå providerfeil.
- Lagring/sletting via de autentiserte profilrutene varsler jobben.
  `/YouTubePlugin/MyJob` viser bare faktisk innlogget konto sin status.
- `PersonalYouTubeJobRuntime` kobler katalog, ekte buffer og native publiserer.
  Oppstart krever at alfaen er aktivert og kontrollkrokene er installert.
  Verktøyfilene må finnes, og kontrollkrokene kontrolleres igjen før en jobb.
- Et avgrenset utvalg fra hver kanal velges før buffering. Store kanaler
  krever dermed ikke at hele opplastingshistorikken lastes ned.
- Eieren får sin nye rot lagt til eksisterende begrensede bibliotekpolicy;
  `EnableAllFolders` slås ikke på. Andre kontoners policy endres ikke.
- Brukersiden henter kø/fremdrift/feil og ferdig status. Polling stopper når
  siden forlates, og sene svar kontrolleres mot aktiv konto og visningssekvens.

Isolert native test: `Test-PersonalYouTubeAlphaJob.ps1` bestod. Ekte HTTP-lagring
startet produksjonsjobben, og eieren fikk biblioteket via vanlig Views og
videoen via GetItems/native videorute. En annen konto med brede native
bibliotekrettigheter fikk bare egen jobbstatus og 404 ved fremmed video.
Profilsletting sperret videoen. Google-transporten var simulert med korrekt
syntetisk nøkkel/kanal, flere eldre videoer og en ekstra side som ikke skulle
hentes; selve YouTube-videoen og native publisering var virkelige.

Komponenttestene omfatter også kansellering ved ny lagring, parallelle eiere,
varig ferdigstatus, sanitert feilstatus og profilens jobbstatus ved sletting.
Den samlede testen omfatter nå også kanalbytte med beholdt nøkkel, fjerning
av tidligere native rot/filer, sletting og uendret B-medie. To faktiske
serveromstarter bekreftet samme rot og video: både Ready og en simulert
Publishing-status over en allerede aktiv native publisering. Et faktisk
prosessavbrudd mens CreateItem var pauset i Preparing ble gjenopprettet:
uferdig rot/media ble fjernet, nøkkelen beholdt, og én ny samling spilte av.
Avbruddstesten gjelder Windows-fixturen. Docker-resultatene nedenfor bruker
ekte Google; klientapper er ennå ikke testet.

Administratorens side har nå aktivering, tre verktøystier og video-/samling-/
serverbudsjett. Innstillingene krever omstart. En felles kø serialiserer
mediepublisering mellom eiere og reserverer plass til både staging og native
kopier; komponenttesten bruker eksisterende medier og midlertidige filer.
Manglende verktøy, ugyldige grenser, fullt budsjett og kjente Google-feil har
saniterte feilkoder og forklaringer i brukersiden. UI-et er ennå ikke prøvd
i en faktisk nettleser etter disse endringene.

Den siste samlede native kjøringen bestod med 12 observasjoner; komponentene
bestod med 212. Tidligere forsøk hadde oppstarts-/minnefeil. Testcontrolleren
setter nå 1 GiB grense bare for den portable serverens .NET-heap på den delte
testmaskinen; hovedserverens miljø endres ikke. Google-transporten er fortsatt
simulert. Ingen universell skjermingsgaranti følger av observasjonstallet.

Eksisterende HA-SSH til Docker-hosten er bekreftet. En separat container
`emby-youtube-alpha-verification` kjører samme installerte image (Emby
4.10.1.0), med kun `/tmp/emby-youtube-alpha-verification/config` montert og
HTTP-port 18097 bundet til 127.0.0.1. Hovedserverens data, plugin og konfigurasjon
er ikke kopiert eller endret.

2026-10-14: Pluginen er installert med verifisert SHA256, alle tre kontrollkroker
er aktive, og arbeideren startet fra vanlig PluginEntryPoint. Node 24.21.0,
yt-dlp 2026.08.19 og en fungerende Linux-FFmpeg er installert med verifiserte
utgivelseshashverdier. Den første FFmpeg-filen i det ferske imaget kunne ikke
kjøres. Emby satte også LD_LIBRARY_PATH til private biblioteker; alle tre
eksterne verktøy krasjet med verdien og fungerte uten den. Bufferprosessen
fjerner nå LD_LIBRARY_PATH og LD_PRELOAD for eksterne Linux-verktøy. Serverens
eget miljø og hovedcontaineren endres ikke.

En vanlig A lagret den virkelige nøkkelen gjennom MyProfile. Arbeideren hentet
ekte Google-data, bufret to videoer og publiserte én native rot uten adapter.
Views/GetItems viste innholdet til A. B med brede bibliotekrettigheter så ikke
roten og fikk 404 på begge videostrømmene; A fikk 200 med MP4-data. Dette er
HTTP-bevis, ikke faktisk klientavspilling. Den globale plugin-nøkkelen er tom,
og den personlige nøkkelen finnes ikke i klartekst i profilfilen eller rapportene.

Bytte til en kontrollert ugyldig nøkkel fjernet gammel rot og videoreferanser.
Google sitt moderne API_KEY_INVALID-format håndteres nå som YouTubeKeyRejected;
dette er verifisert med ekte Google og 213 komponentkontroller. Vanlig B får
403 på serverdiagnostikken. Brukersiden har fått «Lagre og oppdater» og sletting
med bekreftelse, men disse endringene er ennå ikke prøvd i nettleser.

Tilbakeføring til den gyldige nøkkelen avanserte nøkkelrevisjonen, men Google
svarte quotaExceeded. Jobben viser YouTubeQuotaExceeded; ingen personlig rot
er aktiv akkurat nå. Tilbakeføring, Docker-omstart/sletting og klienttest
gjenstår når en gyldig nøkkel har kvote. Første positive jobb brukte DLL
319FD525…; gjeldende DLL 3A5F584B… inkluderer også nøkkelfeil og sletteknapp.
Den første kjøringen er ikke full ende-til-ende-verifisering av siste DLL.
Rapport: `bin/docker-alpha-evidence.json`.

## Tidligere godkjenningsliste (historisk)

1. Tilbakeføring etter nøkkel-/kvotefeil, lesbar native metadata og
   oppdaterings-/slettingsflyt: bekreftet i angitte Docker-/Chrome-prøver.
2. Docker/Linux-livssyklus: sletting, faktisk omstart og Buffering-avbrudd
   med automatisk gjenoppretting bestod. Windows Preparing-avbrudd bestod
   i den oppgitte Windows-kjøringen. Fasene er ikke universelt dekket.
3. Administrator-UI: alle åtte alfa-felt bestod lagring og serveravlesning.
   Chrome viste kvotefeil og kanalvalideringsfeil. Øvrige browserfeilkoder
   er uverifisert individuelt; komponent-/serverbevis må ikke beskrives
   som slike nettleserprøver.
4. Flere kanaler: ekte Google ga én video fra hver av to forskjellige
   kanaler, med korrekte native titler og kontrollerte eier-/B-strømmer.
5. Faktisk avspilling i Android/Android TV: **venter på resultat**.
   Chrome-avspilling bestod. Øvrige klienter skal merkes uverifisert.
6. Alfaversjon og lokal installasjons-/tilbakerullingspakke: bygget og
   pakkehashverifisert. **Siste godkjenningsaudit og kandidatstatusen
   gjenstår etter apptesten**. Ingen offentlig utgivelse er utført.
