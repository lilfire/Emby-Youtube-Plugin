# Native klargjøring og privat rotsletting ved bekreftet overlapp

12. oktober 2026, isolert Emby 4.10.1.0. To vanlige kontoer og
syntetiske lokale Original-videoer; produksjonspluginen og hovedserveren
er ikke endret.

`Test-NativeSyncPrepareRace.ps1` bestod med 26 observasjoner:
22 HTTP-resultater og fire native retention-readbacks.

## Faktisk kontrollert overlapp

Den timing-only NativeSyncWriteGate pauser bare UpdateSyncJobItemInternal
for den forhåndsvaliderte private A-videoen når det faktiske argumentet
har Status=ReadyToTransfer og OutputPath peker på den eksisterende
syntetiske kildefilen. Den endrer ikke status, path eller native rader.
Pausen har automatisk frigjøring etter 25 sekunder og betrodd admin-
frigjøring. Gate-låsen holdes ikke under ventingen.

B sin komplette egen fil ble først hentet med 200 og riktig SHA-256.
Deretter ble A-jobben opprettet asynkront. Runtime-måling viste at
denne installerte versjonen klargjør Original i POST Sync/Jobs før
opprettelsessvaret returneres; en synkron klient som venter på svaret
mens den pauser skrivingen kan ikke observere/frigjøre sin egen pause.

Gate Reached/Active, fil-eksistens og korrekt kildepath ble bekreftet
før adminsletting. De native jobb-/element-ID-ene ble hentet fra den
faktiske pausen og journalført for opprydding. Admin utførte native
Library/VirtualFolders/Delete uten eierbytte. SDK-prober bekreftet
at både rot og kildevideo var borte mens gate fremdeles var Active
og ikke TimedOut. SHA-256 av eierskapskonfigurasjonen var uendret.

Dette er sletting fullført inne i en bekreftet native skrivepause,
ikke bare to HTTP-kall sendt omtrent samtidig. Etter eksplisitt
frigjøring sluttet pausen uten timeout. Opprettelseskallet returnerte
200 etter frigjøring, selv om den opprinnelige samlingen var slettet.
Native manager viste senere ingen gjenværende A-jobb/element.

## Tilgang og retention etter frigjøring og omstart

B, den eksisterende A-kontoen og anonym klient fikk 404 på gamle
A-jobb-, jobitem-query- og filreferanser i begge faser (18 avslag).
Alle seks avslåtte filkall hadde 0 rå payload-bytes.

B fikk fortsatt egen komplette fil med 200 og korrekt SHA-256
etter frigjøring og etter omstart. Det er tre komplette B-filer
totalt, inkludert kontrollen før overlappen.

Native GetJob og direkte GetJobItem viste A-jobben og den konkrete
gamle raden borte både etter overlappen og etter omstart. Guard var
Enabled/Ready med ny BootId. Legitim native sync-feature Allowed=true
ble observert før omstart; ingen lisensomgåelse ble brukt.

Rapport: `bin/native-sync-prepare-root-race-results.json`, med
Completed=true, DeletionInsideConfirmedNativePause=true og
LegitimateSyncFeatureObservedBeforeRestart=true. InitialGate viser
relevant aktiv pause; GateFinal viser Released=true, Active=false,
TimedOut=false og korrekt eksisterende fixture-output.

## Bevarte, ufullførte forsøk

Første synkrone opprettelse tidsavbrøt. Fasemåling i neste forsøk
identifiserte POST Sync/Jobs som det ventende kallet. Disse er bevart
som `native-sync-prepare-root-race-first-incomplete.json` og
`native-sync-prepare-root-race-create-wait-incomplete.json`.

Det første asynkrone forsøket fullførte overlapp og tilgangskontroller,
men kontrollerte feature-observasjoner etter restart, da minnelisten
var tømt. Det regnes ikke som bestått og er bevart i
`native-sync-prepare-root-race-feature-after-restart-incomplete.json`.
Den endelige kjøringen måler feature før restart.

## Praktiske begrensninger

Dette dekker ett konkret skrivepunkt, én Original-kilde og én native
versjon. Det beviser ikke alle tidsvinduer, konverteringsprofiler,
prosessavbrudd eller nyoppretting med ID-gjenbruk. A-filen ble ikke
hentet gjennom Ready-API før sletting i denne kjøringen; pausen var
før native Ready-lagring, med faktisk valgt/eksisterende lokal output.

Ingen orphan/Ready-ressurs ble faktisk beholdt etter dette overlappet.
Resultatet må derfor ikke omtales som et tilgangsbevis for en beholdt
Sync-rad. Gjenværende LiveStream-metadata er testet separat, og dette
erstatter ikke transportbyte- eller alle-klienter-bevis for YouTube.
Full skjerming er fortsatt ikke bevist.

Testbrukere/biblioteker/Sync-jobber og medier er ryddet; fixture,
guard, registre/tempfiler og journal er borte og serveren stoppet.
Alle felter i `bin/native-sync-prepare-root-race-cleanup.json` er true.
