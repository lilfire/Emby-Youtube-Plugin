# Faktisk konverterte Sync-filer mellom Emby-kontoer

Undersøkt 2026-10-12 på isolert Emby 4.10.1.0 med den eksperimentelle serverinterne skjermingen. Produksjonspluginens kildekode og hovedserveren er uendret.

## Resultat

Den fullførte kjøringen bestod 16 HTTP-kontroller: fire komplette eierhentinger, åtte fremmede/anonyme filavslag og fire Ready-lister. Kontrollene ble utført for begge vanlige kontoer, før og etter faktisk serveromstart.

- Emby klargjorde to native Sync-jobber med `ReadyToTransfer`, ikke fabrikkert jobbstatus.
- Utdata var ekte MPEG-4-videoer i MP4, seks sekunder og 12 405 bytes. Kildene brukte H.264 og var 11 071 bytes.
- Begge utdata lå på egne native utdatafilbaner, og begge hadde annen SHA-256 enn sin kildefil. `ffprobe` bekreftet MPEG-4-codec og varighet.
- Hver eier fikk HTTP 200, hele filen og SHA-256 identisk med sin egen native utdatafil.
- Annen konto og anonym klient fikk HTTP 404 med nøyaktig null rå responsbytes. Kontrollene sammenlignet også avslagets hash med de private utdatafilene og sjekket MP4-signatur.
- Ready-listene inneholdt riktig eget videonavn og ikke den andre eierens navn.
- Guard var Enabled/Ready med ny BootId etter omstart. Legitimiteten til Sync-funksjonen ble observert før omstart gjennom serverens faktiske funksjonskontroll; ingen lisenssjekk ble omgått.

Rapport: `bin/native-converted-sync-files-results.json`. Skript: [Test-NativeConvertedSyncFiles.ps1](Test-NativeConvertedSyncFiles.ps1). Kjøringen før utvidet utdataopprydding bestod også; den brukes ikke til å doble testdekningen.

## Native oppsett

Emby dokumenterer at [Sync støttes gjennom klientkapabiliteter og DeviceProfile](https://dev.emby.media/doc/restapi/Sync.html), og at [SyncJobRequest](https://dev.emby.media/reference/RestAPI/SyncService/postSyncJobs.html) har blant annet Container, VideoCodec, AudioCodec og Bitrate. [Download Options](https://emby.media/support/articles/Sync.html) beskriver valg av konverteringskvalitet og custom bitrate.

Testen meldte inn to syntetiske klientmål med SupportsSync=true. Profilen hadde ingen DirectPlayProfiles og en statisk MPEG-4/AAC-transkodingsprofil. Native POST Sync/Jobs brukte Custom/General, MP4/MPEG-4/AAC og Bitrate=100000. Deretter kjørte serverens egen SyncPrepare-oppgave. Det avgjørende konverteringsbeviset er de observerte filene, codec og hash, ikke bare de innsendte profilverdiene eller oppgavestatusen.

## Grense for konklusjonen

Dette lukker det testede hullet mellom Original-filer og faktisk konverterte Sync-filer for disse to kildene, denne profilen og denne serverversjonen. Det beviser ikke full skjerming, alle konverteringsprofiler, cloud-/folder-sync, sletting under pågående konvertering, alle klientapper eller produksjonsintegrasjonen med YouTube. Den tidligere observerte mappe-GUID-kollisjonen er fortsatt et eget uløst funksjonsavvik.

## Opprydding

Native sletting av Sync-jobbene fjernet ikke alle de fysiske konverterte filene. Testskriptet ble derfor utvidet til å registrere akkurat sine egne native utdatafiler i minnet, validere banen under den isolerte serverens `data/sync`, kontrollere uendret hash og slette hver fil eksplisitt etter serverstopp. Ingen rekursiv sletting ble brukt.

De to utdatafilene fra første kjøring ble knyttet til sine eksakte native ffmpeg-logger og syntetiske kilder før sletting; readback finnes i `bin/native-converted-sync-first-output-cleanup.json`. Den siste kjøringens opprydding er i `bin/native-converted-sync-files-cleanup.json`. En separat sluttkontroll bekrefter ingen gjenværende filer i isolert `data/sync`, ingen EmbyServer-prosess og ingen klientjournal: `bin/native-converted-sync-files-final-cleanup.json`. ServerStopped-feltet i den umiddelbare oppryddingsrapporten kan være false mens prosessen avslutter; det feltet er bevart, ikke overskrevet.
