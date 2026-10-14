# Samordning av profilsletting og pågående listerespons

Isolert Emby 4.10.1.0, 12. oktober 2026. Ingen utrulling til hovedserveren.

## Påvist tidsvindu

`Test-ProductionItemLists.ps1 -AfterWriteCheckRace` fullførte 41 observasjoner. Timing-prefixen kjørte med prioritet 100, etter produksjonens skrivekontroll med prioritet 800, på faktisk native WriteToAsync. Mens skriveren var pauset, fullførte A sin profilsletting og Deleted ble lest tilbake. Etter frigivelse ga den gamle listen 200, total=1 og privat videonavn. `bin/production-item-list-after-write-check-race-results.json` viser IsolationPass=false. En ny kontroll alene flyttet altså tidsvinduet.

## Produksjonsendring

PersonalYouTubeTransferLease bruker en SemaphoreSlim per normalisert profilmappe og eier-GUID, delt mellom alle store-instanser i samme prosess. Save/Delete tar eierens sperre før profilens eksisterende fillås. En scoped native skriver tar samme sperre før sin siste tilgangskontroll og holder den gjennom hele Task-en fra WriteToAsync. Postfixen pakker task-en med frigjøring i finally; finalizeren frigjør ved synkront unntak. Dispose er idempotent. Prefix, postfix og finalizer inngår i faktisk patch-verifisering.

Dette gir en bestemt rekkefølge: En profilendring som allerede har vunnet sperren, blir synlig for senere skrivekontroll og kan avvise svaret. En godkjent skriver som allerede holder sperren, får fullføre før profilendringen kan lagres og bekreftes. Sletting blir dermed ventende i stedet for å bekrefte Deleted midt i denne skrivetasken. Andre eiere deler ikke eierens sperre. Ingen thread-affine monitor holdes over await.

Dette innebærer ikke at klienten må ha mottatt alle nettverkspakker før slettesvaret kommer. Grensen er serverens native skrivetask; allerede utleverte/bufrede svar er ikke trukket tilbake.

## Verifisert effekt

`-AfterWriteCheckRace -RequireRaceSafe` fullførte 44 observasjoner med begge native brukeres EnableAllFolders=true og eksperimentell fixture-skjerming av. Den faktiske HTTP-slettingen nådde eierens sperre: Held=true, Waiting=1, HTTP fortsatt ventende og persisted State=Draft. B sin liste og en faktisk B-profiloppdatering fungerte under pausen. Etter frigivelse fullførte A sin allerede autoriserte liste med ett eget element; slettingen fullførte deretter ved sperren med persisted Deleted, Held=false og Waiting=0. Alle senere A-lister var tomme, også etter omstart, mens B fortsatte å fungere.

Rapport: `bin/production-item-list-write-lease-results.json`. At den godkjente A-listen har PrivateNamePresent=true er forventet: testen krevde og målte at profilslettingen fortsatt ventet mens serveren holdt skriverens sperre. Dette er ingen godkjenning av private data fra et svar som begynner etter en fullført sletting.

Åtte nye komponentkontroller dekker faktisk kryssinstans-sletting som venter på en ufullført skrivetask, Draft-readback, B-oppdatering, fullføring etter frigivelse, idempotent frigjøring og frigjøring ved faulted/cancelled Task. Komponentkjøringen fullførte 186 kontroller med testdata fjernet. Synkront unntak gjennom selve native Harmony-finalizeren er ennå ikke separat injisert i en HTTP-test.

Skriverinngangsregresjonen `-WriteRace -RequireRaceSafe` fullførte fortsatt 42 observasjoner: faktisk sletting før skrivekontrollen førte til HTTP 404 uten privat navn, og ett produksjonsavslag ved skriving ble målt. Native livsløpsregresjon `-PublicationJournal -ActualAccess` fullførte 235 observasjoner med begge omstarter verifisert; den har fixture-skjerming på og er ikke ytterligere produksjonskrok-alene-bevis.

Opprydding er lest tilbake i `bin/production-item-list-transfer-lease-cleanup.json`: isolert prosess stoppet, native testbrukere/biblioteker/media og profiler/fixture/klientjournal/modus fjernet. Umiddelbar gammel stoppmarkør er bevart separat fra avsluttende prosesskontroll.

## Gjenværende krav

Sperren samordner profilens Save/Delete med denne GetItems-familiens skriver i én serverprosess. Den samordner ikke native innsetting/reparenting, nye bindinger/journalendringer, bruker-/tokenrevokering, eksterne filendringer eller andre utleveringsruter. Langvarig native skriving kan forsinke samme eiers profilendring til task-en fullfører eller avbrytes. Skrivetimeout og disconnect-atferd i alle klienter er ikke verifisert her.

Full skjerming, personlig YouTube-publisering, øvrige serverinnganger og alle klientfamilier er fortsatt ikke bevist.
