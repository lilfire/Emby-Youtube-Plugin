# Personlige profilruter i produksjonspluginen

Implementert og kontrollert 2026-10-12, etter brukerens tillatelse til produksjonskode etter planen. [PersonalYouTubeService.cs](../../PersonalYouTubeService.cs) bruker [PersonalYouTubeStore.cs](../../PersonalYouTubeStore.cs). Endringen er kjørt i isolert Emby 4.10.1.0, ikke deployert til hovedserveren.

## Rutene

| Rute | Handling |
|---|---|
| GET `/YouTubePlugin/MyProfile` | Egen profil, kanal-ID-er og nøkkelstatus; aldri lagret nøkkel |
| POST `/YouTubePlugin/MyProfile` | Egen oppdatering med ExpectedRevision, Channels, valgfri ApiKey eller ClearApiKey |
| POST `/YouTubePlugin/MyProfile/Delete` | Slett egen generasjon med ExpectedRevision |

Alle ruter krever native Emby-autentisering. Eieren kommer fra `IAuthorizationContext.GetAuthorizationInfo(Request).User.Id`, ikke sti, query eller body. Ingen eierparameter finnes i oppdateringsskjemaet. Uregistrerte JSON-felter og duplikater, også med annen bokstavstørrelse, avvises. GET med fremmed UserId i query returnerer fortsatt den faktisk autentiserte kontoens profil; det er ikke et oppslag av den oppgitte kontoen.

Oppdateringer krever revisjon og kanaler. JSON-kroppen er begrenset til 32 768 bytes før parsing. Ugyldige oppdateringer gir 400, gammel revisjon 409 og for stor kropp 413. Lagringsfeil gis som et generelt 503-svar uten intern filbane eller hemmelig verdi. Profilresponsene bruker `Cache-Control: no-store, private`.

Denne serverbuilden mapper ikke den brukte SDK-HttpException automatisk til ønsket HTTP-status, og resultatfabrikken returnerer en StreamWriter som ikke implementerer IHttpResult. Den ferdige tjenesten bruker derfor den dokumenterte IRequest.Response.StatusCode og resultatfabrikkens JSON-utdata. To mislykkede kontraktforsøk er bevart separat, ikke regnet som bestått:

- `bin/production-profile-service-error-status-incomplete.json`
- `bin/production-profile-service-result-contract-incomplete.json`

## Faktisk serververifisering

[Test-ProductionPersonalProfiles.ps1](Test-ProductionPersonalProfiles.ps1) fullførte nå med 37 HTTP-kontroller (tidligere 35). Rapport: `bin/production-profile-service-results.json`, Completed=true og RestartVerified=true. De to nye kontrollene bekrefter sanitet 503 ved ødelagt A-profil og fortsatt fungerende B-profil. `InvalidDataException` håndteres eksplisitt som utilgjengelig lagring.

- To vanlige kontoer fikk egne profiler og ulike samlings-/generasjons-ID-er selv med samme YouTube-kanal.
- Syntetiske nøkler ble ikke returnert i noen kontrollrespons og lå ikke i klartekst i de lagrede profilene.
- Anonym GET, lagring og sletting ble avvist med 401.
- Fremmed profilsti ga 404. Fremmed eier i body ga 400 uten endring av A- eller B-filen.
- Gamle revisjoner, ugyldig kanal, manglende revisjon, doble JSON-felter, ødelagt JSON og for stor kropp ga forventede avslag.
- Tolv faktisk utsendte samtidige HTTP-lagringer med samme A-revisjon ga én 200 og elleve 409. B sin filhash var uendret. Dette beviser revisjonskonflikten i denne kjøringen, ikke overlapptiming inne i lagringslåsen.
- Etter faktisk omstart beholdt begge profiler generasjon, revisjon og nøkkelstatus. Guard var Enabled/Ready med ny BootId før kontrollene.
- A kunne slette og gjenopprette egen profil med samme samlings-ID, ny generasjon og uten gammel nøkkel. B beholdt egen generasjon, nøkkelstatus og identisk profilfil.
- No-store-headeren ble kontrollert på profilkall gjennom tjenesten, inkludert normale oppdateringsavslag. Native autentiserings-/ukjent-ruteavslag er ikke påstått dekket av den headerkontrollen.

De 26 lagringskontrollene mot produksjonsklassen ble også kjørt på nytt og bestod. De dokumenteres separat i [PRODUCTION-PROFILE-STORE.md](PRODUCTION-PROFILE-STORE.md); tallene summeres ikke til et universelt sikkerhetsbevis.

## Gjenstående integrasjon

Brukermeny, faktiske YouTube API-kall og bakgrunnsjobber er ennå ikke koblet til disse profilene. Rutene publiserer ingen native personlige biblioteker. Native medietilgang, varig referansebinding, avledede filer, fungerende YouTube-mediekjede og alle faktiske klientfamilier er fortsatt nødvendig før full skjerming kan godkjennes.

## Opprydding

Syntetiske brukere, biblioteker, kilder, testplugin og guard ble fjernet med standardfixture-opprydding. Kun de to eksakte syntetiske produksjonsprofilfilene og testens krypteringsnøkkel ble slettet; mappen måtte være fraværende før oppsettet, og uventede ekstra filer ville stoppet oppryddingen. Separat etterkontroll: `bin/production-profile-service-cleanup.json`.
