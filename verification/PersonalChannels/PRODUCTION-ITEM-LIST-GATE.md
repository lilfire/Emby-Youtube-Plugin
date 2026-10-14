# Produksjonssperre før native itemtelling og paging

Implementert og isolert kontrollert 12. oktober 2026 på Emby 4.10.1.0. Hovedserveren er urørt.

## Faktiske kroker

NativeBoundaryInspection undersøker nå også LibraryManager-spørringer. `bin/native-boundary-inventory.json` har de faktiske signaturene og SHA-256-fingeravtrykkene for fire GetItemList-overloader, GetItemIds og tre GetItemsResult-overloader. Produksjonens PersonalYouTubeItemListGate krever alle åtte metodekropper og den tidligere verifiserte ServiceController.Execute-kroppen før installasjon.

Oppstarten kontrollerer egen prefix på alle åtte metoder og prefix/postfix på serviceutføringen. Snapshot leser også faktisk Harmony-installasjon og gir PatchLost ved bortfall. PluginEntryPoint logger installasjonsstatus eller generisk kontraktfeil. Dette er fremdeles ikke full garanti ved bortfall på en server med allerede publiserte private biblioteker.

## Produksjonsavgjørelse

For den eksplisitte native GetItems-DTO-en, som betjener /Items og /Users/{UserId}/Items, hentes faktisk autentisert bruker. Innlevert UserId normaliseres til denne brukerens GUID. Et native inventar vurderes med produksjonens NativeAccess før service-/databasetransaksjonen starter, og Denied-ID-er inngår i forespørselens eksklusjonssett.

En AsyncLocal-kontekst fører faktisk bruker og eksklusjonssett gjennom native query-kjeden. Query-prefixene setter User og samler ExcludeItemIds før native telling og paging. Det er ikke en etterfølgende fjerning av poster fra den ferdige siden. Det interne inventaret har en separat recursion guard for å unngå å filtrere sin egen rå lesing. Servicepostfixen gjenoppretter tidligere kontekst og markerer den avsluttet når resultattasken er ferdig. En native query som arver en avsluttet kontekst nektes i kode; dette siste er ennå ikke verifisert med en separat forsinket native task-test.

Dette er et forespørselstids-snapshot. Samtidig oppretting, sletting eller revokering etter inventaret kan gjøre settet foreldet. Denne racen er ikke løst av den nye kroken og skal fortsatt behandles som et åpent fullskjermingskrav. Inventar/oppløsning per forespørsel trenger også vurdering mot realistisk bibliotekstørrelse før produksjonsbruk.

## Native baseline og faktisk kontroll

Det første listeforsøket forventet TotalRecordCount=1 på en tom side etter ett tilgjengelig element, men målte 0. Den ufullførte rapporten er bevart som `bin/production-item-list-empty-count-incomplete.json`.

For å avklare dette fjernet en administrasjonsbegrenset testprobe bare produksjonens listepatcher med deres egen Harmony-ID, før personlige profiler/bindinger fantes. Den eksperimentelle skjermingen var også avslått. Native bibliotekpolicy ga A tilgang til egen rot. Den faktiske native komplette listen hadde total=1 og én egen video, mens den tomme siden ved StartIndex=1 hadde total=0. Snapshot viste faktisk PatchLost under denne baselinen. Serveromstart gjenopprettet de kontraktverifiserte produksjonskrokene. Testen sammenligner nå tom side med denne målte native semantikken, fremfor å endre testkravet uten evidens eller oppfinne en annen API-semantikk.

Deretter opprettes produksjonsprofiler og native bindinger for ordinære A/B-kontoer. **Begge får EnableAllFolders=true**, og policyene leses tilbake. Native bibliotekbegrensning kan derfor ikke forklare det senere fraværet av fremmed video. Fixture PrivacyGuard slås av og avleses før listekontrollene, også etter omstart.

`Test-ProductionItemLists.ps1` fullførte 37 observasjoner i `bin/production-item-list-results.json`:

- Komplett liste, første side og tom neste side følger egen synlig datamengde/native countsemantikk uten fremmed navn.
- Falsk UserId i query og i /Users/{UserId}/Items gir den faktiske brukerens resultat, ikke den påståtte brukerens.
- A mister sin private video ved profilsletting, mens B fortsatt har korrekt egen side og telling.
- De samme kontrollene passerer etter faktisk serveromstart med fixture-skjermingen avslått.
- Produksjonens scope/query-prefixer registrerer ti forespørsler og ti query-kall i siste oppstartsfase.

Den eksisterende native livsløpsregresjonen med fixture-skjerming på ble også kjørt med de nye krokene installert: `Test-ProductionNativeBindings.ps1 -PublicationJournal -ActualAccess` fullførte 235 observasjoner. Den kjøringen er en regresjon, ikke ytterligere listekrok-alene-bevis. Etterpå ble kun statusreturtypen gjort til en eksplisitt record og oppstartslogging lagt til; ny bygging passerte uten advarsler/feil.

Opprydding er lest tilbake i `bin/production-item-list-cleanup.json`: faktisk server stoppet, native prøvebrukere/biblioteker/filer fjernet, og ingen profiler, fixture-DLL, klientjournal eller modusfil står igjen. Den tidligere umiddelbare stoppmarkøren bevares separat fra den senere prosesskontrollen.

## Gjenstående innganger

GetItems er én listefamilie. GetItemCounts, LatestMedia, UserViews, virtual-folder-lister, metadata-/tagglister, andre API-er, socket/DLNA og fil-/jobb-/strømkjeden trenger egne kontrakter og gjennomgang. Administrator-/server-API-nøkler uten en faktisk User i autentiseringskonteksten er ikke avklart av denne ordinære kontotesten. Personlig produksjonspubliserer, API-jobber/cache, recovery og faktisk YouTube-avspilling/klientfamilier står fortsatt åpne. Full skjerming er ikke bevist.
