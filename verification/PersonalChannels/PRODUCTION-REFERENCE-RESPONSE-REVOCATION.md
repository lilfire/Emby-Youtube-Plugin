# Direkte metadata og avspillingsinformasjon ved profilsletting

Isolert Emby 4.10.1.0, 12. oktober 2026. Hovedserveren er urørt.

## Påvist brudd og svarkontrakter

`Test-ProductionServiceGate.ps1 -WriteRace` fullførte 59 observasjoner. NativeReferenceWriteGate fulgte faktisk autentisert A og den faktiske GetItem-skriveren, med en kontrollert pause ved native WriteToAsync før produksjonens prioritet-800 skrivekrok. Ingen svarverdier ble endret. B sin metadata, fil og avspillingsinformasjon fungerte under pausen. A sin profil ble slettet, Deleted lest tilbake og fortsatt ventende HTTP-kall kontrollert. Ved frigivelse kom 200 med privat videonavn. `bin/production-service-write-race-results.json` har IsolationPass=false.

Den eksisterende service-prefixen nektet fremmede referanser ved inngangen, men knyttet ikke et godkjent direkte svar til senere utlevering. Listekroken kjente heller ikke denne skriveren.

Første forsøk på å knytte både metadata og avspillingsinformasjon direkte til skriverkroken avviste B sin positive PlaybackInfo med 404. Native GetItem returnerer StreamWriter, mens native PlaybackInfo returnerer MediaBrowser.Model.MediaInfo.PlaybackInfoResponse som et objekt for senere serialisering. De ufullførte testene er bevart i `bin/production-service-write-contract-incomplete.json` og `bin/production-service-playback-contract-incomplete.json`; de er ikke bestått evidens. Et senere byggforsøk brukte en metode som bare finnes på den konkrete fabrikken, ikke SDK-interface; dette ble rettet til SDK-metoden GetResult<T> før den gjeldende koden ble testet.

## Produksjonsendring

ServiceReferenceGate tar nå eierens transfer-sperre for tillatte private referanser og kontrollerer referansen på nytt etter at sperren er vunnet. Den holder sperren gjennom native Execute-task og frigjør i finally. Prefix, postfix og finalizer verifiseres ved installasjon og Snapshot. Ukjente offentlige referanser beholder native kjede.

GetItem, GetPlaybackInfo og GetPostedPlaybackInfo kontrolleres også etter task-fullføring. Et faktisk PlaybackInfoResponse serialiseres med Embys injiserte IHttpResultFactory.GetResult<T> og faktisk IRequest, slik at native resultatfabrikk styrer serialisering. Både denne skriveren og den native metadata-skriveren registreres med autentisert eier og en referansespesifikk tilgangskontroll i den eksisterende verifiserte WriteToAsync-kroken.

Skrivekroken bruker samme per-eier-sperre gjennom hele native write-task og utfører den registrerte referansekontrollen før skriving. En sletting som har fullført før dette, avviser den gamle referansen. En skriver som har vunnet sperren først, fullfører sin native write-task før samme eiers profilendring kan bekreftes. Skrivergjenbruk mellom kontekster og ukjent resultatkontrakt i disse beskyttede svarfamiliene avvises. Manglende verifisert skrivekrok før registrering gir også avslag.

De øvrige auditerte DTO-ene bruker sperren gjennom Execute-task, men dette innebærer ikke at Download-filens senere utlevering er dekket av denne metadata-skriverkoblingen.

## Verifisert effekt

`-WriteRace -RequireRaceSafe` fullførte 60 observasjoner. Samme private metadata-kall etter fullført profilsletting fikk 404 uten privat navn. Produksjonskroken sto som Installed=true, WritesDelta=3 og DeniedDelta=1 gjennom pausen. B sin metadata, fil med uendret SHA og GET PlaybackInfo fungerte før, under og etter slettingen og etter omstart. Ti fremmede DTO-kall ga fortsatt nøyaktig ti inngangsavslag i hver fase; egne native favoritt-/avspilt-endringer fungerte og fremmede endringer lot A sin UserData være uendret. Rapport: `bin/production-service-write-protected-results.json`.

`-PlaybackWriteRace -RequireRaceSafe` fullførte først 66, deretter 74 observasjoner med skjerpede positive kontroller. A sin tillatte PlaybackInfo ble først målt å inneholde privat videonavn. En ny faktisk PlaybackInfo-skriver ble så pauset, profilen slettet og Deleted lest tilbake før frigivelsen. Svaret ble 404 uten privat navn, med Installed=true, WritesDelta=5 og DeniedDelta=1. B sin GET og POST PlaybackInfo hadde minst én faktisk mediekilde, B sitt private navn, ingen A-navn og ingen ErrorCode i alle positive faser, inkludert omstart. Rapport: `bin/production-playback-info-write-results.json`, gjeldende Count=74.

Fixture-skjermingen var av under assertions i begge kjøringer. Timingkroken endrer bare tidspunkt og identifiserer syntetisk A gjennom faktisk autentisering. Ingen vanlig bruker får styre den i produksjonen.

Liste-sperreregresjonen `-AfterWriteCheckRace -RequireRaceSafe` fullførte fortsatt 44 observasjoner etter felles skriverkobling. Komponentene fullførte 186 kontroller med testdata fjernet. Native livsløpsregresjon `-PublicationJournal -ActualAccess` fullførte 235 observasjoner med begge omstarter verifisert; denne regresjonen har fixture-skjerming på og er ikke ytterligere produksjonskrok-alene-bevis.

Avsluttende opprydding leses tilbake i `bin/production-reference-response-cleanup.json`, med tidligere umiddelbar stoppmarkør bevart separat fra den endelige prosesskontrollen.

## Åpne krav

Dette beviser de målte metadata-/PlaybackInfo-svarene i denne serverbuilden. Det beviser ikke faktisk YouTube-avspilling, hele HLS-/mediekjeden, senere filutlevering for Download, XML-/komprimeringsvarianter i alle klienter eller samordning med native/register/journal-/bruker-/tokenendringer. Synkrone feilstier gjennom de nye native finalizer-krokene er ikke separat injisert i en HTTP-test. Øvrige serverinnganger og ferdig personlig publisering står fortsatt åpne.
