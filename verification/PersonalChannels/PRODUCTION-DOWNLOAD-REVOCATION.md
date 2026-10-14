# Privat GetDownload ved fullført profilsletting

12. oktober 2026. Isolert Windows Emby 4.10.1.0, lokale prøvevideoer,
syntetiske ikke-administrative kontoer og eksperimentell PrivacyGuard deaktivert.
Dette er avgrenset evidens for faktisk GetDownload, ikke full skjerming.

## Feilen og rettelsen

En autentisert A-forespørsel ble holdt ved den faktiske native skriverinngangen.
A sin profil ble slettet og tilstanden lest tilbake mens forespørselen fortsatt
var ventende. Før rettelsen returnerte den frigjorte forespørselen HTTP 200 og
hele A-filen (11071 byte, SHA identisk med kildefilen). Rapporten
`bin/production-download-write-race-results.json` fullførte 75 observasjoner,
men selve isolasjonskontrollen var falsk. Fullført rapport er ikke bestått garanti.

GetDownload returnerer FileWriter, ikke StreamWriter. Produksjonskontrollen
registrerer nå begge verifiserte skrivertyper og kontrollerer eierens tilgang
under samme profilsperre ved faktisk skriverinngang. Avslag frigjør en allerede
åpen StreamHandler; den opprinnelige skriveren kjøres ikke.

Første kroppskontroll ga 404 og ingen kildefil. Den eldre rapporten
`bin/production-download-body-only-results.json` (76 observasjoner) undersøkte
ikke headerne og er derfor utilstrekkelig. En skjerpet test påviste at avslaget
fortsatt inneholdt privat filnavn i Content-Disposition. Denne feilen er bevart
i `bin/production-download-header-leak-results.json`, Completed=false.

IResponse.Headers er en kopi i den faktiske NetCoreResponse. Clear på denne
samlingen fjernet ikke den sendte headeren; AddHeader med null gjorde heller
ikke det. Rettelsen tømmer den underliggende HttpResponse.Headers gjennom
verifiserte felt-/grensesnittkontrakter før native feilbehandling får et generisk
ResourceNotFound-avslag. Responsklassen ligger i EmbyServer-assemblyen;
HttpListenerHost og skriverne ligger i Emby.Server.Implementations.

## Gjeldende verifisering

`Test-ProductionServiceGate.ps1 -DownloadWriteRace -RequireRaceSafe` fullfører
76 observasjoner i `bin/production-download-write-protected-results.json`:

- A får HTTP 404, text/plain, 16 byte; Content-Length er feilsvarets lengde.
- Ingen privat filnavn i kropp eller headere; ingen Content-Disposition,
  Content-Range, ETag, Last-Modified eller Accept-Ranges.
- Svarinnholdets SHA er forskjellig fra A-kilden. Sammen med generisk kort
  tekstsvar avviser dette levering av prøvevideoen i denne kjøringen.
- Produksjonsskriverkontrollen er Installed=true, WritesDelta=6 og DeniedDelta=1.
- Prøvefilen kan åpnes eksklusivt etter avslaget, som kontrollerer at ingen
  gjenværende kildehåndtak i denne testen hindrer slik åpning.
- B beholder egen metadata, SHA-korrekt fil og GET/POST PlaybackInfo før,
  under og etter A-sletting samt etter faktisk serveromstart.
- Ti konkrete tjeneste-DTO-er beholder kontroller mot andre kontoer og
  gamle referanser. Eksperimentell PrivacyGuard er lest tilbake som deaktivert.

FileWriter.WriteToAsync har i denne serveren IL-hash
`C727A5F81B37C15D6DFAB13492CCA85C01F8055AD7E4828C7FF0EDA9AE875F8C`.
Installasjon avgrenser native skriver-/tjenestekontrakter og krever tilgjengelig
HttpResponse/IHeaderDictionary-kontrakt. Dette er ikke verifisering av Linux,
Docker eller andre Emby-builds, og kickoff-hash beviser ikke alle async-metoder.

Etter headerrettelsen passerer GET PlaybackInfo-regresjonen 75 observasjoner,
GetItems-skrivesperren 44 og komponentkontrollene 186. Det siste header-testløpet
feilet først på en feil i verifikatoren: HttpHeaders.Contains fikk et
content-headernavn. Verifikatoren sammenligner nå navn fra begge samlingene;
den nye 76-observasjoners kjøringen fullførte med de skjerpede kravene.

Opprydding er lest tilbake i `bin/production-download-cleanup.json`: syntetiske
brukere, biblioteker, medier og fixture er borte, profilmappen og journalene
er borte, og den isolerte serverprosessen er faktisk stoppet. Det tidligere
øyeblikksbildet ServerStopped=false er bevart sammen med endelig true.

## Åpne beviskrav

HEAD, range-forespørsler og betingede svar var ikke undersøkt av denne kjøringen.
Senere avgrenset evidens finnes i [PRODUCTION-DOWNLOAD-VARIANTS.md](PRODUCTION-DOWNLOAD-VARIANTS.md).
Alle øvrige fil-/streaminnganger gjenstår. Det samme gjelder ny innsetting/reparenting,
register-/journalendringer, tokenrevokering, avbrutte eller langvarige overføringer,
pakker som allerede er levert, og hele klient-/YouTube-kjeden.

Native innstillinger og brukerens faktiske nøkkel/kanaler må fortsatt kobles
til komplett personlig publisering. Full skjerming er derfor fortsatt uoppnådd.
