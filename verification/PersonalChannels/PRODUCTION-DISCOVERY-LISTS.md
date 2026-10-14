# Bibliotekoversikt og nyeste elementer mellom kontoer

13. oktober 2026. Isolert Windows Emby 4.10.1.0 med to syntetiske native
biblioteker, produksjonsprofiler/bindinger og vanlige A/B-kontoer med brede
native folder-rettigheter. Eksperimentell guard er deaktivert og lest
tilbake. **Full skjerming er fortsatt ikke bevist.**

## Faktisk API-lekkasje

Vanlige GetUserViews og GetLatestMedia-kall viste begge testkontoenes
bibliotek-/videonavn før listefamiliene ble utvidet. Dette var normale
HTTP-kall; ingen interne resultater eller filstier ble injisert.

Den bevarte mellomrapporten
`bin/production-discovery-before-root-filter-results.json` har Completed=true,
26 observasjoner og 12 IsolationPass=false. På dette tidspunktet var Latest
allerede rettet gjennom query-krokene, men Views returnerte fortsatt begge
private biblioteknavn og TotalRecordCount=2, også etter A-profilsletting og
omstart. Å legge Views til request-scopen alene rettet ikke denne lekkasjen.
Query-exclusions dekket ikke det faktiske mappe-arrayet brukt av visningen.

Den første diagnostikkfilen fra løpet med begge lekkasjer ble senere
overskrevet av denne mellomdiagnostikken. Den skal ikke siteres som en
bevart 24-feilrapport. Mellomrapporten over er bevart separat fra ny testing.

## Produksjonsendring

PersonalYouTubeItemListGate håndterer nå GetItems, GetLatestMedia og
GetUserViews. UserId normaliseres fra faktisk autentisert aktør, både for
Guid- og string-egenskapene. Den eksisterende native query-/resultat-/
skriverkontrollen brukes videre, med ny finalizer som rydder request-scope
og gir generisk avslag ved en synkron tjenestefeil.

Den konkrete femparameter-GetUserViews i UserViewManager får i tillegg en
produksjons-prefix. Den filtrerer det faktiske Folder[]-inputet før native
visninger, gruppering, DTO-er og antall bygges. Private fremmede eller
slettede mapper fjernes. Native user-argument settes til faktisk aktør.
Returtype, parameterkontrakt og IL-hash er kontrollert; native hash er
BC63BE59DFC9A0DB61A41FC202EF808C878B13449CA40B825D2F1981D8159CF9.
Snapshot kontrollerer at denne prefixen fortsatt er installert og oppgir
AuditedDtoCount=3 og faktisk ViewSources-teller.

Kildebeviset registrerer nøyaktig den exclusion-snapshoten som ble anvendt
før filtrering. En nyere denial lest etter at en mappe allerede er beholdt,
skal ikke feilaktig kunne merke den som filtrert. QueryCoverage krever nå
en faktisk registrert kildekontroll, og hver registrert kilde må dekke både
opprinnelige og ferske denials. En inventarliste alene teller ikke som bevis.

Dette er en avgrenset revisjon av tre native DTO-er og konkrete query-/
view-innganger. Det er ikke en universell kontroll av alle resultatkilder.

## Verifisering

Test-ProductionDiscoveryLists.ps1 kontrollerer begge aktører, eget og
forfalsket UserId, korrekt eget innhold og antall, fremmede navn og kjente
native referanser, faktisk profilsletting og faktisk omstart. Views testes
med IncludeHidden=true og IncludeExternalContent=false, med og uten
AllowDynamicChildren. Latest bruker Video, GroupItems=false og Limit=100.

Beskyttede løp krever også faktisk service-scope-teller og view-/query-
kildeteller. En tom Latest-liste etter sletting kan lovlig ha null query-
kall: det faktiske filtrerte mappe-arrayet er da tomt, og ViewSources må
likevel være nådd. En tom liste uten noen kontrollert kilde godkjennes ikke.

Før-kontroll-racene pauses ved faktisk native StreamWriter, og A-sletting
lagres før skriveren frigis. Svaret må være generisk HTTP 404 med 16-byte
`Items not found.`, uten entityheadere; WritesDenied øker nøyaktig én gang.
Etter-kontroll-racene krever en faktisk ventende sletting ved eierens sperre,
B sin uavhengige profiloppdatering, korrekt godkjent A-svar og lagret sletting
etter frigjøring. Ingen sperre/venter skal være igjen.

De opprinnelige GetItems-count/page-kontrollene fullfører 37 observasjoner i
`bin/production-item-list-results.json` etter endringen. Den separate
produksjonsmodellen fullfører 188 kontroller, inkludert avvisning uten en
filtrert kilde og krav om at opprinnelige denials også dekkes når listen over
ferske denials er tom. Bygg av produksjon og fixture har ingen advarsler/feil.

## Gjenstående krav

De seks lagrede discovery-rapportene fra denne revisjonen har Completed=true
og ingen registrerte IsolationPass=false: standard 26, dynamiske views 26,
Views før skriverkontroll 30, Latest før skriverkontroll 30, Views etter
skriverkontroll 31 og Latest etter skriverkontroll 31. Dette er 174
avgrensede observasjoner, ikke et bevis for alle Emby-ruter eller klienter.
Rapportene ligger under bin/production-discovery-*.json. Views før
skriverkontroll ble kjørt før verifieren fikk rekursiv kontroll av kjente
private referanser; navn, antall, kildekontroller og skriverutfall var kontrollert.

Andre liste-/søke-/genre-/resume-/suggestion-innganger, øvrige views-parametre
og sammensatte/grouped kilder, alle nested counts og metadatafelt, native
innsetting/reparenting og andre samtidighetsgrenser er ikke bevist her.
Eksakte normale app-kall og alle klientfamilier må fortsatt kontrolleres.
Bruker-/tokenrevokering, sync/offline, sockets/DLNA, øvrige ressursinnganger,
cacheinnhold og faktisk personlig YouTube-henting/publisering gjenstår også.
Windows 4.10.1.0-evidens beviser ikke Docker-/Linux-builds eller oppførsel
etter serveroppgraderinger. Ingen utrulling til hovedserveren er gjort.
