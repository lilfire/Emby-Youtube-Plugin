# Profilsletting etter ferdig native listeresultat

Kontrollert på isolert Emby 4.10.1.0 den 12. oktober 2026. Ingen utrulling til hovedserveren.

## Påvist brudd

`Test-ProductionItemLists.ps1 -ResultRace` fullførte 42 observasjoner. Fixture-kroken pauset produksjonens AfterService før resultatinnpakningen, etter at native Task<object> var fullført. Resultatet var en native StreamWriter. Ingen resultatverdier ble endret av timingkroken.

Mens A sitt HTTP-kall fortsatt ventet, fungerte B sin liste. A sin profil ble slettet gjennom produksjonsruten, Deleted lest tilbake og fortsatt aktiv pause kontrollert. Etter frigivelsen kom HTTP 200, total=1, ett element og A sitt private videonavn. `bin/production-item-list-result-race-results.json` har IsolationPass=false; Completed=true betyr at eksperimentet fullførte.

## Produksjonsendring

Hver scoped native query registrerer hvilke ID-er den faktisk ekskluderte. PersonalYouTubeQueryCoverage beholder snittet av disse settene, med lås for samtidige queries. En senere query som ekskluderer en nylig nektet ID kan dermed ikke godkjenne et eldre resultat fra en tidligere query som tillot den.

Når tjenestens native task er ferdig, leser produksjonens Finish registrerte sperrer på nytt. Hvis noen aktuell sperre ikke var dekket av alle queries, forkastes hele resultatet med generisk 404. Lagringsfeil gir samme avslag. Dette omskriver ikke ferdige elementer eller tellinger. Uten registrerte queries brukes det opprinnelige sperresettet konservativt.

Ni nye komponentkontroller dekker sen sperre, snitt fremfor union, flere queries, ingen query og samtidige registreringer. Komponentkjøringen fullførte 178 kontroller med testdata fjernet.

## Verifisert effekt og begrensning

`Test-ProductionItemLists.ps1 -ResultRace -RequireRaceSafe` fullførte 42 observasjoner. Samme tidligere lekkende forespørsel fikk 404 uten privat navn. B sine lister fungerte under pausen, etter slettingen og etter omstart. Begge native brukere hadde EnableAllFolders=true, og eksperimentell fixture-skjerming var av.

Rapport: `bin/production-item-list-result-protected-results.json`. Testen er gjentatt etter skriveinngangskontrollen og fullførte fortsatt 42 observasjoner med HTTP 404 uten privat navn. Size ved feilrespons er nå korrekt rapportert som null listeelementer; et tidligere rapporteringsforsøk telte PowerShell-null som ett arrayelement.

Den tidligere pre-query-racen ble gjentatt med `-InventoryRace -RequireRaceSafe`: 41 observasjoner fullførte, gammel A-forespørsel ga 200 med total=0 og null elementer. Native livsløpsregresjon `Test-ProductionNativeBindings.ps1 -PublicationJournal -ActualAccess` fullførte 235 observasjoner med begge omstarter verifisert. Denne regresjonen har fixture-skjerming på og er ikke ytterligere produksjonskrok-alene-bevis.

Opprydding er lest tilbake i `bin/production-item-list-result-cleanup.json`: isolert prosess stoppet, testbrukere/biblioteker/media og profiler/fixture/journal/modus fjernet. Den tidligere umiddelbare stoppmarkøren beholdes separat fra den avsluttende prosesskontrollen.

Kontrollen ligger før resultatet returneres til HTTP-kjeden. Endringer etter denne kontrollen under StreamWriter/serialisering/byteutlevering er fortsatt ikke dekket. Nye uregistrerte native elementer etter inventaret, bruker-/tokenrevokering, andre listefamilier og øvrige serverinnganger står også åpne. Dette er ingen universell skjermingsgaranti.
