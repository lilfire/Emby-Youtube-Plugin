# Forslag: egen produksjonskontroll

Undersøkt 2026-10-13 på isolert Windows Emby 4.10.1.0. Hovedserveren
er ikke endret. Full skjerming og støtte i alle klienter er fortsatt ubevist.

## Direkte funn

`Users/{UserId}/Suggestions?IncludeItemTypes=Video&Limit=100` viste begge
private prøvevideoer til begge vanlige kontoer. Begge hadde brede native
mapperettigheter. Den eksperimentelle fixture-beskyttelsen var deaktivert;
produksjonskontrollene var installert. Dette var ordinære HTTP-kall uten
intern kilde- eller resultatinjeksjon.

`bin/production-discovery-suggestions-diagnostic-results.json` er bevart:
Completed=true, 14 observasjoner, hvorav 12 listekall ikke bestod skjerming.
Alle listekall returnerte HTTP 200, begge navn og TotalRecordCount=2.
Dette gjaldt eget og en annen brukers UserId, før og etter lagret sletting
av A sin profil og etter faktisk serveromstart. Service-/query-tellerne for
produksjonens listekontroll økte ikke for disse kallene.

## Rettelse og avgrensning

PersonalYouTubeItemListGate inkluderer nå den faktiske DTO-en
`Emby.Api.GetSuggestedItems`. Den innleste native ruteinventarfilen viser
at UserId er System.Guid, som for GetItems. Den kontrakten kontrolleres
eksplisitt ved installasjon. Faktisk autentisert bruker normaliserer UserId.
Eksisterende native query-filtrering skjer før resultat/count bygges;
resultat- og skriverkontrollen krever registrert kildebevis og aktuelle
eierbegrensninger. De tidligere tre DTO-ene beholder sine kontroller.

Denne native ruten returnerer QueryResult<BaseItemDto>, ikke en ferdig
StreamWriter. Første aktive egenkontroll avdekket HTTP 404 fra RegisterWriter
selv om query-kontrollen var nådd. Den testen teller ikke som bestått.
Scope bevarer nå den faktiske IRequest og markerer akkurat Suggestions-DTO-en.
Dens typede resultat går gjennom native IHttpResultFactory.GetResult før
registrering ved den felles skriverkontrollen. Andre resultattyper gis
ingen generell omgåelse; ukjente skriverkontrakter avvises fortsatt.

Første rettelsesbygg antok feilaktig string-UserId for den nye DTO-en.
Den isolerte testen stoppet på installasjonskontrollen før noen skjermings-
observasjon; dette løpet teller ikke som verifisert. Native inventar ble
lest, Guid-kontrakten rettet, og fixture/produksjon bygget uten feil/advarsler.

Test-ProductionDiscoveryLists.ps1 har en separat Suggestions-familie.
Eget aktive innhold må faktisk returneres, fremmede/slettede navn og kjente
private referanser skal mangle, og både antall og faktiske service-/
query-kontroller må stemme. Tomme svar alene godkjennes ikke som fungerende
eiersamling. Skriverløp bruker faktisk native StreamWriter og eksisterende
timing-fixture; de er ikke rute- eller DTO-injeksjon.

## Gjenstående krav

Beskyttet løp med sletting før skriverkontroll fullførte 18 observasjoner:
`bin/production-discovery-suggestions-protected-suggestions-write-revocation-results.json`.
Løpet etter godkjent skriverkontroll fullførte 19 observasjoner:
`bin/production-discovery-suggestions-protected-suggestions-write-lease-results.json`.
Begge har Completed=true og ingen IsolationPass=false. De 12 listekallene
i hvert løp nådde én faktisk service-scope og to native query-kontroller.
Aktiv egen konto fikk ett eget element; slettet A fikk null, og B beholdt
ett eget element, også etter omstart og med den andre brukerens UserId.
Før-kontroll-svaret ble HTTP 404 / 16-byte generisk avslag, uten entityheadere;
WritesDenied økte én gang. Etter-kontroll-løpet lot A-sletting vente ved
eierens skriverlås mens B oppdaterte sin profil, før korrekt A-svar og
fullført sletting. Ingen eierlås eller ventende sletting stod igjen.

Regresjonsløpet for Views/Latest med Views før skriverkontroll fullførte
30 observasjoner på samme produksjonsbygg, nå med rekursiv kontroll av
kjente private referanser. Produksjonsmodellens 188 kontroller bestod også.
Den opprinnelige GetItems-regresjonen fullførte 37 observasjoner på samme
bygg. Sluttkontroll i `bin/production-suggestions-cleanup.json` er lest
tilbake: testkontoer/biblioteker/media og fixture er fjernet, personlige
testprofiler og oppsettsjournal mangler, serveren er stoppet, og installert
produksjons-DLL har samme SHA-256 som det verifiserte bygget.

Andre forslagparametre, paging/rangering, blanding med offentlige samlinger,
native endringer av innhold og klientenes faktiske forespørsler er ikke
bevist av denne matrisen. Resume, metadataindekser/genres/counts og øvrige
oppdagelsesveier trenger egne native kildekontroller og positive kontroller.
Det samme gjelder resten av hovedplanen, inkludert personlig YouTube-henting,
avspilling i alle klienter, tokenrevokering og eksakte Docker-/Linux-builds.
