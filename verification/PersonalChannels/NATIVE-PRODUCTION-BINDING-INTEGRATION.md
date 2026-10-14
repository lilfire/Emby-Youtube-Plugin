# Produksjonsbindinger mot faktisk Emby

Kontrollert 2026-10-12 på isolert Emby 4.10.1.0. Produksjonsregisteret ble brukt av testpluginens eksisterende eksperimentelle tilgangskroker. Ingen slik krok ble lagt til produksjonspluginen, ingen faktisk YouTube-kilde ble brukt, og hovedserveren ble ikke endret.

## Kallkjeden

`ProductionBindingBridge.cs` bruker den allerede innlastede produksjonsassemblyen. Den registrerer faktiske native elementer gjennom `PersonalYouTubeStore.Prepare` og `PersonalYouTubeNativeBindings.Register`, uten kopier av produksjonsalgoritmen. Administrasjonsproben godtar bare de to kontrollerte, syntetiske bibliotekene med samsvarende vanlig konto, bibliotekpolicy og prøvevideoens filplassering.

Hvert bibliotek har tre registrerte native identitetspar: virtuell rot, fysisk foreldremappe og video. Et første forsøk forventet bare rot/video og avviste den fysiske mappen. Det ble rettet ved å kontrollere den faktiske foreldremappen mot prøvevideoens plassering. Det ufullførte forsøket er bevart i `bin/production-native-binding-member-incomplete.json` og regnes ikke som bestått.

I aktiv testmodus lar `PrivacyGuard.FindOwner` produksjonsregisteret avgjøre kjente native referanser før prototypekartet. Registerets nåværende generasjonsavgjørelse oversettes til eieren eller et avslagsmerke for den eksperimentelle håndhevingen. Testmodus er lagret separat og leses etter omstart. Prototypens øvrige mekanismer er fortsatt til stede; dette er ikke bevis for at en ferdig produksjonsgrense bruker registeret for alle innganger eller ukjente referanser.

## Resultater

`Test-ProductionNativeBindings.ps1` fullførte med **51 observasjoner**: 47 HTTP-kontroller av metadata/nedlasting/lister, to faktiske native registreringer, én direkte native kontroll av beholdt kilde og én kontroll av nektet identitetsoverføring. Rapport: `bin/production-native-binding-results.json`, Completed=true og RestartVerified=true.

- Vanlige A/B-kontoer opprettet egne profiler med samme syntetiske kanal. Faktiske native ID/GUID-par ble registrert under deres ulike samling/generasjon.
- Begge metadataaliaser ga 200 for eieren og 404 for den andre kontoen. Eiernedlastinger var 11 071 bytes med samme SHA-256 som egne prøvefiler; fremmede og anonyme nedlastinger ga 404 og null bytes.
- A slettet sin profil gjennom produksjonsruten. A sitt native bibliotek, foreldremappe og video ble ikke slettet. Direkte native kontroll bekreftet den beholdte roten og den samme video-ID-en.
- Likevel ga gamle A-metadatareferanser 404 både for A og B. A/B/anonyme gamle A-nedlastinger ga 404 og null bytes. A sin videoliste viste ingen private A-/B-videoer. B beholdt egen metadata, videoliste og SHA-korrekt nedlasting.
- Serverprosessen ble faktisk stoppet og startet igjen. Testen krevde ny fixture BootId og Ready før gjentakelsen. De samme avslagene og B sine positive kontroller bestod.
- A gjenopprettet profilen: samme CollectionId, ny GenerationId. Et forsøk på å registrere de eksisterende native identitetene under den nye generasjonen ble avvist som kollisjon, og registerfilens hash var uendret. Gamle referanser forble nektet; B beholdt tilgangen.

Dette viser at profilens generasjon kan styre kjente, eksisterende native referanser gjennom disse testkrokene, også når native innhold faktisk beholdes. Det erstatter ikke den universelle servergjennomgangen, en produksjonspubliseringskjede eller faktiske klient-/YouTube-kontroller.

## Opprydding og resterende grense

Testkontoer, biblioteker, prøvefiler, modusmarkør, testplugin, produksjonsprofilfiler, register og isolert krypteringsnøkkel ble fjernet. Den vanlige umiddelbare oppryddingsrapporten viste ServerStopped=false mens prosessen avsluttet. Den uavhengige sluttkontrollen i `bin/production-native-binding-cleanup.json` krever stoppet server og alle øvrige mål fjernet.

Neste nødvendige steg er produksjonens tilgangsgrense og publiseringsjournal. Ukjente/private referanser før registrering og native etterkommere som ikke er registrert må håndteres uten å falle tilbake til tidligere navn-/rotkart. Strømmer, Sync og avledede filer trenger kildens generasjonsbinding. Ingen påstand om full skjerming eller alle klienter følger av denne finitte testen.
