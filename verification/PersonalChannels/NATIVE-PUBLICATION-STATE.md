# Preparing og Active på faktisk Emby

Kontrollert 2026-10-12 på isolert Emby 4.10.1.0. `Test-ProductionNativeBindings.ps1 -PublicationJournal` bruker produksjonens journal og register gjennom testpluginens eksperimentelle kroker. Ingen produksjonskrok ble installert på hovedserveren, og ingen faktisk YouTube-kilde ble brukt.

## Faktisk oppsett og tilstandsovergang

To syntetiske vanlige kontoer fikk hvert sitt native prøvebibliotek og sin profil. Native elementer finnes allerede før denne testen av journaltilstanden; dette er **ikke** en test av første bibliotekoppretting før native ID-registrering.

Den isolerte administrasjonsproben kalte Begin i den allerede innlastede produksjonsjournalen. A/B fikk persistente Preparing-oppføringer. Faktiske native rot-, fysisk mappe- og videoidentiteter ble registrert under deres profiler. Testmodusen lot deretter journalens samlede avgjørelse styre de kjente referansene.

B ble aktivert først. A sine rot- og videoreferanser forble nektet i Preparing, mens B beholdt metadata, liste og SHA-korrekt nedlasting. En direkte native administrasjonskontroll bekreftet at A sin rot og samme video-ID fortsatt faktisk fantes.

Serveren ble så faktisk stoppet og startet igjen. Testen krevde ny BootId og Ready før kontrollene fortsatte. A sine Preparing-referanser var fortsatt nektet; B beholdt positive kontroller. Først etter separat Activate av A ble A sine metadataaliaser og SHA-korrekte nedlasting tilgjengelige igjen.

Deretter ble den tidligere livsløpstesten gjentatt: profilsletting mens native innhold beholdes, en ny faktisk serveromstart og profilgjenoppretting med ny generasjon. Gamle A-referanser forble nektet. Registrering av eksisterende native identiteter under ny generasjon ble avvist med uendret registerhash. B beholdt tilgangen.

## Resultater og opprydding

Rapport: `bin/production-native-publication-journal-results.json`, Completed=true, PublicationJournal=true, PreparingRestartVerified=true og RestartVerified=true.

**86 observasjoner:** 77 HTTP-kontroller og ni registrerings-/journal-/native tilstandskontroller. Syv positive nedlastinger var SHA-korrekte egne prøvefiler. Alle 19 nektede nedlastinger ga 404 og null bytes. Rot- og videometadata ble kontrollert via begge native aliaser. Videolister skjulte nektet A-innhold og beholdt B sin positive kontroll.

Prosjektene bygget uten advarsler/feil. De tidligere 112 komponentkontrollene er uendret i omfang; denne testen tilfører faktisk journaltilstand i den isolerte serverprosessen.

Journal, register, profiler, isolert krypteringsnøkkel, testplugin/modus, prøvefiler, biblioteker og kontoer ble fjernet. Den uavhengige sluttkontrollen `bin/production-native-publication-journal-cleanup.json` krever alle ni felt true. Den tidligere umiddelbare fixture-rapporten med ServerStopped=false under avslutning beholdes separat.

## Hva som fortsatt må lukkes

Testen beviser den navngitte overgangen for eksisterende, registrerte native elementer gjennom testkrokene. Den beviser ikke at en ny virtuell rot før første binding klassifiseres privat, eller at alle produksjonsruter bruker avgjørelsen. En virtuell rot kan ha native sti utenfor journalens interne mediemappe; kontrollerte fysiske kildesteder/publiseringskontekst må derfor føres inn i den tidlige klassifiseringen.

Produksjonens publiserer, universelle native tilgangskroker, automatisk gjenoppretting/opprydding, avledede referanser og personlig YouTube-/alle-klientkjede gjenstår. Full skjerming er fortsatt ikke bevist.
