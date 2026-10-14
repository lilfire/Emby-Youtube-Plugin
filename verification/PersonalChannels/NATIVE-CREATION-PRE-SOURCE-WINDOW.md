# Native oppretting før kildestier er lagret

Undersøkt på isolert Emby 4.10.1.0 den 12. oktober 2026. Hovedserveren er ikke endret.

## Faktisk hull

En administrasjonsprobe leser IL fra den faktisk lastede LibraryManager-implementasjonen. Rapporten `bin/native-creation-il.json` viser at AddVirtualFolder kaller CreateItem ved offset 257, SaveLibraryOptions ved 269 og AddMediaPaths ved 278. Dette er serverens faktiske kallrekkefølge, ikke en antakelse ut fra SDK-signaturen.

Den isolerte NativeCreationGate pauser etter CreateItem for den eksakt forhåndsregistrerte syntetiske JournalPending-roten. Kallet får maksimalt 25 sekunder og endrer ingen native verdier. Ved pause bekreftet vi at GetItemById finner roten, at Locations er tom, og at opprettingsforespørselen fortsatt er uferdig. A og B fikk roten lagt i EnabledFolders og policyene ble lest tilbake. Dette fjerner kanal- og bibliotekbegrensninger som forklaring på et avslag i denne testen.

`Test-NewUnregisteredPrivateRoot.ps1 -InFlight` fullførte 34 observasjoner. Begge brukerne fikk 200 og privat rotnavn på metadataoppslag med både numerisk ID og GUID mens opprettingen var pauset. Biblioteklistene skjulte roten. Etter at kallet returnerte, var de direkte oppslagene 404, også etter faktisk omstart. Completed=true betyr at eksperimentet fullførte; de fire IsolationPass=false er **påviste brudd**, ikke beståtte skjermingskontroller. Rapporten er bevart som `bin/new-root-in-flight-results.json`.

## Produksjonskomponent og ny isolert kontroll

PersonalYouTubePublicationJournal har nå ReserveRootIdentity(snapshot, rootGuid). Den krever en eksisterende Preparing-post og gjeldende profilsnapshot og lagrer ReservedRootId varig før native synlighet. Tom identitet, identitetsbytte, annen generations reservasjon og allerede bundet identitet avvises. Aktivering må bruke samme GUID. DecideSources nekter en reservert Preparing-identitet, og dens faktiske native etterkommere, selv når kildestiene ennå ikke finnes. Reservasjonen beholdes ved aktivering og generationsendringer.

Fixture-koblingen reserverer GUID i prefix til faktisk CreateItem, før native databaseoppretting, og pauser deretter i postfix. Dette er fortsatt en eksperimentell kobling. Den bruker en strengt avgrenset syntetisk testkontekst; en produksjonspubliserer må ha en betrodd opprettingskontekst og avbryte native oppretting hvis reservasjonen feiler. Biblioteknavn eller klientparametere alene skal ikke autorisere reservasjonen.

`Test-NewUnregisteredPrivateRoot.ps1 -InFlight -ReserveIdentity` kontrollerer den varige GUID-en mot faktisk native rot mens kallet er pauset, og krever 404 uten privat navn for begge brukernes fire metadataoppslag. Begge biblioteklister må skjule roten. Etter retur/omstart beholdes avslag; etter binding beholdes Preparing-avslag; etter aktivering fungerer samme rot for A, mens B nektes. B sitt eksisterende videoinnhold er positiv kontroll med identisk filhash. Endelig rapport: `bin/new-root-in-flight-protected-results.json`.

Den endelige beskyttede kjøringen fullførte 35 observasjoner, med seks beståtte tilgangskontroller i pausen og faktisk omstart. Opprydding er lest tilbake i `bin/new-root-in-flight-cleanup.json`: server stoppet, fixture-DLL, testjournal, profiler og produksjonsmodus fjernet.

Tolv nye komponentkontroller dekker identitetsreservasjon, avslag uten kildestier, etterkommer, ny store-instans, kollisjon, feil aktiveringsrot og slettet snapshot. Samlet komponentkjøring har 130 kontroller, Completed=true og TestDataGone=true.

## Gjenstående arbeid

Dette lukker det demonstrerte vinduet i den isolerte fixture-koblingen. Produksjonspluginen har ennå ingen universell native tilgangskobling eller personlig bibliotekpubliserer. Full skjerming er fortsatt ikke bevist. Andre native innganger, samtidige opprettinger, krasj/publiseringsgjenoppretting, synkroniseringsfiler og strømreferanser samt faktisk YouTube-avspilling i klientfamiliene inngår fortsatt i planen.
