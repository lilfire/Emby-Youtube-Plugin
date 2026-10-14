# Sjangre, studioer og merkelapper

Undersøkt på isolert Windows Emby 4.10.1.0, 2026-10-13. Ingen utrulling
til hovedserveren. Full skjerming og faktisk støtte i alle klienter er
fortsatt ubevist.

## Funn fra ordinære klientkall

To faktiske lokale Movie-elementer fikk egne og delte metadata gjennom
native admin-API før binding til private profiler. Native readback må
bekrefte private og delte sjanger-/studio-/merkelappnavn før testing.
GetItem-DTO-en bruker GenreItems og TagItems; gamle tomme ID-lister i
oppdateringsobjektet måtte fjernes for at de nye navnelistene skulle lagres.
De to første oppsettsfeilene teller ikke som skjermingstester.

Begge vanlige kontoer hadde brede mapperettigheter og egne native bindinger.
Eksperimentell fixture-beskyttelse var deaktivert. GetGenres/GetStudios/
GetTags med eget, annen eller utelatt UserId viste begge brukernes private
navn og samlet TotalRecordCount. Dette fortsatte etter A-profilsletting og
faktisk omstart, uten produksjonens service-/query-scope.

`bin/production-metadata-before-scope-results.json` er bevart med
Completed=true, 56 observasjoner og 54 IsolationPass=false.
Genre-/studiooversiktene hadde tre navn. Merkelapper hadde fem navn,
inkludert to gamle indeksverdier fra tidligere isolerte fixture-løp.
Det aktive delresultatet før IL-inspeksjonen fungerte er også bevart i
`bin/production-metadata-active-before-scope-results.json`; det er ufullført.

## Produksjonsendringer og native kilde

Listekontrollen inkluderer tre nye DTO-er med Guid-UserId, totalt åtte.
De fire faktiske native LibraryManager-inngangene GetGenres, GetAllGenres,
GetStudios og GetTags har pinnefestede IL-hasher og samme query-/resultat-/
skriverkontroll som tidligere listefamilier. Faktisk konto normaliserer
UserId. Dette rettet sjangre/studioer i den prøvde matrisen.

Det var ikke tilstrekkelig for merkelapper. Det bevarte mellomløpet
`bin/production-metadata-before-tag-source-results.json` har 56 observasjoner,
Completed=false og 18 feil, alle merkelappkall. Produksjonskontrollen ble
nådd, men både fremmede og gamle globale merkelappverdier var fortsatt med.
En nådd query-prefix er dermed ikke alene bevis på riktig resultatkilde.

SqliteItemRepository.GetTags leser globale Tag-indekselementer. Video-ID-er
i ExcludeItemIds avgrenser ikke tag-ID-ene. En egen produksjonsbinding
beregner nå tag-ID-er fra native GetItemLinks hos innhold som både native
brukertilgang og personlig eierkontroll tillater. Den faktiske GetTags-query
får disse ItemIds før native SQL, og eksisterende ItemIds intersectes.
Ingen tillatte tag-ID-er bruker den ikke-eksisterende negative ID-en -1
som eksplisitt tomt filter; en tom array ville betydd ingen ID-begrensning.
Denne kilden bruker InternalScan slik at inventarkall ikke feilaktig teller
som native metadata-query-bevis.

De anvendte tag-ID-ene må fortsatt være tillatte både ved ferdig resultat
og ved faktisk skriverkontroll. Query-objektets faktiske ItemIds må også
fortsatt være lik snapshoten som ble anvendt. Resultat med ukontrollert
tag-kilde avvises.
Native SQL GetTags-kontrakten krever hash
10E642254294B22BEC2B7D4F69954DE5BF39582D9D20806404D411C2D1F18334.
TagService returnerer et typet QueryResult<TagItem> uten ferdig writer;
akkurat den native typen går gjennom den generiske native resultatfabrikken
før registrering ved felles skriverkontroll. Andre resultattyper får ingen
generell omgåelse.

Read-only IL-inspeksjonen er bevart i
`bin/native-metadata-processing-inspection.json`. Den stopper etter 64
metoder og har Truncated=true; den er ikke en komplett SQL-/kildeaudit.
For bred refleksjon ga TypeLoadException i den første inspeksjonen og ble
erstattet av eksplisitte native familier. En inspeksjonsfeil gir et eget
feilfelt og skal aldri regnes som et vellykket native metodebevis.

## Verifisering og avgrensning

Metadata-familien tester begge kontoer, eget/annen/utelatt UserId, eksakte
egne og delte navn, TotalRecordCount, sletting og faktisk omstart. Beskyttede
kall krever faktisk service-/query-kontroll og én native skriverkontroll.
Native StreamWriter kan pauses før og etter skriverkontrollen ved faktisk
profilsletting. Delte metadata-ID-er beholdes når brukeren har eget innhold
med samme metadata; fremmed privat innhold og foreldreløse indeksverdier
skal ikke etablere en tillatt tag-kilde i dette testmiljøet.

På det siste produksjonsbygget bestod seks skriverløp: Genres før/etter
kontroll 60/61, Studios 60/61 og Tags 60/61 observasjoner, totalt 363.
Rapportene heter `bin/production-discovery-metadata-protected-` fulgt av
`genres`, `studios` eller `tags`, og `-write-revocation-results.json` eller
`-write-lease-results.json`. Alle har Completed=true og ingen IsolationPass=false.
Før-kontroll-løpene gir 16-byte generisk HTTP 404 etter lagret sletting,
uten entityheadere. Etter-kontroll-løpene krever ventende sletting ved
eierlåsen, uavhengig B-oppdatering, korrekt eget svar og deretter fullført
sletting uten gjenværende lås/venter. Disse seks matrisene bruker begge
autentiserte kontoer; anonyme kall og kjent privat metadata-ID-kontroll
tilføyes i et eget supplerende løp. Ingen eldre rapport er oppgradert til
dekning av de nye kontrollene.

Det supplerende løpet `bin/production-discovery-metadata-protected-results.json`
fullførte 65 observasjoner, Completed=true og null IsolationPass=false.
Ni anonyme kall (tre ruter i tre faser) ga HTTP 401 uten metadata,
query-kontroll eller registrert skriver. De autentiserte svarene ble også
kontrollert rekursivt mot tre native private metadata-ID-er per konto,
lest tilbake ved oppsett. Tall-ID-er og string-ID-er kontrolleres begge.
Den første utvidelsen hadde en verifierfeil som krevde eget innhold også
fra anonym konto; det ufullførte løpet telles ikke, og aktørkravet ble rettet
før det supplerende løpet over.

Regresjon på samme endelige produksjonsbygg: Views/Latest 26 observasjoner,
Suggestions før skriverkontroll 18, Counts 107 og opprinnelig GetItems 37.
Alle løp fullførte med riktig positiv egenkontroll. Bygg av produksjon og
fixture hadde null advarsler/feil. Sluttrapporten
`bin/production-metadata-lists-cleanup.json` er lest tilbake: testkontoer,
biblioteker, lokale prøvefiler og fixture er fjernet; profiler og
oppsettsjournal mangler; serveren er stoppet; installert produksjons-DLL
matcher det verifiserte byggets SHA-256. Ingen hovedserverendring er gjort.

Direkte navn-/ID-oppslag og metadataressurser er ikke dekket her. Paging,
andre filter-/formatvarianter, per-elementantall, offentlige/private
blandinger, native link-/navneendringer og samtidige native mutasjoner
trenger fortsatt egen verifisering. Alle øvrige hovedplankrav, inklusive
tokenrevokering, faktisk personlig YouTube-kjede og Docker-/Linux-builds,
gjelder fortsatt. En bestått navneliste beviser ikke full skjerming.
