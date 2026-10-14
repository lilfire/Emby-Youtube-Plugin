# Ventende bilde-/undertekstsvar ved profilsletting

Oppdatering 13. oktober 2026: Historisk test før asset-leserbinding.
[PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver nåværende binding og videre tester av avledede ressurser.
Vurdering av manglende binding nedenfor gjelder utgangspunktet.

12. oktober 2026. Isolert Windows Emby 4.10.1.0, syntetiske lokale A/B-filer,
produksjonsprofiler/native bindinger, brede native bibliotekrettigheter for
vanlige kontoer, eksperimentell guard deaktivert og lest tilbake.

## Faktisk kontrollert forløp

NativeReferenceWriteGate sporer resultatet fra det faktiske GetItemImage-
eller GetSubtitle-kallet for autentisert syntetisk A. Den pauser den faktiske
native FileWriter ved WriteToAsync før produksjonens skriverkontroll:
fixture-prioritet 1000, produksjonsprioritet 800. Bare merket syntetisk
forespørsel treffes. Dette er et tidsverktøy og håndhever ingen tilgang.

For hver rute er følgende kontrollert:

1. Eierens egen PNG/SRT fungerer før pausen, med SHA eller privat SRT-markør.
2. FileWriter er faktisk Active, ikke TimedOut, og HTTP-kallet er ufullført.
3. B kan fortsatt hente sitt eget bilde og sin egen undertekst under pausen.
4. A-profilsletting fullfører og Deleted leses tilbake mens pausen fortsatt
   er aktiv og svaret ufullført.
5. Etter eksplisitt frigjøring avvises det tidligere godkjente A-svaret med
   HTTP 404, akkurat `Items not found.` (16 byte), ingen entityheadere og
   Content-Length 16. Det returneres ingen PNG/SRT-kropp.
6. Den faktiske produksjonskontrollen rapporterer Installed=true og nøyaktig
   én ny WritesDenied. Avslaget stammer fra produksjonens skriverkontroll.
7. Nye/gamle/fremmede/anonyme og blandede kilde-ID-er kontrolleres etter
   sletting og faktisk omstart; B sine egne ressurser fungerer fortsatt.

## Reproduksjon og evidens

`Test-ProductionMediaAssets.ps1 -WriterRace Image -RequireIsolation`
fullfører 56 observasjoner i
`bin/production-media-assets-image-write-results.json`.

`Test-ProductionMediaAssets.ps1 -WriterRace Subtitle -RequireIsolation`
fullfører 56 observasjoner i
`bin/production-media-assets-subtitle-write-results.json`.

Begge rapporters Completed, pause/deletion-readback, native resultatkontrakt,
generiske avslag og produksjonsteller er kontrollert etter at prosessene
fullførte med exit 0. Native resultatkontrakt er FileWriter i begge løp.
Fixture-bygget passerer uten advarsler/feil. Produksjonskoden krevde ingen ny
rettelse i denne runden; eksisterende felles skriverkontroll stopper begge
konkrete ventende svar.

Sluttkontrollen i `bin/production-asset-write-cleanup.json` er lest tilbake:
syntetiske kontoer, biblioteker, filer og fixture er fjernet, profiler og
journaler er borte og den isolerte serverprosessen er faktisk stoppet.
Umiddelbar ServerStopped=false i den tidligere cleanupen er beholdt separat
fra den senere FinalServerStopped=true.

## Hva dette ikke beviser

Den etterfølgende kontrollen etter tatt eier-sperre er dokumentert separat i
[PRODUCTION-ASSET-TRANSFER-LEASE.md](PRODUCTION-ASSET-TRANSFER-LEASE.md).
Den supplerer, men endrer ikke plasseringen av pausen beskrevet her.

Pausen ligger før produksjonens skriverkontroll og før dens overføringssperre
tas. Dette er ikke en test av sletting etter at denne sperren er tatt, eller
etter at bytes er sendt. HEAD/304/range, andre formater, transformerte/cached
bilder og alternative undertekst-/HLS-ruter er ikke kontrollert her. Faktisk
avledet fil-/cachekilde er ikke bundet/auditert av denne testen. Native
mutasjoner, bruker-/tokenrevokering, lange overføringer og alle klientfamilier
gjenstår. Full skjerming er fortsatt ikke bevist. Ingen utrulling til
hovedserveren er utført i denne runden.
