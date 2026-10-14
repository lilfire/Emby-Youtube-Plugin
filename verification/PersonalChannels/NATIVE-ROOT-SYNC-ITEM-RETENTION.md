# Direkte native Sync-elementkontroll ved privat rotsletting

12. oktober 2026. Isolert Emby 4.10.1.0, to vanlige kontoer,
native HomeVideos-biblioteker og lokale syntetiske MP4-filer.
Produksjonspluginen og hovedserveren er urørt.

Den tidligere Ready Original-testen observerte at A-jobben var borte,
men undersøkte ikke elementet uavhengig av jobben. Den nye admin-proben
kaller faktisk SyncManager.GetJobItem direkte med element-ID-en og
kontrollerer parent-jobben separat. En eksisterende rad tillates bare
hvis JobId matcher forventet jobb og ItemId har kjent privat fixture-
opprinnelse. Bare booleans og native status returneres.

Før filhenting fantes A-elementet og parent-jobben, status var
ReadyToTransfer og privat kildeopprinnelse var verifisert. A hentet
hele Original-filen med 200, 11 071 bytes og korrekt kilde-SHA-256.
Etter filhenting fantes element og jobb fortsatt, men status var
Transferring. Første forsøk som krevde ReadyToTransfer etter filhenting
stoppet derfor; det regnes ikke som bestått. Den korrigerte testen
måler status både før og etter filhenting.

Testadmin slettet den private native roten uten eierbytte eller nytt
Guard Enable-snapshot. A-kontoen ble beholdt, eierskapsconfig-hash var
uendret, og SDK readback bekreftet at rot og video var borte.

Direkte GetJobItem på den gamle A-element-ID-en returnerte null etter
sletting og etter faktisk omstart. GetJob returnerte også null begge
ganger. Det er altså ikke bare en fraværende parent-jobb som skjuler
at den konkrete elementraden fremdeles finnes.

B, den eksisterende A-kontoen og anonym klient fikk 404 på gamle
jobb-/element-/filreferanser. Alle sju avslåtte filkall hadde 0 rå
payload-bytes. Fire komplette filhentinger hadde riktig SHA-256:
A/B før sletting og B etter sletting og etter omstart. B sine lister
hadde korrekt eget innhold. Guard var klar med ny BootId.

Kjøringen har **35 observasjoner: 29 HTTP og seks native readbacks**.
De seks er to GetJob-readbacks og fire GetJobItem-kontroller (før
filhenting, etter filhenting, etter sletting og etter omstart).
Rapport: `bin/native-root-ready-files-results.json`, Completed=true.
Den tidligere 31-observasjoners kjøringen med rå denial-bytes er bevart
i `bin/native-root-ready-files-raw-body-results.json`.

Dette gjelder én konkret tidligere ReadyToTransfer-rad under vanlig,
sekvensiell rotsletting. Det viser ikke at foreldreløse Sync-elementer
aldri kan oppstå ved samtidig klargjøring/sletting, prosessavbrudd,
andre profiler eller andre native versjoner. Fravær er heller ikke
et tilgangsbevis for en faktisk beholdt Sync-ressurs; ingen slik
ressurs ble observert her. Tidligere beholdt LiveStream-test gjelder
en annen ressurstype. Full skjerming av faktisk YouTube-funksjon i
alle klientfamilier er fortsatt ikke bevist.

Testkontoer, biblioteker, Sync-jobber og medier er fjernet; fixture,
guard, registre/tempfiler og journal er borte og serverprosessen
stoppet. Alle felter i
`bin/native-root-sync-item-retention-cleanup.json` er true.
