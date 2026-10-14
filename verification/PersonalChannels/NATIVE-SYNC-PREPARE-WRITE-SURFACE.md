# Faktisk native kontrollpunkt for klargjøring/sletting-overlapp

12. oktober 2026, isolert Emby 4.10.1.0. Denne undersøkelsen leser
metoder/IL-referanser fra de faktisk lastede native assemblyene.
Ingen samtidig klargjøring/sletting-test er kjørt i denne undersøkelsen.
Produksjonspluginen og hovedserveren er ikke endret.

## Nye runtime-observasjoner

`SyncJobProcessor.ProcessJobItem` sin faktisk lastede async MoveNext
oppretter SyncJobItemCanceledHandler før den kaller SyncVideo, og gir
SyncVideo håndtererens ChainedToken. Etter videoklargjøring finnes et
kall til OnItemReadyToTransfer. Dette dokumenterer at en native
kanselleringsmekanisme finnes, ikke at den dekker alle overlapp eller
sørger for atomisk kilde-/status-/databasetilstand.

`SetJobItemStatus` setter Status, kaller SyncManager.UpdateSyncJobItemInternal
og kan deretter oppdatere jobbstatus. Men SyncVideo sin faktisk lastede
MoveNext inneholder også direkte Status-settere og direkte UpdateSyncJobItemInternal-
kall. Filsti-settere forekommer før flere av disse lagringskallene.
Et teststopp bare i SetJobItemStatus dekker derfor ikke nødvendigvis
den relevante klargjøringsbanen.

UpdateSyncJobItemInternal kaller SyncRepository.Update(SyncJobItem).
Det er dermed et konkret runtime-kontrollpunkt før repository-lagring,
og det kan velges ut fra faktisk argument.Status=ReadyToTransfer,
argumentets forventede private ItemId og valgt lokal OutputPath.
Metodereferansene alene beviser ikke hvilket av SyncVideo sine
betingede løp Original-profilen tar; det må måles ved neste kjøring.

## Evidens

`bin/native-sync-race-method-surface.json` inneholder første ferske
runtime-inventar. `bin/native-sync-race-write-surface.json` inneholder
den utvidede gjennomgangen med SyncVideo sin async state machine,
SetJobItemStatus og UpdateSyncJobItemInternal. Bare typenavn, signaturer,
referanser og enum-metadata er brukt; ingen nøkler eller instansverdier
er publisert fra innholdet.

Fixture-inspektøren ble utvidet til disse konkrete metodene. Build
bestod med null advarsler/feil. Dette er en testdiagnostikk-endring;
det er ikke en ny produksjons-sikkerhetsgrense.

## Neste nødvendige kontroll

En avgrenset isolert probe bør pause akkurat ett klargjøringskall ved
UpdateSyncJobItemInternal når den forventede A-kilden har faktisk
ReadyToTransfer-status og en eksisterende syntetisk lokal OutputPath.
Pause må bekreftes i runtime før rotsletting, og ha tidsbegrensning og
trygg frigjøring. Probe skal ikke endre status, filsti eller lagre
kunstige native jobb-/elementrader.

Etter native rotsletting under pausen og frigjøring må faktisk
GetJob/GetJobItem-retention måles, og gamle fil-/listekall for A/B/
anonym kontrolleres med rå bytes. B sin egen fil må fortsatt være
komplett og hash-korrekt. Hvis sletting serialiseres til etter at
pausen er over, er det ikke den tilsiktede overlappen og skal ikke
regnes som et samtidighetsbevis.

Native kansellering, repository Update og fravær i tidligere sekvensielle
tester er foreløpig utilstrekkelig bevis for denne tilstanden. Full
skjerming er fortsatt ikke bevist.

Oppfølging: dette kontrollpunktet er nå faktisk brukt i en timing-only
probe for én Original-kilde, med native rotsletting bekreftet inne i
pausen. 26 observasjoner bestod; A-jobb/element ble ikke beholdt.
Se [NATIVE-SYNC-PREPARE-ROOT-RACE.md](NATIVE-SYNC-PREPARE-ROOT-RACE.md)
for konkret overlappsevidens, ufullførte forsøk og begrensninger.

Begge inspeksjonskjøringers fixture ble ryddet. Testbrukere/biblioteker,
medier, plugin/guard, registre/tempfiler og journal er borte, og serveren
stoppet. Alle felter i `bin/native-sync-race-inspection-cleanup.json`
er true.
