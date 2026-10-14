# Native bibliotekantall og personlige samlinger

Undersøkt på isolert Windows Emby 4.10.1.0, 2026-10-13.
Hovedserveren er ikke endret. Full skjerming er fortsatt ubevist.

## Positive kontroller og faktisk lekkasje

Første antallsundersøkelse brukte hjemmevideoer. Alle 18 antallskall ga
null, også for egen prøvevideo. Dette er ikke et positivt skjermingsbevis.
`bin/production-discovery-counts-inspection-diagnostic-results.json`
bevarer dette løpet; CountsInspection-rader har ingen IsolationPass.

Start-NativeClientFixture kan nå lage to isolerte filmbiblioteker med
lokale prøvefiler. Med Movie som faktisk skannet medietype ga samme
Items/Counts-rute MovieCount=2 til begge vanlige kontoer, også etter
lagret sletting av A sin profil og faktisk omstart. Det skjedde også
med de prøvde native numeriske ParentId-ene. Begge kontoene hadde brede
native mapperettigheter; eksperimentell beskyttelse var deaktivert.
Ingen intern kilde-/resultatfeil ble injisert.

Det bevarte før-rettelse-løpet er
`bin/production-counts-movies-before-scope-results.json`: Completed=true,
32 observasjoner, hvorav 18 antallsdiagnoser med MovieCount=2 og null
produksjons-request-/query-tellerøkning. «isolation failures=0» fra den
generelle discovery-harnessens sluttlinje gjelder ikke antallsdiagnosene;
de mangler med hensikt pass/fail og er ikke godkjent skjerming.

## Native kilde og produksjonsendring

Admin-fixtureens read-only IL-inspeksjon har en separat counts-valgmodus.
`bin/native-counts-processing-inspection.json` viser LibraryService.Get
og GetCount. GetCount lager InternalItemsQuery med relevant medietype,
Limit=0 og Recursive=true, bruker Folder.GetItems og leser TotalRecordCount.
Det bekrefter hvorfor en ordinær elementliste og null hjemmevideotelling
ikke alene verifiserer denne ruten.

Produksjonens listekontroll inkluderer nå DTO nummer fem:
Emby.Api.Library.GetItemCounts, med native UserId av type string.
Faktisk autentisert bruker normaliserer UserId. Eksisterende query-kontroll
filtrerer før telling, resultatkontroll krever brukt kildebevis, og native
skriveren bruker samme aktuelle kontroll og eierlås som de andre listene.
ParentId som peker på en fremmed eller slettet privat binding avvises før
native telling. Dette gir en egen CountParentsDenied-teller.

Installering krever også de undersøkte native Get/GetCount-hashene:
729899A945BB781FF40674A0C908941941FB4D23A646F4BFFC63EAA86FF2B4C7 og
697454884000CCDA0FBFDEBF3FB0129B139C73E6CD481C135F977028C4A7BAD4.
Dette avgrenser kontrakten til undersøkt build; det beviser ikke skjerming
ved en ustøttet serverbuild eller hvis private samlinger finnes uten
en fungerende kontroll.

## Verifierens krav

Test-ProductionDiscoveryLists har en egen Counts-familie med Movie-kontroll.
Matrisen bruker begge vanlige kontoer, eget/annen/utelatt UserId, global
telling og begge bibliotekenes numeriske ID og GUID. Anonyme kall inngår.
Samme matrise kjøres aktiv, etter lagret A-sletting og etter faktisk omstart.
Alle 14 native antallsfelt kontrolleres; en egen aktiv film skal gi nøyaktig
MovieCount=1 og øvrige felt null. Slettet A skal ha null global telling.
Avviste svar skal ikke inneholde antallsobjekt eller private navn.

Positive kall må nå én faktisk service-kontroll og sju native query-kall.
Avvist privat ParentId må nå den konkrete produksjonskontrollen, én
request-teller, én ParentId-avvisning og null native query-kall. Anonymt
avslag kan komme fra Emby sin autentisering før pluginens service-prefix.
Native StreamWriter kan pauses før og etter produksjonskontrollen for
å kontrollere profilsletting med faktisk ventende HTTP-svar.

## Uavklarte krav

Beskyttet løp før skriverkontroll fullførte 111 observasjoner i
`bin/production-discovery-counts-protected-counts-write-revocation-results.json`.
Løpet etter godkjent skriverkontroll fullførte 112 observasjoner i
`bin/production-discovery-counts-protected-counts-write-lease-results.json`.
Begge rapportene er lest tilbake med Completed=true og ingen
IsolationPass=false. Hvert løp omfatter 105 antallskall i de tre fasene.
Privat ParentId ga 404 uten native query-kall; anonyme forespørsler ga 401
før pluginens service-kontroll. Egen numerisk/GUID-parent og global telling
ga det forventede antallet og nådde sju kontrollerte queries.

Før-kontroll-løpet lagret A-sletting mens faktisk HTTP-svar ventet; svaret
ble 404 med 16-byte generisk avslag uten entityheadere, og WritesDenied
økte én gang. Etter-kontroll-løpet krevde at slettingen ventet ved eierlåsen,
B sin profiloppdatering lyktes, korrekt eget antallsobjekt ble skrevet,
og slettingen deretter fullførte uten gjenværende lås/ventere.

Regresjon på samme produksjonsbygg fullførte Suggestions før skriverkontroll
med 18 observasjoner, Views/Latest med 26 og opprinnelig GetItems med 37.
Bygg av produksjon og fixture hadde null advarsler/feil. Sluttkontroll i
`bin/production-item-counts-cleanup.json` er lest tilbake: testkontoer,
biblioteker, lokale prøvefiler og fixture er fjernet, private testprofiler
og oppsettsjournal mangler, serveren er stoppet, og installert DLL matcher
det bygde produksjonsartefaktets SHA-256. Tidligere rapporter gjelder sine
respektive bygg og utgjør ikke en universell regresjon på dette bygget.

Andre medietypers positive telling, favorittfilter, underbiblioteker,
offentlige/private blandinger, innsetting/reparenting og andre native
datakilder er ikke bevist av en Movie-matrise. Genres/studios/tags, resume,
andre ressursinnganger, tokenrevokering og de faktiske klientene gjenstår.
Hele personlig YouTube-henting/avspilling og eksakte Docker-/Linux-builds
må også verifiseres som beskrevet i hovedplanen.
