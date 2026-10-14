# Fysiske kildesteder for virtuell rot

Undersøkt 2026-10-12 på faktisk isolert Emby 4.10.1.0. `Inspect-NativeRootLocations.ps1` bruker en administrasjonsprobe begrenset til den syntetiske A-roten. Hovedserveren er ikke endret.

## Faktisk serverkontrakt

Den native roten er `MediaBrowser.Controller.Entities.CollectionFolder`. Dens `Path` er ikke lik prøvevideoens kontrollerte mediemappe. Den prøvde offentlige `PhysicalLocations`-egenskapen og parameterløse `GetPhysicalLocations`-metoden finnes ikke på denne runtime-typen.

Den faktisk innlastede bibliotektjenesten har derimot `GetVirtualFolders()`. Den returnerte nøyaktig én `VirtualFolderInfo` med samme interne ItemId som roten, og dens Locations inneholdt den kontrollerte mediemappen. Proben kaller den faktiske SDK-/servermetoden; dette er ikke utledning fra biblioteknavnet eller klientens query.

Rapport: `bin/native-root-locations-results.json`, Completed=true og NativeConfiguredLocationsMatchControlledMedia=true. RootPathEqualsControlledMedia=false. Det første egenskapsforsøket er bevart separat som `bin/native-root-locations-property-only.json`. Et innledende sammendragsutskrift brukte Select-Object direkte på en hashtable og viste null; lagret JSON og senere avlesning viste de faktiske feltene. Skriptutskriften er rettet til PSCustomObject.

## Produksjonsavgjørelse og integrasjon

`PersonalYouTubePublicationJournal.DecideSources` vurderer nå alle faktiske serverkildesteder. Et privat Preparing-kildested eller en uregistrert sti under den interne medienamespace gir avslag også når rotens egen native sti er offentlig/et annet sted. To forskjellige private reservasjoner i samme kildeliste avvises; en tillatt første sti kan ikke skjule en nektet senere sti. `DecideItem` beholder sin gamle signatur og delegerer til den nye metoden for én sti.

Den eksperimentelle native broen henter Locations fra `ILibraryManager.GetVirtualFolders()` for kandidatens faktiske rot/forfedre og sender dem sammen med elementets egen Path. Ingen forespørselsparameter brukes som kildested.

Seks nye komponentkontroller passerer: Preparing-kilde med separat virtuell sti i begge rekkefølger, positiv Active-rot med eget konfigurert kildested, uregistrert annen privat sti, og to motstridende aktive private kilder i begge rekkefølger. Komponentrapporten har nå 118 kontroller, Completed=true og TestDataGone=true.

`Test-ProductionNativeBindings.ps1 -PublicationJournal` ble kjørt på nytt med den nye kildestedsavgjørelsen. Alle 86 observasjoner passerte, inkludert Preparing-omstart, aktivering og senere profilsletting/omstart/gjenoppretting. Dette er fortsatt en regresjon mot allerede eksisterende native elementer, hvis kildemapper ligger utenfor journalens interne media-namespace. Den første opprettingen før registerbinding er ikke en del av denne kjøringen.

## Åpent rotvindu

Funnet gir en konkret måte å få serverens konfigurerte kildesteder inn i avgjørelsen. Det beviser ikke når disse stedene blir synlige under selve AddVirtualFolder, om alle innganger får den samme konteksten, eller at en ny uregistrert virtuell rot aldri kan utleveres før konfigurasjonen kan leses. Neste kontroll må reservere journalens interne sti før faktisk native oppretting og måle både metadata/utlevering og native/config-tilstand før rotbindingen legges inn. Produksjonens universelle inngangsgrense og publiseringskjede er fortsatt ikke implementert.

[NEW-UNREGISTERED-NATIVE-ROOT.md](NEW-UNREGISTERED-NATIVE-ROOT.md) har senere kontrollert en faktisk ny rot fra den reserverte interne stien uten ID-binding, etter native-kallets retur og etter omstart. Samme rot fikk positiv A-kontroll først etter registrering og aktivering; B forble nektet. 27 observasjoner passerte. Tidsvinduet inne i selve native opprettingskallet består.

Prøvebiblioteker, kontoer og filer ble ryddet etter hver isolerte kjøring. Uavhengig sluttkontroll bekrefter stoppet server, fjernet fixturejournal og fravær av produksjonens profilmapppe. Full skjerming er fortsatt ikke bevist.
