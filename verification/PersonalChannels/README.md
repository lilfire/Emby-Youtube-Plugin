# Personlige YouTube-samlinger: isolert gjennomførbarhetstest

Verifisert 2026-10-11 på den lokale, isolerte Emby Server 4.10.1.0-installasjonen.

Ny kontroll: `Run-Noninterference.ps1 -RequireUnchanged` fant en lekkasje i
resultatantall: bruker B fikk først fire og deretter fem treff på samme side
når bare bruker A la til en privat video. Filtrering etter sideinndeling gav
også tom første side og feil størrelse på sider. Dette viser at filtrering av
ferdige HTTP-svar alene ikke gir full skjerming.

Testprototypen ekskluderer nå andre eieres elementer før biblioteksoppslaget
beregner sider og telling. Listen over ekskluderte ID-er beregnes ved inngangen
til forespørselen. Et første forsøk med nye databasesøk inne i hvert
biblioteksoppslag gav heng i testserveren; den løsningen er fjernet. Nyeste
kjøring fullførte 18 før/etter-sammenligninger uten endring for bruker B, samt
80 samtidige leseforepørsler fordelt på begge eiere med riktig eier og antall.
Positive kontroller krever riktige sider med egne videoer, også uten UserId
og via Users/{id}/Items. Ett oppslag sammenligner komplette videometadata;
de øvrige listeoppslagene sammenligner identitet, rekkefølge og totalantall.
Dette er et begrenset observerbart bevis, ikke generell bevisføring for alle
API-ruter, samtidige endringer eller alle former for metadata.
Rapport: `bin/noninterference-results.json`.

### Kontroll av vanlige biblioteker uten testbeskyttelsen

`Run-NativeLibraries.ps1` opprettet to separate `homevideos`-biblioteker med
to syntetiske MP4-videoer i hvert, samt to nye vanlige brukere. Testpluginen
med eierkontrollen var avinstallert. Begge brukerne fikk `EnableAllFolders=false`
og bare sitt eget biblioteks **GUID** i `EnabledFolders`; numerisk ItemId er
ikke riktig verdi her. Rettighetene ble lest tilbake, og begge autentiserte
sesjoner ble kontrollert for riktig bruker og `IsAdministrator=false`.

Positive kontroller viser egne videoer, to treff, korrekte sider og faktisk
egen avspilling (11 071 byte). Vanlige søk og siste videoer skjulte den andre
brukerens innhold. Likevel ga 16 av 44 observasjoner tilgang til fremmed
innhold: direkte videooppslag, oppslag med den andre brukerens UserId,
PlaybackInfo, etikettoversikter, direkte MP4-strøm og nedlasting. Begge vanlige
brukere fikk den andres MP4 (11 071 byte, HTTP 200) ved kjent video-ID.
Separate biblioteker og biblioteksrettigheter alene er derfor heller ikke et
bevis på full skjerming i denne isolerte Emby 4.10.1.0-installasjonen.

Dette er en test av den konkrete installasjonen med eksisterende produksjons-
og WatchState-testplugin; det er ikke en påstand om alle Emby-installasjoner
eller versjoner. Ingen ekte private brukerdata eller YouTube-nøkler ble brukt.
Testbiblioteker og testbrukere slettes med API, og slettingen leses tilbake
før serveren stoppes. Rapportene er `bin/native-library-results.json` og
`bin/native-library-setup.json`. Dette er referansekjøringen uten eierkontroll.

Prototypen er nå utvidet med eksplisitt eier per syntetisk vanlig biblioteksrot,
og samme sentrale kontroll håndhever disse eierne. `-RequireProtected`
installerer testkontrollen, lagrer to roteiere og kontrollerer etter en reell
omstart at kontrollen er aktiv og at prosessens BootId er endret. Kjøringen
med 48 observasjoner ga null lekkasjer: egne videoer, sider, siste videoer,
biblioteksvisning og egne sjanger-/studio-/etikettoversikter var tilgjengelige;
fremmede videooppslag, PlaybackInfo, direkte strøm og nedlasting ble avvist
med 404. Begge eiere kunne fortsatt spille egne videoer etter omstart.
Den videre testen fant at `Library/VirtualFolders/Query` likevel returnerte
begge private biblioteker med kontrollen aktiv. Tjenesten returnerer et
`QueryResult`-objekt før HTTP-serialisering, og tidligere kontroll av
`StreamWriter` og sesjonsarrayer dekket ikke dette resultatet. Prototypen
filtrerer nå også elementene i slike resultatobjekter. For denne ruten hentes
hele oversikten, filtreres etter eier og deles i sider etterpå, slik at en
side med bare eget bibliotek heller ikke kan røpe et globalt totalantall.

Nyeste kjøring etter omstart har **58 observasjoner og null påviste lekkasjer**.
Begge eiere får ett eget bibliotek, TotalRecordCount=1 og en korrekt første
side; neste side er tom og beholder TotalRecordCount=1. Positive videokontroller
og eksplisitte 404-avslag passerer fortsatt. Rapporter:
`bin/native-library-protected-results.json` og
`bin/native-library-protected-setup.json`. Dette lukker de bekreftede video-
og bibliotekoversiktslekkasjene i testmodellen, ikke alle utestede veier.

API-kartleggingen avdekket enda en variant: den eldre
`GET /Library/VirtualFolders` returnerer `List<VirtualFolderInfo>`, og denne
listen inneholdt begge private biblioteker selv etter kontrollen av QueryResult.
Vanlige lister og elementarrayer filtreres nå også etter elementenes eier.
Begge eiere får bare sin egen biblioteksinformasjon fra både den eldre ruten,
Query-ruten og `Library/MediaFolders`. Før-fiks-rapporten er bevart som
`bin/native-library-list-before-fix.json`.

### Inventar over deklarerte API-ruter

`Run-ApiInventory.ps1` leser rutedefinisjoner, forespørselstyper, feltnavn og
svarkontrakter fra de innlastede Emby-modulene på testserveren. Den siste
kjøringen fant **582 deklarerte ruter**: 355 i Emby.Api, 69 i MediaEncoding,
70 i LiveTV, 26 i DLNA, 25 i Sync og resten i øvrige moduler og
produksjonspluginen. Resultatet er `bin/api-inventory.json`. Inventaret er
ikke 582 vellykkede sikkerhetstester, og en deklarert rute er ikke bevis for
at funksjonen er aktiv, lisensiert eller tilgjengelig i denne installasjonen.

Det konkrete inventaret bekrefter separate behandlingsveier for SOAP/DLNA og
offline synkroniseringsfiler. En Sync-jobb-ID er ikke videoens element-ID, og
en DLNA-kontrollforespørsel bruker SOAP-data fremfor vanlige DTO-ID-felt.
Tilgangskontrollen kan derfor ikke påstå at disse er dekket bare fordi
video-ID-er filtreres. Disse veiene må verifiseres særskilt, sammen med
varsler og øvrige metadataentiteter. Kartleggingen forklarer også hvorfor
gamle Search/Hints- og ikke-deklarerte Filters-oppslag ikke er positive
bevis for vanlige biblioteksøk på denne versjonen.

API-kilder: [opprette bibliotek](https://dev.emby.media/reference/RestAPI/LibraryStructureService/postLibraryVirtualfolders.html),
[biblioteksidentiteter](https://dev.emby.media/reference/RestAPI/LibraryStructureService/getLibraryVirtualfoldersQuery.html) og
[slette bibliotek](https://dev.emby.media/reference/RestAPI/LibraryStructureService/postLibraryVirtualfoldersDelete.html).

### Nytt moteksempel: offline-synkronisering

`Run-NativeLibraries.ps1 -RequireProtected -ProbeSync` ble kjørt med to
vanlige brukere, hvert sitt private bibliotek og hver sin registrerte
synkroniseringsenhet (`native-a` og `native-b`). Hver bruker opprettet en
faktisk jobb for sin egen lokale prøvevideo. Eierens jobb og jobbelement
kunne leses tilbake. Ingen ekte YouTube-nøkler eller eksterne enheter ble brukt.

Kjøringen som påviste hullet hadde **110 observasjoner**, inkludert 28 før eiervernet,
24 Sync-forespørsler etter verifisert serveromstart og 58 bibliotek-/avspillingskontroller.
Dette er antall observasjoner, ikke antall beståtte sikkerhetstester.

Med daværende prøvevern aktivt var følgende feil:

- `GET /Sync/Jobs/{Id}` gav begge brukerne den andres jobb med HTTP 200.
  Svaret inneholdt videotittel, video-ID, intern eier-ID og enhets-ID.
- `GET /Sync/Jobs?StartIndex=0&Limit=1` gav bruker a totalantall 2 til tross
  for bare én synlig jobb. Bruker b fikk en tom førsteside og totalantall 0,
  selv om ubegrenset søk viste vedkommendes egen jobb.

Ubegrensede jobblister og jobbelementlister ble filtrert i disse prøvene.
Dette løser ikke direkte oppslag, kontrollhandlinger eller filtrering før
sidetelling. Jobb-ID og jobbelement-ID må behandles i sine egne navnerom og
knyttes til originalt innhold og eier. De kan ikke tolkes som video-ID-er.
Tilgang må kontrolleres før lesing, endring, sletting og filutlevering.

Jobbene stod fortsatt i `Queued`. Både eierens og den andre brukerens
`/Sync/JobItems/{Id}/File` gav HTTP 400; anonym tilgang gav 401.
`AdditionalFiles` gav også 400. Ingen eier fikk en faktisk offline-fil,
så disse feilresponsene er **ikke bevis for skjerming av nedlastede kopier**.
Det er ennå ikke avklart hvorfor jobbene ikke ble behandlet.

Rapport: `bin/native-library-protected-sync-results.json`.
Den første kjøringen avsluttet med feil fordi den gjenskapte lekkasjen. Testens `finally`
sletter jobbene, leser tilbake at de er borte, fjerner prøvebibliotekene og
brukerne, avinstallerer prøvevernet og stopper den isolerte serveren.
Produksjonspluginen er ikke endret. Full skjerming er fortsatt ikke bevist.

### Etterprøvd kontroll av synkroniseringsjobber

Prøvevernet bruker nå serverens faktiske `SyncManager.GetJob` og `GetJobItem`
for å følge jobb-/fil-ID-er tilbake til jobben, originalvideoen og eieren.
Kontrollen skjer før endepunktet kjøres, også ved oppdatering, sletting og
filforespørsler. Jobb-ID-er og enhets-ID-er behandles ikke som video-ID-er.
Bruker-ID i Sync-forespørsler kontrolleres mot innlogget bruker.

Jobb- og jobbelementlister hentes uten forespurt sidestørrelse, filtreres og
får så sidetelling og sideutvalg. Dette er en verifikasjonsteknikk; kostnaden
for store samlinger og samtidige endringer er ikke verifisert.

Nyeste kombinerte kjøring:
`Run-NativeLibraries.ps1 -RequireProtected -ProbeSync -ProbeDlna`.
Den bestod med **167 observasjoner**. Rapport:
`bin/native-library-protected-dlna-sync-results.json`.
Den nyeste DLL-en var ferdig bygget før denne kjøringen begynte.

Bekreftede positive og negative kontroller for begge vanlige brukere:

- Eierens jobb og jobbelement gav HTTP 200 og korrekt video.
- Den andres direkte jobb, jobbelement og forespørsel med falsk bruker-ID
  gav HTTP 404.
- Førstesiden viste egen jobb med totalantall 1 for begge brukere.
- Eierens oppdatering gav HTTP 200. Den andres oppdatering og sletting gav
  404. Eierens etterfølgende oppslag bekreftet at navn, video-ID og eier-ID
  fortsatt var de samme.
- Fil- og tilleggsfilforespørsler fra andre og anonym bruker ble avvist
  før filendepunktet kjørte. Eierens fil gav fortsatt 400, så ferdige
  nedlastingsfiler har fremdeles ingen positiv avspillingskontroll.
- De eksisterende bibliotek-, avspillings- og aktive DLNA-kontrollene bestod
  samtidig. DLNA-konfigurasjonen ble gjenopprettet og lest tilbake.

Serverens `Convert media`-oppgave (`SyncPrepare`) ble eksplisitt startet og
dens oppgave-ID fulgt til avsluttet `Completed`. Eierens fil feilet fortsatt;
serverloggen oppgir «The job item is not yet ready for transfer.» Dette
avklarer at den tidligere 400-responsen skyldtes filens tilstand, men ikke
hvorfor den aldri ble ferdig. Ingen lisensårsak er bekreftet.

Alt dette gjelder isolerte prøvevideoer og Emby 4.10.1.0. Vi har ikke
verifisert alle Sync-operasjoner, endret eierskap, enhetsbytte, alle
referanseformer, ferdige offline-kopier eller alle fysiske klientapper.
Alle egne jobber, brukere og biblioteker ble slettet med tilbake-lesing,
prøvevernet avinstallert og serveren stoppet. Produksjonspluginen er uendret.
Full skjerming er fortsatt ikke bevist.

### Offline-handlinger: påvist endring av en annen brukers historikk

En ny prøve på `/Sync/OfflineActions` fant et eget hull i den tidligere
prøveversjonen. Med to normale brukere og verifisert eget videoinnhold kunne
begge sende en `PlayedItem`-handling med den andres bruker-ID og video-ID.
Eierens `UserData.LastPlayedDate` ble endret. HTTP 200 alene er ikke beviset:
endringen ble lest tilbake fra eierens egen innloggede sesjon før og etter.
Moteksemplet er bevart i `bin/offline-actions-before-fix.json`.

To tidlige forsøk var ugyldige som sikkerhetskontroller: `MarkFavorite` gav
400 med «Unexpected action type», og kontroll av `PlayCount` var feil fordi
den aktuelle servermetoden ikke øker denne telleren. En prøve med jobb-ID
som `ItemId` traff heller ikke videoen. Metodereferansene i den installerte
serveren bekrefter at `ReportOfflinePlayedItem` bruker originalvideo-ID og
handlingens bruker-ID, oppdaterer avspillingsstatus og lagrer brukerdata.
Den gyldige positive kontrollen bruker originalvideo-ID, `PlayedItem` og
leser `Played` samt `LastPlayedDate` med feltet `UserDataLastPlayedDate`.

Prøvevernet kontrollerer nå alle referanser og oppgitte brukere i den
innkommende listen før den gis videre til serveren. Dette gjelder både
referanse til fremmed video og falsk bruker-ID i et listeelement. Ingen
listeelementer behandles før hele listen har passert kontrollen.

Nyeste kjøring:
`Run-NativeLibraries.ps1 -RequireProtected -ProbeSync -ProbeDlna`.
Den bestod med **187 observasjoner**. Begge eiere fikk HTTP 200 og lagret
egen avspillingsstatus. Fremmede rapporter gav 404, og eierens avspillingsdato
var uendret ved tilbake-lesing. En blandet liste med egen tillatt handling
først og fremmed video etterpå gav også 404; den første handlingen ble ikke
lagret. Rapport: `bin/native-library-protected-dlna-sync-results.json`.

Dette er ikke en prøve av ferdige offline-filer eller alle handlingstyper.
`Convert media` ble igjen fulgt til avsluttet oppgave, men eierens fil var
fortsatt ikke klar for overføring. Emby beskriver nedlasting/synkronisering
som en Premiere-funksjon i [Sync Introduction](https://support.emby.media/support/articles/Sync-Introduction.html).
Dette er en mulig miljøbegrensning, ikke en bekreftet forklaring på den
konkrete filtilstanden. Ingen lisens er anskaffet eller omgått.

Bibliotek-, avspillings-, DLNA- og jobbkontrollene bestod samtidig. Egne
jobber, brukere og biblioteker ble slettet og lest tilbake som fraværende,
DLNA-konfigurasjonen gjenopprettet, prøvevernet fjernet og serveren stoppet.
Ingen produksjonskode ble endret. Full skjerming er fortsatt ikke bevist.

### Statusendepunkt og enhetsbasert synkronisering

Prøven ble utvidet med `GET /Sync/Items/Ready?TargetId=...`, `POST /Sync/Data`
og `POST /Sync/{ItemId}/Status`, både med egen og den andres prøveenhet.
`Items/Ready` returnerte tomme samlinger for begge. `Sync/Data` returnerte
`ItemIdsToRemove` med den lokale ID-en som forespørselen selv oppga. Fordi
ingen prøvefil var klar, verifiserer dette hverken metadata eller filtilgang
for en ferdig privat offline-kopi. Enhetsbasert tilgang er fortsatt uavklart.

En tidligere kontroll antok at `POST /Sync/{ItemId}/Status` oppdaterte
jobbstatus, siden DTO-en har `Progress` og `Status`. Det er ikke tilfelle i
den installerte 4.10.1.0-versjonen. Metodereferansene fra den faktiske
`SyncService.Post(GetSyncStatus)` viser bare opprettelse av et tomt
`SyncedItemProgress`-objekt. Praktiske forespørsler returnerte HTTP 200 med
et tomt objekt uten endring av jobbelementet. Dette var ingen positiv
kontroll av statusendring, og testen bygger ikke lenger på den antakelsen.

Denne prøven påviste samtidig et eksistenssignal i det daværende prøvevernet:
med fremmed privat video-ID kom 404, med ukjent ID kom 200 og tomt objekt.
Dermed var fravær av private navn ikke tilstrekkelig skjerming.
Moteksemplet er bevart i `bin/sync-status-existence-before-fix.json`.

Prøvevernet kontrollerer nå originalvideoens eksistens og eierskap i
HTTP-kontrollen før DTO-tjenesten og dens feilsvar kjøres. Egen video gir
fortsatt 200. Fremmed privat video og ukjent ID gir begge 404 med samme tomme
svar. Testen sammenligner både status og svarinnhold for begge vanlige brukere.
Dette gjelder den konkrete ruten og referanseformen, ikke generelt alle
mulige eksistenssignaler eller tidsforskjeller.

Nyeste kombinerte kjøring bestod med **215 observasjoner**:
`Run-NativeLibraries.ps1 -RequireProtected -ProbeSync -ProbeDlna`.
Rapport: `bin/native-library-protected-dlna-sync-results.json`.
De tidligere positive/negative bibliotek-, DLNA-, jobb- og offline-handlings-
kontrollene bestod samtidig. Testens opprydding fullførte med tilbake-lesing;
serveren er stoppet og prøvevernet avinstallert. Ingen produksjonskode er
endret. Ferdige offline-filer, resterende tilgangsveier og faktiske klienter
gjenstår. Full skjerming er fortsatt ikke bevist.
### Avklart begrensning for ferdige offline-filer

Den isolerte testserverens funksjonskontroll er nå observert under den
faktiske konverteringsoppgaven. En observerende Harmony-postfix følger
returverdien fra serverens implementasjon av
`ISecurityManager.IsFeatureAllowed(string, CancellationToken)`.
Observasjonen venter på og returnerer nøyaktig samme boolske resultat;
den endrer ingen lisens, funksjonstillatelse eller konverteringsstatus.
Ingen nøkkelverdi ble lest eller skrevet til rapporten.

Serveren svarte **`Feature=sync, Allowed=false`**. Én av de registrerte
kontrollene har tidspunkt innenfor den aktuelle `Convert media`-oppgavens
verifiserte start- og sluttid. Oppgaven ble startet etter opprettelsen av
prøvejobbene; sluttresultatet var ikke et gammelt oppgaveresultat.
Metodereferanser fra `SyncJobProcessor` bekrefter funksjonskontrollen på
behandlingsveien til jobbelementene.

Dette avklarer hvorfor denne instansen ikke gir en positiv kontroll av
ferdige konverterte offline-filer: synkronisering er ikke tillatt av serveren.
Det beviser ikke om den underliggende årsaken er manglende/utløpt lisens,
nettverksvalidering eller en annen betingelse i funksjonskontrollen.
Ingen slik årsak er fremstilt som verifisert.

Den nye kjøringen uten DLNA hadde **167 observasjoner** og bestod de
bibliotek-, jobb-, status- og offline-handlingskontrollene. De to ekstra
observasjonene er diagnoser av funksjonskontrollen, ikke nye beståtte
sikkerhetstester. Rapport: `bin/native-library-protected-sync-results.json`.
Samlet gatebevis: `bin/sync-feature-gate.json`, med oppgaveintervallet og
observerte boolske resultater. Den tidligere kombinerte kjøringen med DLNA
hadde 215 observasjoner; det er ulike kjøringer og ulikt omfang.

Brukeren har bekreftet at ingen separat testinstans med aktiv synkronisering
er tilgjengelig. Et reelt forløp fra konvertering til ferdig offline-fil
kan derfor ikke fullverifiseres i det tilgjengelige testmiljøet nå. Dette
er en åpen del av målet, ikke en begrensning som er fjernet fra omfanget.
Øvrige tilgangsveier kan fortsatt undersøkes. Produksjonspluginen er uendret,
prøvemiljøet er ryddet og serveren stoppet. Full skjerming er fortsatt ikke
bevist.
### Bevisstatus for full skjerming

### DLNA, SOAP og medielenkenes autentisering

Første DLNA-prøve gav bare 404, også uten eierkontroll. Tilbake-lesing av
`System/Configuration/dlna` viste `EnableServer=false`. Disse avslagene var
ikke positive sikkerhetsbevis. `-ProbeDlna` krever nå en vellykket
SOAP-baseline med egne data; manglende baseline skal feile testen.

`Run-StreamedMetadata.ps1 -RequireProtected` er utvidet fra åtte til tolv
kontroller med et innkapslet DIDL-Lite-dokument i et SOAP-svar. Prøven fant
en reell formatlekkasje: XML-feltet `Result` inneholder kodet XML-tekst og
element-ID-ene er attributter. Kontroll av vanlige XML-underfelt alene skjermet
ikke denne formen. Prototypen kontrollerer nå ID-attributter og parser
innkapslet DIDL-Lite med DTD og eksterne XML-oppslag avslått. De tolv
kontrollene passerer med egne/private data for eieren og bare offentlige data
for den andre. `bin/soap-format-before-fix.json` bevarer moteksemplet.

Den faktiske tjenesten ble deretter testet ved kortvarig aktivering av DLNA
i testinstansen. PlayTo ble deaktivert under prøven. Hele den opprinnelige
DLNA-konfigurasjonen gjenopprettes og leses tilbake før serveren stoppes.
`Run-NativeLibraries.ps1 -RequireProtected -ProbeDlna` har nå **108 observasjoner**,
inkludert 25 ubeskyttede og 25 beskyttede SOAP-oppslag. Før kontrollen ble
private biblioteker/videoer returnert til begge brukere og ved et anonymt
oppslag. Etter kontrollen var de testede fremmede/anonyme svarene uten
private navn, og hver autentisert bruker fikk egne data.

Prøven avdekket også en credential-lekkasje: DLNA-medielenkene inneholdt en
server/API-nøkkel uten brukereier. Den kunne lese `System/Logs` med HTTP 200.
Den første diagnostikken brukte `System/Configuration`, men den ruten viste
seg ikke å skille vanlige brukere fra privilegerte nøkler; det er loggruten,
ikke konfigurasjonsruten, som underbygger privilegiet i den endelige prøven.
Prototypen erstatter nå `api_key` i medielenker på den kontrollerte lokale
Emby-opprinnelsen med den autentiserte mottakerens egen nøkkel. Svar uten
autentisert bruker får ikke denne nøkkelen. Utstedte lenkenøkler ble kontrollert
mot brukeridentiteten, og begge var bundet til riktig vanlig bruker og fikk
HTTP 403 fra `System/Logs`. Alle fire faktiske medielenker fra de to brukernes
biblioteker gav HTTP 200 og 11 071 byte med bare autentiseringen i lenken.
Nøklene er ikke skrevet ut og er redigert bort fra rapportene.

Rapporter: `bin/native-library-protected-dlna-results.json`,
`bin/native-library-protected-dlna-setup.json` og det tidligere moteksemplet
`bin/dlna-credential-before-fix.json`. Resultattallet inkluderer bevisst
ubeskyttede baselines; det betyr ikke 76 beståtte avslag på private oppslag.
Den videre aktive prøven fant en tellelekkasje: en side med bare eget
bibliotek viste TotalMatches=4, mens den komplette synlige oversikten hadde
tre elementer. De to andre synlige elementene var offentlige systemmapper;
det er derfor feil å kreve at hele rotoversikten bare har ett element.
Moteksemplet er bevart i `bin/dlna-paging-before-fix.json`.

SOAP-forespørsler behandles nå asynkront før tjenesten kjører. Prototypen
kontrollerer ObjectID, leser høyst 64 KiB med DTD/eksterne XML-oppslag avslått,
og endrer BrowseDirectChildren til et komplett kildeoppslag. Eierfiltreringen
skjer før den opprinnelige sideinndelingen brukes. Resultatet må være komplett
før globalt totalantall beregnes; ufullstendige kildeoversikter avvises i
stedet for å rapportere sidelengden som total. De testede rot- og videosidene
har nå identitet/rekkefølge lik tilsvarende del av den komplette synlige
oversikten. Tomme siste sider beholder riktig totalantall. Egne metadata og
medielenker passerer positive kontroller.

Skjult og ukjent ObjectID ga først forskjellige svar. For syntetiske
fixture-elementer lar prototypen nå tjenesten behandle en verifisert
ikke-eksisterende ID i stedet for en skjult ID. Metadataoppslagene for
skjult og ukjent objekt er kontrollert for samme HTTP-status og identisk
SOAP-svar (denne installasjonen bruker en UPnP-feil med kode 401/Invalid Action).
Dette er en testteknikk med et kontrollert sentinel-ID, ikke ferdig
produksjonsbehandling av alle objekt-ID-former.

Tolv formatkontroller og de aktive SOAP-prøvene dekker fortsatt ikke generell
DLNA-privathet. Andre SOAP-handlinger, større resultater, samtidige endringer,
objekt-ID-former, URL-opprinnelser og alle autentiseringsformer må verifiseres
videre. Ingen fysisk DLNA-klient eller TV-/mobilapp er testet.

### Krav og gjenværende bevis

| Krav | Nåværende bevis | Gjenstår |
|---|---|---|
| Egne og fremmede elementer i native biblioteks-API | Eierpositive og negative tester med to eiere i kanal- og vanlige biblioteksmodeller; 58 native observasjoner etter omstart; 582 deklarerte ruter kartlagt | Hele API-overflaten og faktiske TV-/mobilapper |
| Ingen indirekte telling eller påvirkning av sider | 18 før/etter-sammenligninger; positive sider med og uten UserId | Flere filtre, kategoriantall, andre aggregeringer; nullsvar i Counts og Hints er svakt bevis |
| Ingen metadata via direkte ID/navn | Video, sjanger, studio og etikett testet; bibliotekoversikt i et rått QueryResult filtreres før sider og telling | Andre metadataentiteter og alternative resultatobjekter |
| Ingen media via kjente adresser | Syntetisk MP4 og HLS, segmenter, HEAD og Range; fire aktive DLNA-medielenker med riktig brukertoken og uten tilgang til loggruten | Andre strømprotokoller, bilder/undertekster/vedlegg i full bredde, URL-opprinnelser/autentiseringsformer og ekte YouTube-avspilling |
| Ingen sesjons- eller varslingslekkasje | HTTP-/WebSocket-sesjoner og kontrollert LibraryChanged; aktive SOAP-lesinger med egen/fremmed/anonym mottaker | Automatiske varsler, køer, fjernstyring, globale meldinger og resterende DLNA-veier |
| Trygg oppstart | Tidlig sperre, forsinket oppstart og ugyldig eier testet; eierkobling for vanlige biblioteker gjenopprettet ved verifisert restart | Nyeste endringer må prøves ved oppstartsvindu, kompatibilitetsfeil og oppdatering |
| Trygg samtidighet og innholdsendring | 80 samtidige lesinger; ny privat video mellom målinger | Endringer mens lesinger pågår, sletting, eierbytte og rettighetsendringer |
| Private brukerinnstillinger og API-nøkler | Ingen ekte nøkler brukt; profilmodell testet syntetisk | Reell innstillingslagring og alle lese-/skrive-/eksportveier |

Målet er ikke oppnådd. Den bekreftede lekkasjen fra vanlige biblioteker betyr
at vi fortsatt trenger en sentral eierkontroll, ikke bare bibliotekstilgang.
Ingen produksjonskode er endret. Testpluginen bruker syntetiske eiere (`a`, `b`,
`c`), falske video-ID-er og ingen ekte API-nøkler. Den utvidede testen serverer
en lokalt generert blå testvideo og et testbilde. HLS-testen bruker seks sekunder
med syntetisk video og stille lyd. Ingen ekte
YouTube-videoer, YouTube-forespørsler eller avspilling i brukerens apper ble startet.

## Resultat

### Siste status: kontroll inne i pluginen

Den nyeste gjennomførbarhetsmodellen trenger ikke Docker, en ekstern tilgangsport
eller egne klientendringer. Kontrollene ligger i testpluginen og kjøres direkte
mot Emby. Det tidligere forsøket med en separat tilgangsport er ikke valgt som
forutsetning for funksjonen.

- `Run-ExtendedPrivacy.ps1` og `Verify-PrivacyResults.ps1`: 25 eksplisitte
  verifikasjoner bestod, inkludert faktiske video-/bildebytes, komprimert HTTP,
  mottatte WebSocket-sesjonsmeldinger og positive kontroller for eieren.
- `Run-TwoOwners.ps1`: 14 kontroller bestod for to faktiske Emby-brukere med hver
  sin samling. Begge kunne lese egne kopier av samme YouTube-video; begge ble
  avvist ved oppslag mot den andres kopi. Nye videoer og omstart beholdt eierskapet.
- `Run-HlsPrivacy.ps1`: 12 kontroller bestod. Eieren fikk ekte master- og
  mediespillelister og videosegmenter. `ffprobe` bekreftet faktisk transkoding
  fra 160 til 80 piksler bredde. Andre brukere og anonyme fikk 404 på både
  spillelister og segmenter, også med eierens avspillingssesjon. HEAD og
  byteområdeforespørsel fra annen bruker ble også avvist. Eierens eventuelle
  autentiseringsparametere fjernes fra spillelisteadressene før negative tester.
- `Run-LibraryMessages.ps1 -RequireProtected`: seks former for primitive
  video-/mappe-ID-lister ble testet over ekte WebSocket-forbindelser, før og
  etter beskyttelse. Før utvidelsen lekket alle seks også med aktiv kontroll.
  Nå får eieren sine private ID-er, andre får ingen av dem, og offentlige
  video-ID-er beholdes. Meldinger sendes kontrollert gjennom Embys
  `SendMessageToUserSessions` med den vanlige `LibraryChanged`-dataformen;
  testen beviser utgående filtrering, ikke automatisk varsling fra alle
  bibliotekendringer eller klientenes behandling av meldingen.
- `Run-ResponseFormats.ps1`: 20 HTTP-svar fra ti formatvarianter ble lest og
  analysert. `format=xml` var en reell omgåelse før XML-filtreringen ble lagt
  til. Nå får eieren to videoer og andre null, både i gyldig XML og JSON.
  Andre testede formatnavn/Accept-headere falt tilbake til JSON; testen beviser
  ikke at serveren faktisk støtter CSV, JSV, MessagePack eller JSONP.
- `Run-DerivedMetadata.ps1 -RequireProtected`: 100 API-observasjoner med to
  eiere. Sjangere, studioer og etiketter lekket før utvidelsen; direkte oppslag
  på private sjanger-/studionavn lekket også. Nå får begge egne oversikter og
  egne kategori-ID-er, mens den andres navn og ID-er avvises. En kategori som
  begge eierne bruker er synlig for begge. Tolv sideforespørsler med én kategori
  per side fikk riktig totalantall (to synlige kategorier), egen kategori på
  første side og delt kategori på neste. Seks forsøk med den andres `UserId`
  ble avvist. Gyldig XML for sjangere/studioer beholdt eierens data.
  `Tags?format=xml` ga HTTP 500 også uten kontrollpluginen; dette er en eksplisitt
  begrensning, ikke et bestått positivt XML-klientbevis. `Items/Filters`,
  `Items/Filters2` og navneoppslag under `Tags/{Name}` ga 404 også som kontroller;
  disse er ikke verifiserte fungerende ruter på denne serveren.
- `Run-StreamedMetadata.ps1 -RequireProtected`: åtte kontrollerte HTTP-svar
  gjennom Embys ekte `StreamWriter.SourceStream`, i JSON og XML. Før utvidelsen
  lekket begge formater fordi kontrollen bare leste `SourceBytes`. Nå får eieren
  begge testelementene og den andre bare det offentlige elementet, med samsvarende
  resultatantall. Dette tester utgående strømfiltrering med syntetiske DTO-er,
  ikke automatisk alle serverendepunkter som kan bruke strømmer.
- Sesjonsregresjonen fikk først ingen eiermeldinger ved uendret avspilling.
  Testen bruker nå separat enhets-ID for eieren og utløser faktisk
  avspillingsprogresjon mens WebSocket-abonnementet er aktivt. Eieren mottok
  tre private sesjonsmeldinger, og de 25 eksisterende verifikasjonene bestod.
  To-eier-testen med 14 kontroller bestod også etter XML-utvidelsen.
- Filtrering virket også når en testbruker midlertidig fikk tilgang til alle
  kanaler i Emby. Private videosøk ble filtrert, også resultatantallet.
- `Run-StartupGate.ps1` avviste alle testede private oppslag under en bevisst
  fire sekunders oppstartsforsinkelse og ved ugyldig eier. Observerte svar var
  503 under blokkeringen, 404 etter vellykket aktivering og noen 500 under
  serverinitialisering. Ingen av disse testforespørslene fikk HTTP 200.

Eierkontrollen installeres nå i pluginens konstruktør, før `IServerEntryPoint.Run`.
Når lagret beskyttelse finnes, avvises HTTP-forespørsler inntil eiere og nødvendige
serveravhengigheter er klare. Testpluginen laster selv sin innebygde Harmony-
avhengighet tidlig; den er ikke avhengig av at en annen plugin gjør det senere.

Kontrollen omfatter innsendte ID-er før tjenesten kjøres, biblioteksoppslag for
avledede metadata, utgående HTTP-data (JSON/XML i bytebuffere og strømmer,
inkludert komprimerte svar) og WebSocket-data ut fra den autentiserte mottakeren. Vanlig fjernstyring kan være
aktivert; eierens private avspillingssesjon skjules fra andre, mens eieren får
den i både HTTP og WebSocket.

Dette avklarer en mulig pluginarkitektur for personlige samlinger og lukker de
lekkasjene som hittil er påvist med den installerte testpluginen. Det er ikke
en ferdig produksjonsimplementasjon eller en garanti for alle Emby-versjoner og
klienter. HLS-transkoding av syntetisk video er verifisert, men ingen ekte
YouTube-avspilling eller fysisk TV-/mobilapp er testet. Målet om alle
klienttyper gjelder fortsatt. Dagens produksjonsplugin leverer en YouTube-
watchadresse og deaktiverer transkoding i `YouTubeChannel.Mapping.cs`.
HLS-testen beviser derfor tilgangskontrollen for Emby-strømmer, ikke at dagens
YouTube-avspilling virker i alle klienter. YouTube Data API `videos.list`
leverer videoressurser/metadata, ikke en generell MP4/HLS-strøm til Emby.
Kilder: https://dev.emby.media/reference/RestAPI/DynamicHlsService.html og
https://developers.google.com/youtube/v3/docs/videos/list.

Det gjenstår også kontroll av flere utgående dataformer, blant annet
andre former for resultatobjekter, automatisk varsling av bibliotekendringer,
metadata utenfor de tre testede kategoriene og kombinasjoner av biblioteksfiltre.
Testene så langt gir ikke grunnlag for å kalle all mulig metadataeksponering
ferdig sikret.

Testmodellen forutsetter at kontrollpluginen faktisk er installert og kompatibel.
Fjerning eller manglende lasting av hele pluginen kan ikke sikres av den fjernede
pluginen. Administrator som kan endre serverfiler eller deaktivere beskyttelsen
er derfor utenfor skjermingen fra vanlige Emby-brukere. Dette må beskrives tydelig
ved eventuell produksjonsimplementasjon; det skal ikke skjules bak beståtte tester.

Krav til videre implementasjon:

1. Stabil, uforanderlig kanalidentitet og lagret eier-ID per brukerprofil.
2. Brukerspesifikk API-nøkkel og kanal-/spillelistevalg. Bakgrunnsinnhenting
   velger profilens eier selv når Emby sender `UserId = 0`.
3. Kontroll før tjenestekjøring, pluss filtrering av HTTP- og WebSocket-svar.
4. Tidlig oppstartskontroll, validerte kroker og eksplisitt versjonskompatibilitet.
5. Tilpassing av eksisterende pluginlogikk som fortsatt antar én global kanal.
6. Kontroll av resterende API-/strømmeveier og native klienter før utrulling.

Maskinlesbare rapporter finnes i `bin/privacy-verification.json`,
`bin/extended-privacy-results.json`, `bin/two-owners-results.json` og
`bin/startup-gate-results.json`, `bin/hls-results.json`,
`bin/library-message-results.json` og `bin/response-format-results.json`.
De nye rapportene er `bin/derived-metadata-results.json` og
`bin/streamed-metadata-results.json`. Diagnose av biblioteksgrensesnittene er
lagret i `bin/derived-metadata-surface.json`.
Rapportene inneholder ingen nøkler eller tokens. Rapporter fra bekreftede
omgåelser før utvidelser finnes som `bin/library-message-before-fix.json` og
`bin/response-format-before-fix.json`.

Metadatautvidelsen krever mer enn å legge private video-ID-er i
`InternalItemsQuery.ExcludeItemIds`: dette alene skjermet ikke de avledede
oversiktene i testen. Modellen sjekker koblinger fra kategoriene til de konkrete
elementene brukeren får se, og filtrerer før sideinndeling. Forsøk med manuelt
redigerte testmetadata var ustabile fordi kanaloppdatering kunne overskrive dem;
testkanalen deklarerer nå metadataene selv, slik at oppdatering bevarer dem.
Modellen skanner bibliotek/koblinger for å bevise tilgangsregelen. Ytelse på et
stort bibliotek, indeks/cache med trygg oppdatering og korrekt håndtering av
alle filtre er ikke ferdig verifisert. Ikke bruk denne skanningen som ferdig
produksjonsarkitektur uten disse kontrollene.

### Tidligere livssyklus- og tilgangstester

`Run-Lifecycle.ps1` bestod 18 kontroller. Maskinlesbar rapport finnes i
`bin/lifecycle-results.json` etter kjøring.

- Flere instanser av samme kanalklasse fungerer samtidig.
- Bakgrunnsinnhenting mottar `UserId = 0`. Eier må være knyttet til kanalinstansen.
- Hver instans valgte sin egen syntetiske nøkkel-eier. Dette tester valg av eier,
  ikke autentisering eller kvotebelastning mot Google.
- Gjentatt registrering ga ingen duplikater og bevarte eksisterende kanaler.
- Endring av én profil oppdaterte bare den profilen.
- Samme YouTube-provider-ID i to samlinger ga forskjellige Emby-elementer.
- Sett-status for disse elementene var separat, også for samme Emby-bruker.
- Profiler ble lastet fra disk og registrert ved serveroppstart.
- Kanalens database-ID og GUID var stabile over omstart og påfølgende oppdatering.

## Viktige implementasjonskrav

1. `AddParts` erstatter det eksisterende kanalregisteret i den testede serveren.
   Hele registeret må bevares, også andre plugins. Testen henter de eksisterende
   instansene gjennom et privat felt med refleksjon; dette er et gjennomførbarhetsbevis,
   ikke en garanti for et stabilt offentlig integrasjonspunkt i alle Emby-versjoner.
2. `IChannel` har ingen `Id`-egenskap i SDK-et. Testens egen `Id`-egenskap hindret
   ikke at endring av `Name` opprettet en ny database-ID og GUID. Kanalens tekniske
   navn må derfor være stabilt, basert på uforanderlig eierskap fremfor brukernavn.
3. Å fjerne registreringen sletter ikke kanalens eksisterende databaseinnhold.
   Eksplisitt opprydding gjennom `ILibraryManager.DeleteItem` med
   `DeleteFileLocation = false` fjernet kanalen og videoer, også fra søk.
   Direkte oppslag mot et slettet videoelement returnerte HTTP 404.
4. Emby oppdaget også en tom malinstans gjennom dependency injection. Registreringen
   og eventuell automatisk malinstans må håndteres slik at den ikke blir en ekstra
   brukersynlig samling.
5. Den eksisterende pluginens felles konfigurasjon, kanaloppdatering, startsider,
   mappeidentifikasjon og sett-status må tilpasses flere eide samlinger.

## Tilgangskontroll: tidligere praktisk undersøkelse

En vanlig testbruker fikk bare tilgang til én av de eksisterende kanalene.
Kanaltilgangen brukte kanalens GUID i `EnabledChannels`, og ble lest tilbake.

- Kanaloversikt, bibliotekvisning, vanlig rekursivt videosøk og generell
  «nylig lagt til» skjulte den blokkerte kanalen.
- Forespørsler med kjent mappe-/kanal-ID kunne fortsatt hente blokkerte videoer.
- Direkte videooppslag og avspillingsinformasjon returnerte fortsatt data.
- Faktisk avspilling ble ikke forsøkt. Søkehint-endepunktet ga ingen resultater
  også før blokkering og er derfor ikke et gyldig bevis for filtrering.

Personlige samlinger er teknisk gjennomførbare. Kanaltilgang alene skal ikke
beskrives som full personvern- eller sikkerhetsisolering.

## Eierkontroll på serveren: ny isolert test

`Run-Privacy.ps1` bestod 20 kontroller på samme serverversjon. Rapporten ligger
i `bin/privacy-results.json`. Brukerens opprinnelige rettigheter ble gjenopprettet
og lest tilbake. Testkanalene ble slettet, testsesjonen logget ut, serveren
stoppet og testpluginen avinstallert.

Emby sitt `MakePrivate`-endepunkt avviste testens kanal-, mappe- og videoelementer.
`Items/Access` avviste også forsøket. Direkte lagring gjennom SDK-metoden
`ILibraryManager.SaveUserItemShares` med `UserItemShareLevel.None` ble lest tilbake
som lagret, men hindret ikke de testede direkte oppslagene. Disse funksjonene
løser derfor ikke den påviste lekkasjen for kanalinnhold i dette forsøket.

`PrivacyGuard.cs` er et separat gjennomførbarhetsforsøk. Det kombinerer vanlig
kanaltilgang for oversikter og søk med et ekstra HTTP-filter som finner eieren
via kanalens elementhierarki. Eieren sammenlignes med brukeren fra den
autentiserte forespørselen, ikke med en innsendt `UserId`.

Verifiserte resultater:

- Kontroll før aktivering: annen bruker fikk metadata og avspillingsinformasjon.
- Etter aktivering fikk annen bruker HTTP 404 ved direkte metadata, GET/POST
  avspillingsinformasjon, kjent `ParentId`, nylig lagt til med kjent forelder
  og bulkoppslag med `Ids`.
- Annen brukers ID i URL, globalt søk eller Authorization-header omgår ikke filteret.
- Uinnloggede forespørsler mot beskyttede elementer og bildeendepunktet ble avvist.
  Testvideoen har ikke bildeinnhold; dette beviser avvisning av forespørselen,
  ikke skjerming av faktiske bildebytes.
- Eier fikk fortsatt metadata og avspillingsinformasjon. En vanlig bruker som
  ble satt som eier, fikk også tilgang. Administratorstatus alene ga ingen
  overstyring i denne testmodellen.
- Ny video lagt til etter aktivering arvet beskyttelsen gjennom foreldrelenkene.
- Et annet offentlig testelement var fortsatt tilgjengelig.

Dette var den første API-testen med syntetiske elementer. Utvidelsen nedenfor
tester faktisk bilde-/videoinnhold, body og WebSocket. Ingen av testene gir
grunnlag for å erklære full skjerming i produksjon.

## Tidligere utvidet test: hull før siste endringer

`Run-ExtendedPrivacy.ps1` registrerte 41 observasjoner i den siste kjøringen.
Rapport: `bin/extended-privacy-results.json`. Dette er en undersøkelse som også
registrerer lekkasjer, ikke 41 beståtte sikkerhetstester. Første forsøksrapport
ligger i `bin/extended-privacy-baseline.json`.

Verifisert med fungerende kontrollforespørsler:

- Uten filter kunne annen bruker hente faktisk bilde (10 642 bytes) og faktisk
  MP4 (2 276 bytes). Med aktivt filter fikk eieren fortsatt disse bytes, mens
  annen bruker og uinnloggede forespørsler fikk 404 uten innhold.
- GET/HEAD mot strømmeveien, direkte GUID-oppslag og strømmeforespørsel med
  eierens `PlaySessionId` ble avvist for annen bruker. HLS- og nedlastingsveier
  ble også avvist, men det ble ikke produsert fungerende HLS-segmenter eller
  testet en full transkodingsøkt; de skal ikke regnes som komplette medietester.
- Ordinært søk og kanaloversikt uten `UserId` viste ikke private testelementer
  for vanlig bruker. Anonymt søk ga 401. Søkehint uten resultater er ikke et
  selvstendig bevis for filtrering.
- Den opprinnelige body-kontrollen returnerte 404, men lot tjenesten kjøre
  videre: `POST /Sessions/Playing` registrerte den private videoen som avspilt
  i den andre brukerens sesjon. Dette ble rettet i testpluginen ved å stoppe
  `ServiceController.Execute` før tjenesten kjøres. Ny test ga 404 og null
  slike avspillingssesjoner. Privat ID i nestet `NowPlayingQueue` blir nå også
  avvist. Ingen fysisk klient spiller video som følge av disse rapportene.

**Bekreftet lekkasje 1 — sesjoner og WebSocket:** Med
`EnableRemoteControlOfOtherUsers = true` fikk den vanlige brukeren navnet på
eierens private video i `GET /Sessions`, og i tre faktiske `Sessions`-meldinger
over WebSocket. Ingen privat video-ID var nødvendig i disse forespørslene.
Dermed kan ikke et filter som bare kontrollerer innsendte element-ID-er dekke
kravet. Etter at denne fjernstyringsrettigheten ble slått av og lest tilbake,
forsvant private metadata fra HTTP-oversikten. En separat kjøring mottok også
to WebSocket-sesjonsmeldinger uten private metadata etter samme begrensning.
I siste kjøring kom ingen meldinger i observasjonsvinduet; dette siste tilfellet
er ikke i seg selv bevis på filtrering. En ferdig løsning må filtrere slike
utgående data, eller eksplisitt deaktivere fjernstyring av andre brukere og
håndheve begrensningen ved alle rettighetsendringer.

**Bekreftet lekkasje 2 — oppstartsvindu:** Testen lagrer nå filterets eier og
aktiverer det automatisk i `IServerEntryPoint.Run`, før profilregistreringen.
Dette er fortsatt for sent. I siste kjøring fikk annen bruker HTTP 200 med
private metadata umiddelbart etter at serveren svarte etter omstart. Tre
sekunder senere ga samme forespørsel 404, og filtertelleren bekreftet at filteret
da var aktivt. Andre kjøringer fikk 404 allerede ved første forsøk. Et sporadisk
oppstartsvindu er tilstrekkelig til at denne modellen ikke gir full skjerming.
En pause i klienten eller senere aktivering løser ikke dette: beskyttelsen må
virke før klientforespørsler kan behandles, også ved manglende/feilende plugin.

**Historisk konklusjon før siste endringer:** En personlig Emby-kanal fungerer, og direkte innhold kan skjermes
med ekstra serverkontroll. Den testede modellen gir fortsatt ikke full skjerming
i én Emby-server. Før produksjon trengs en sikker oppstartsgrense og kontroll av
sesjons-/WebSocket-data. Separate serverinstanser per bruker er et alternativ
som unngår å legge samlingene i samme serverdatabase, med egne klienttilkoblinger
og mer drift. Dette alternativet er ikke installert eller testet her.

TV-/mobilapper, full HLS/transkoding, DLNA, nedlastings-/synkroniseringsfunksjoner,
alle mulige API-/WebSocket-meldinger og feil ved oppstart er fortsatt ikke
uttømmende verifisert. Administratorer som kan endre plugin/serverkonfigurasjon
er dessuten en annen tillitsgrense enn vanlige serverbrukere.

## Foreslått løsning for vanlige Emby-apper

1. Opprett én stabil Emby-kanal per bruker med eksplisitt eier-ID. Brukerens
   kanalvalg og API-nøkkel hører til denne profilen, også ved bakgrunnsoppdatering.
2. Begrens ordinære kanaloversikter og søk gjennom Emby sin kanalpolicy. Bevar
   øvrige bibliotekrettigheter og håndter nye brukere og endrede rettigheter.
3. Legg på sentral eierkontroll for private elementer og alle relevante
   API-/strømmeveier. Ikke stol på ID-er fra klienten som bevis på eierskap.
   Definer også håndtering av administratorer og fjernstyrt avspilling.
4. Sikre oppstart: ikke eksponer private samlinger før kontrollen er aktiv.
   Ved manglende filter, ukjent eier eller inkompatibel serverversjon må tilgang
   til private samlinger avvises. Testen aktiveres manuelt og har ikke dette.
5. Verifiser hele tilgangsflaten og de aktuelle TV-/mobilappene før utrulling.
   Dette må inkludere faktiske bilder, avspilling/strømmer, søk uten bruker-ID,
   sesjons-ID-er, body-felter, omstart og endring/sletting av eierskap.

Prototypen bruker Harmony mot den konkrete HTTP-serverens interne
`RequestHandler`, samt `ServiceController.Execute`. Dette er
versjonsavhengig og krever kontroll av kompatibilitet ved Emby-oppdatering.
Eier-ID lagres for automatisk oppstart; eierskapskartet er i minnet og gjelder
testelementene. Oppstartsvinduet som er beskrevet historisk ovenfor, ble avvist
i testene etter flytting til konstruktøren. Implementasjonen er fortsatt
et gjennomførbarhetsforsøk. En støttet sentral tilgangskrok fra Emby
ville være et bedre langsiktig integrasjonspunkt. Hvis vi ikke kan sikre alle
tilgangsveier i samme server, er separate Emby-serverinstanser per bruker et
alternativ med sterkere prosess-/datalagringsskille, men egen servertilkobling
og mer drift.

Offisiell dokumentasjon beskriver kanalpolicyen:
[Content Access](https://support.emby.media/support/articles/Content-Access.html).
Den praktiske verifikasjonen ovenfor gjelder Emby 4.10.1.0.

## Gjenta eierkontrolltesten

Bygg og installer testpluginen som for livssyklustesten. Den nyeste testpluginen
laster selv sin innebygde Harmony-avhengighet tidlig.
Opprett en lokal testsesjon for den vanlige testbrukeren og lagre autentiseringssvaret
som `privacy-session.json` under den isolerte serverroten. Filen inneholder en
hemmelighet og skal aldri legges i Git eller skrives til rapporten. Kjør deretter
`Run-Privacy.ps1` før filteret er aktivert. Skriptet kontrollerer servernavn og versjon,
gjenoppretter rettigheter, logger ut testsesjonen og avinstallerer forsøket.

For utvidelsen: Generer `personal-fixture.mp4` i den isolerte serverens
`data/data`-mappe med serverens medfølgende ffmpeg, for eksempel en ett sekund
lang blå 160x90-video i H.264/MP4. Installer testpluginen med serveren stoppet,
start serveren og kjør `Run-ExtendedPrivacy.ps1`. Skriptet oppretter selv en
lokal sesjon for den eksisterende passordløse `fixture-second`-testbrukeren.
Det rydder kanaldata, logger ut sesjonen, gjenoppretter og leser tilbake hele
brukerpolicyen, stopper serveren og fjerner testplugin, profil/filtertilstand
og den genererte mediefilen. Rapporter inneholder ingen autentiseringstokens.

## Gjenta livssyklustesten

1. Bygg `PersonalChannels.csproj` i Release.
2. Med testserveren stoppet, kopier `PersonalChannelsFixture.dll` fra prosjektets
   `bin/Release/net6.0` til den eksisterende isolerte serverens `data/plugins`.
3. Start serveren med `../EmbyFixture/Start-IsolatedServer.ps1`.
4. Kjør `Run-Lifecycle.ps1`.

Testen nekter å kjøre mot et annet servernavn eller versjonsnummer. Den rydder
egne kanaldata, stopper testserveren og avinstallerer testpluginen ved avslutning.
Eksisterende innlogging lastes lokalt; hemmeligheter skrives ikke til rapporten.

## Nyopprettet privat bibliotek: registreringsvindu (2026-10-11)

`Run-NativeLibraries.ps1 -RequireProtected -ProbeNewRoot` oppretter et tredje
syntetisk bibliotek mens skjermingen allerede er aktiv, og skanner en lokal
MP4-video før biblioteket får eierkobling. Før endringen returnerte direkte
videooppslag HTTP 200 med private metadata. Moteksemplet er lagret lokalt i
`bin/native-library-protected-new-root-before-fix.json`.

En avvisning basert bare på bibliotekets navn i foreldrekjeden løste ikke dette:
videoens interne foreldrekjede nådde ikke den virtuelle bibliotekroten.
Testforsøket avviser derfor også eksplisitt merkede syntetiske private videoer
som ennå ikke har en eier. Dette er et krav til identifikasjon av private objekter
fra opprettelsen; navneprefikset i forsøket er ikke en produksjonsmekanisme.

Etter endringen avviste begge vanlige brukeres direkte oppslag, PlaybackInfo,
MP4-strøm og nedlasting med HTTP 404 før eierregistrering. Søk beholdt to egne
treff og avslørte ikke den nye videoen. Etter registrering og lest tilbake
bibliotekpolicy fikk eieren HTTP 200 med riktige metadata, mens den andre
brukeren fikk HTTP 404. Den isolerte kjøringen hadde 70 observasjoner.

Samlet kjøring med `-ProbeDlna -ProbeSync -ProbeNewRoot` fullførte med 277
observasjoner og ingen lekkasjer i de beskyttede kontrollene. Dette inkluderer
positive og negative kontroller samt ubeskyttede baseliner og diagnostikk;
antallet er ikke 277 uavhengige sikkerhetsbevis. Testen verifiserte også lagret
eierkobling etter prosessrestart. Brukere, biblioteker og synkroniseringsjobber
ble fjernet med kontroll av resultatet, DLNA-konfigurasjonen gjenopprettet,
og testserveren stoppet.

Kjøringen inkluderer kansellering med POST Sync/Items/Cancel, POST
Sync/{target}/Items/Delete og DELETE Sync/{target}/Items: eieren kunne fjerne
sin jobb, mens en annen bruker ble avvist uten å endre jobben. Tomme lister var
uten effekt; DELETE med tom liste ga serverfeil også for eieren og er derfor
ikke en vellykket funksjonskontroll. Oppryddingen kontrollerer hvilke jobber
som fremdeles eksisterer før sletting, siden eierens kansellering allerede kan
ha fjernet dem.

Full skjerming er fremdeles ikke bevist for alle klienter, alle serverruter
eller ferdig nedlastet offlineinnhold. Den tilgjengelige serverens faktiske
sync-funksjonssjekk returnerte false under konverteringsoppgaven, og brukeren
har ingen separat testserver med aktiv synkronisering. Det nye registrerings-
vinduet er testet for de nevnte HTTP-rutene og søk; tilsvarende vindu for DLNA,
WebSocket og andre avledede data må kontrolleres særskilt. Forsøket endrer kun
verifikasjonskode, ikke produksjonspluginen.
## DLNA ved opprettelse og eierskifte (2026-10-11)

Utvidelsen av `Run-NativeLibraries.ps1 -RequireProtected -ProbeDlna -ProbeNewRoot`
fullførte med 144 observasjoner. Dette er en egen kjøring uten Sync-testene;
den erstatter ikke den tidligere samlede rapporten med 277 observasjoner.

Før tredje bibliotek fikk registrert eier, beholdt begge vanlige brukeres
DLNA-rotliste samme antall treff som før opprettelsen, uten navnet på det nye
biblioteket. Direkte BrowseDirectChildren på biblioteket ga ingen BrowseResponse.
BrowseMetadata på den private videoen hadde samme status og svartekst som
BrowseMetadata på en ukjent ID. Etter registrering fikk eieren metadata og en
fungerende lokal medielenke (11071 bytes), mens den andre brukeren ble avvist.

Biblioteket ble deretter overført fra bruker a til bruker b. Bruker a beholdt
bevisst sin opprinnelige EnabledFolders-rettighet, slik at kontrollen prøvde
selve eiergrensen også ved en foreldet bibliotekpolicy. Etter overføringen
fikk bruker a HTTP 404 for metadata og MP4-strøm, mens bruker b fikk HTTP 200
og fungerende avspilling. Tilsvarende DLNA-kontroller bestod. Alle disse
kontrollene ble gjentatt etter en verifisert ny serverprosess med lagret
eierkobling. Medielenken som bruker a fikk før overføringen, ble også brukt
på nytt: HTTP 404 både før og etter omstart. Lenken med autentisering ble
bare holdt i minnet; rapporten lagrer bare status, aldri URL eller token.

Testen kontrollerer nye forespørsler og gjenbruk av utstedte URL-er. Den beviser
ikke avbrudd av en allerede åpen mediestrøm eller sletting av filer som en
klient tidligere har lastet ned. WebSocket-hendelser i registreringsvinduet,
videre innholdsskanning, andre serverversjoner og faktiske apper er fortsatt
åpne punkter. Full skjerming er derfor fremdeles ikke dokumentert.
## Nye videoer etter registrering av biblioteket (2026-10-11)

Den første inkrementelle kontrollen fant en funksjonsfeil: en ny skannet video
ble avvist med HTTP 404 også for riktig eier. Forsøket registrerte eiere bare
for objektene som eksisterte da biblioteket fikk eierkobling. Moteksemplet er
lagret lokalt som `bin/native-library-incremental-before-fix.json`.

Forsøket bruker nå SDK-metoden `ILibraryManager.GetCollectionFolders(BaseItem)`
for nye videoobjekter uten direkte eierregistrering. Et syntetisk privat
bibliotek uten eier gir avvisning. Flere private biblioteker med ulike eiere
gir også avvisning i forsøket; sistnevnte regel er ikke praktisk testet ennå.
Dette er kun verifikasjonskode. Produksjonspluginen er uendret.

Samlet kjøring med `-RequireProtected -ProbeDlna -ProbeSync -ProbeNewRoot`
fullførte med 309 observasjoner og ingen lekkasjer i de beskyttede kontrollene.
Både første video i det nye biblioteket (`LibraryInitial_c_1`) og videoen som
ble lagt til etter eierskifte og omstart (`LibraryScanAddition_c_2`) hadde
vanlige navn uten det tidligere private videoprefikset. Den første ble avvist
før eierregistrering og tillatt etterpå. Den nye videoen ble oppdaget av den
faktiske biblioteksoppgaven, uten ny eierregistrering eller manuell utvidelse
av objektlisten. Eieren fikk metadata og 11071 bytes MP4, mens den tidligere
eieren fikk HTTP 404. Globale videosøk uten oppgitt UserId viste fire videoer
for eieren og to for den andre brukeren, med samsvarende TotalRecordCount.
DLNA ga eieren metadata og fungerende medielenke for den nye videoen, og
avviste den andre brukeren. Tidligere tester for opprettelse, eierskifte,
omstart, utstedte DLNA-lenker og Sync-kontroller bestod i samme kjøring.

Resultatene finnes i `bin/native-library-protected-dlna-sync-new-root-results.json`.
Testjobber, biblioteker og brukere ble fjernet med kontroll av resultatet,
DLNA-konfigurasjonen gjenopprettet og testserveren stoppet. Observasjonsantallet
inkluderer baseliner og diagnostikk. Det beviser ikke alle ruter, alle klienter,
WebSocket under opprettelse, ferdige offlinefiler eller allerede åpne strømmer.
Full skjerming er derfor fortsatt uavklart på disse områdene.
## WebSocket-kontroll gjennom bibliotekets livssyklus (2026-10-11)

`Run-NativeLibraries.ps1` har nå `-ProbeNativeSocket`, sammen med
`-RequireProtected -ProbeNewRoot`. Den åpner faktiske WebSocket-forbindelser
for begge vanlige brukere. Et begrenset administratorendepunkt i testpluginen
sender et deterministisk LibraryChanged-varsel gjennom serverens
ISessionManager.SendMessageToUserSessions. Varselet inneholder video-ID-er fra
alle tre private testbiblioteker, bibliotekreferanser og en offentlig
kontroll-ID. En tilfeldig kontrollmarkør gjør at testen krever akkurat dette
varselet og ikke forveksler andre hendelser eller et tomt svar med skjerming.
Mottakeren setter sammen alle WebSocket-fragmenter før JSON leses.

Ti kontroller bestod: begge brukere før eierregistrering, etter registrering,
etter eierskifte, etter verifisert prosessrestart og etter ny video ble skannet.
Begge fikk sine to opprinnelige video-ID-er og den offentlige kontroll-ID-en.
Den nye private ID-en var skjult for begge før eierregistrering, deretter bare
synlig for riktig eier, også etter overføring og restart. ItemsUpdated og
FoldersAddedTo ble kontrollert for uvedkommende referanser.

Første forsøk manglet kontrollvarselet etter den andre omstarten og ble avvist
som ufullstendig, ikke registrert som et vellykket sikkerhetsbevis. Testen
oppretter nå en ny faktisk innlogging før WebSocket-tilkobling i hver fase og
kontrollerer at bruker-ID og ikke-administratorstatus stemmer. Isolert kjøring
fullførte med 94 observasjoner. Samlet kjøring med DLNA, Sync, nytt bibliotek
og WebSocket fullførte med 319 observasjoner og ingen lekkasjer i de beskyttede
kontrollene. Rapporten er
`bin/native-library-protected-dlna-sync-new-root-socket-results.json`.
Brukere, biblioteker, testjobber og testplugin ble ryddet, konfigurert DLNA
lest tilbake som gjenopprettet og testserveren stoppet.

Dette beviser filtrering av den kontrollerte LibraryChanged-meldingen gjennom
reelle serverforbindelser. Det beviser ikke hvilke andre meldinger en faktisk
bakgrunnsskanning genererer, eller at alle hendelsesformer og klienter er
skjermet. Naturlige skannevarsler, overlappende private biblioteker, allerede
åpne strømmer og ferdige offlinefiler krever fortsatt egne kontroller. Det er
fortsatt ikke grunnlag for å si at full skjerming er bevist.
## Naturlige WebSocket-varsler fra skanning (2026-10-11)

`NaturalSocketScan` åpner begge brukernes faktiske WebSocket-forbindelser før
biblioteksoppgaven startes. En ny lokal video legges til i bruker b sitt
private bibliotek. Testen kontrollerer at videoen faktisk ble skannet inn,
venter gjennom serverens varslingstid og leser naturlige LibraryChanged-
meldinger før et separat kontrollvarsel avslutter innsamlingen. Begge brukere
må motta det merkede kontrollvarselet. Bruker b må få den nye video-ID-en i et
naturlig varsel, og bruker a må ikke få et bibliotekvarsel fra denne private
endringen.

Det første forsøket ventet bare ti sekunder og mottok ingen naturlige varsler.
Det ble avvist som manglende positiv kontroll. Signatur-/IL-inspeksjon av den
installerte LibraryChangedNotifier viste Timer med 40000 ms etter siste
endring. Testen venter nå 45 sekunder etter fullført oppgave. Inspeksjonen
leser metodehenvisninger og utvalgte statiske instruksjonskonstanter, aldri
runtime-nøkler eller registreringsverdier. Ingen abonnementssjekk ble funnet
i denne sendemetoden; den bruker faktiske innloggede brukersesjoner.

Etter korrekt ventetid fikk bruker b den nye video-ID-en. Bruker a fikk en
tom LibraryChanged-melding med IsEmpty=false. Selv uten private ID-er kunne
dette røpe at et bibliotek hadde endret seg. Moteksemplet er bevart lokalt som
`bin/native-library-natural-socket-empty-event-before-fix.json`.

Testforsøket undertrykker nå LibraryChanged helt når alle seks referanselistene
blir tomme etter eierfiltrering. Begge faktiske SendAsync-overlastene returnerer
en fullført Task ved undertrykkelse; andre WebSocket-meldinger følger samme
sendeløp som tidligere. Samlet kjøring med
`-RequireProtected -ProbeDlna -ProbeSync -ProbeNewRoot -ProbeNativeSocket`
fullførte med 321 observasjoner. Bruker a fikk null naturlige bibliotekvarsler,
bruker b fikk ett med den nye video-ID-en, og begge fikk kontrollvarselet.
Øvrige positive og negative kontroller bestod. Rapporten er
`bin/native-library-protected-dlna-sync-new-root-socket-results.json`.

En separat regresjonskjøring av `Run-LibraryMessages.ps1 -RequireProtected`
bestod for ItemsAdded, ItemsUpdated, ItemsRemoved, FoldersAddedTo,
FoldersRemovedFrom og CollectionFolders. Eieren beholdt sine private referanser,
den andre brukeren fikk ingen slike referanser, og offentlige videooppdateringer
ble bevart. Naturlig skanning er bare prøvd for denne private tilleggsendringen;
sletting, omdøping, samtidige offentlige endringer og alle øvrige hendelsesformer
er ikke bevist. Testserveren ble stoppet og testpluginen fjernet.
Full skjerming for alle klienter og offlineinnhold er fremdeles ikke bevist.
## Slettevarsler og historisk eierkobling (2026-10-11)

Den naturlige WebSocket-testen omfatter nå både innlegging og sletting av den
nye lokale videoen. For sletting åpnes begge forbindelsene først, deretter
fjernes bare den konkrete genererte MP4-filen under bin/native-c og den
faktiske biblioteksoppgaven kjøres. Testen leser tilbake at den gamle ID-en
ikke lenger finnes i biblioteket, venter 45 sekunder og krever ItemsRemoved
med den gamle ID-en for eieren. Begge forbindelser må fortsatt motta et
separat kontrollvarsel. Et feilaktig krav om en ny video i første utgave av
slettekontrollen ble rettet før resultatene ble brukt som sikkerhetsbevis.

Testen fant en faktisk lekkasje: bruker a fikk den gamle private video-ID-en i
et naturlig slettevarsel selv om videoen var fjernet. Moteksemplet er bevart i
`bin/native-library-natural-deletion-before-fix.json`. Eieroppslag for nye
videoer støttet seg på levende biblioteksobjekter; dette var utilstrekkelig
etter sletting.

Testforsøket beholder nå historiske eierkoblinger for numerisk ID og GUID.
Faktiske ItemAdded-, ItemUpdated- og ItemRemoved-hendelser registrerer eier
ut fra de syntetiske private bibliotekene. Registrering av bibliotekeier
oppdaterer koblingene for eksisterende objekter. Historikken beholdes separat
når den aktive objektlisten gjenbygges, og bruker ConcurrentDictionary fordi
bibliotekshendelser og forespørsler kan kjøres samtidig. Dette er fortsatt
kun forsøkskode, ikke endring av produksjonspluginen.

Etter endringen fikk bruker a null naturlige bibliotekvarsler ved sletting,
mens bruker b fikk ett med riktig ItemsRemoved-ID. Begge fikk kontrollvarselet.
Begge brukeres direkte oppslag på den slettede videoen ga HTTP 404. Isolert
kjøring bestod med 100 observasjoner. Samlet kjøring med DLNA, Sync, nye
biblioteker, eierskifte, omstart og WebSocket bestod med 325 observasjoner.
Rapporten er `bin/native-library-protected-dlna-sync-new-root-socket-results.json`.
En separat regresjonskjøring av Run-LibraryMessages.ps1 bestod også for alle
seks referansefelter og bevarte offentlige videooppdateringer. Oppryddingen
fullførte og testserveren ble stoppet.

Historikken er foreløpig bare i minnet. Behandling av gjenstående referanser
til slettet privat innhold etter en ny serverprosess er ikke bevist. Dette
gjelder blant annet eventuelle synkroniseringsjobber og lagrede medieartefakter.
Omdøping, blandede offentlige/private endringer, overlappende biblioteker,
faktiske klienter og ferdig offlineinnhold gjenstår også. Full skjerming er
fortsatt ikke bevist.
## Synkroniseringsjobb med slettet kilde etter omstart (2026-10-11)

`Run-NativeLibraries.ps1` har nå `-ProbeDeletedSync`, sammen med
`-RequireProtected -ProbeSync -ProbeNewRoot`. Denne kjøringen bruker egen
slettekontroll og kombineres ikke med -ProbeNativeSocket, som allerede sletter
samme prøvevideo. Testen oppretter en faktisk Original-synkroniseringsjobb for
den nye private videoen hos bruker b, verifiserer eierens metadata og HTTP 404
for bruker a, fjerner den konkrete genererte filen, skanner biblioteket igjen
og gjentar oppslag før og etter en verifisert ny serverprosess.

Emby bruker automatisk videonavnet som jobbnavn i dette tilfellet. Den første
navnekontrollen forventet det innsendte jobbnavnet og ble rettet til det
faktiske videonavnet før kjøringen ble brukt som bevis.

Jobben var tilgjengelig for eieren før sletting. Etter sletting ga den HTTP
404 for begge brukere, også etter omstart. For å skille reell sletting fra
skjuling i testfilteret ble et begrenset administratorendepunkt lagt til i
testpluginen: NativeSyncJobProbe bruker den installerte SyncManager.GetJob
og returnerer bare om akkurat den syntetiske jobben finnes. Den bekreftet at
jobben faktisk eksisterte før sletting, og at den var fraværende både etter
sletting og etter omstart. En opprinnelig privat jobb som fortsatt finnes på
den andre videoen, inngår i øvrige positive kontroller i samme kjøring.

Kjøringen med DLNA, Sync, nytt bibliotek og -ProbeDeletedSync fullførte med
319 observasjoner og ingen lekkasjer i de beskyttede kontrollene. Rapporten er
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-results.json`.
Dette er en annen testkombinasjon enn WebSocket-kjøringen med 325 observasjoner;
den erstatter ikke denne. Testjobber, biblioteker og brukere ble ryddet med
kontroll av resultatet, DLNA-konfigurasjonen gjenopprettet, testplugin fjernet
og testserveren stoppet.

Det ble ikke funnet en gjenstående jobb som lekket fra den slettede prøvekilden.
Dette beviser den observerte oppryddingen av en kølagt Original-jobb i Emby
4.10.1.0, ikke sletting av ferdig konverterte offlinefiler, flere kilder i samme
jobb, samtidige forespørsler under sletting eller alle lagrede medieartefakter.
Historisk eierkobling er fortsatt bare i minnet. Full skjerming for alle
klienter og offlineinnhold er derfor fortsatt ikke bevist.
## Jobb med flere videoer: sletting av én kilde og omstart (2026-10-11)

`-ProbeMultiSourceSync` utvider `-ProbeDeletedSync`. Første forsøk med to
individuelle ItemIds ga en returnert jobb med bare én RequestedItemId. Dette
ble avvist som manglende flerkilde-kontroll, selv om begge videoer kunne leses
av riktig eier. Det resultatet beviser ikke hvordan serveren grupperer alle
individuelle forespørsler. Testen bruker nå én faktisk jobb for hele det
syntetiske private biblioteket. Den krever to konkrete jobbelementer før
sletting, én gjenværende med riktig kilde-ID etter sletting, og samme element
etter en verifisert serveromstart. Jobb-ID registreres for opprydding før
innholdskontrollene, slik at feil under opprettelsen også kan ryddes.

Samlet kjøring med
`-RequireProtected -ProbeDlna -ProbeSync -ProbeNewRoot -ProbeDeletedSync -ProbeMultiSourceSync`
fullførte med 336 observasjoner. Jobben ble bevart etter at én video ble
slettet, bekreftet direkte i NativeSyncJobProbe både før og etter omstart.
Eieren fikk HTTP 200 med jobbmetadata og én gjenværende kilde. Den andre
brukeren fikk HTTP 404 for både jobb og jobbelementliste. Den gamle filruten
for det slettede jobbelementet ga HTTP 404 for begge brukere etter omstart.

Jobboversiktene ble prøvd med og uten eksplisitt UserId for begge brukere,
både etter sletting og etter omstart. Bare eieren fikk bibliotekjobben i
listen. Eierens TotalRecordCount økte med én sammenlignet med den målte
oversikten før opprettelsen; den andre brukerens antall var uendret.
Resultatene finnes i
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-results.json`.

Oppryddingen fullførte med kontroll av testbrukere, biblioteker og registrerte
jobber. En separat kontroll med testfilteret avinstallert bekreftet også at
jobbene fra de to mislykkede oppsettforsøkene ikke lå igjen i Embys jobbregister.
Testserveren ble stoppet. Produksjonspluginen er uendret.

Dette gjelder en kølagt bibliotekjobb med to private videoer i Emby 4.10.1.0.
Den beviser ikke ferdige offlinefiler, en jobb med offentlige og private kilder,
sletting av selve biblioteket mens jobben eksisterer eller alle klienters
oppførsel. Historikk for slettede ID-er er fortsatt bare i minnet. Full
skjerming er dermed fortsatt ikke bevist for hele målet.
## Opprettelse med blandede kilder og skjult/ukjent ID (2026-10-11)

`-ProbeMixedSync` prøver begge vanlige brukere med egne og den andres private
video-ID-er i samme CreateSyncJob-forespørsel. Begge rekkefølger testes.
NativeJobsSnapshot er et begrenset administratorendepunkt for akkurat de to
syntetiske brukerne. Det leser faktiske SyncManager-jobber og jobbelementer,
kontrollerer den native brukeravgrensningen, sorterer etter ID og returnerer
antall, jobb-ID-er for opprydding og en SHA-256 av den serialiserte tilstanden.
Det returnerer ingen jobbtitler, kildebaner eller innholdet som hashes.

Gyldig opprettelse for eieren brukes som positiv målekontroll: jobbantallet
må øke med én og tilstandsavtrykket må endres. Kontrolljobben slettes igjen.
Den første samlede kjøringen krevde også uendret tilstand hos den andre
brukeren under denne tillatte handlingen. Den ekstra forventningen ble
fjernet fra positiv kontroll da den faktiske nye jobben var korrekt målt.
Kravet om uendret tilstand hos begge brukere ved avviste forespørsler er
beholdt. Før slike kontroller kreves tre påfølgende like målinger med 200 ms
mellomrom, innen ti sekunder, slik at en uavklart overgang ikke telles som
sikkerhetsbevis.

Sammenligning med den ukjente ID-en 999999999 fant en konkret forskjell:
skjult kilde ga HTTP 404, mens ukjent kilde ga HTTP 500. Det målte avtrykket
av jobber/jobbelementer var også endret etter forsøket. Moteksemplet er bevart
som `bin/native-library-mixed-sync-hidden-missing-before-fix.json`.
Forskjellen i HTTP-svar kunne brukes til å skille skjult innhold fra en
ukjent ID. Dette forsøket alene fastslår ikke hvilken enkelt post som ble
endret eller årsaken til hver tilstandsendring.

Testfilteret kontrollerer nå at alle eksplisitte originalkilder i CreateSyncJob
finnes før den native opprettelsen kjøres. Dette gjelder ItemIds og oppgitt
ParentId; standard ParentId=0 behandles fortsatt som standardverdi. Kontrollen
er avgrenset til denne opprettelses-DTO-en, siden andre Sync-ruter kan bruke
jobbelement-ID-er i stedet for opprinnelige video-ID-er.

Etter endringen bestod begge brukere og begge rekkefølger: skjult og ukjent
kilde ga samme HTTP 404 og samme målte svarinnhold. Native tilstandsavtrykk
for begge brukeres jobber og jobbelementer var uendret. Gyldig eieropprettelse
fungerte fortsatt. Den avgrensede kjøringen hadde 233 observasjoner.
Den siste samlede kjøringen med DLNA, Sync, nytt bibliotek, flerkildejobb,
sletting/omstart og -ProbeMixedSync hadde 356 observasjoner og ingen lekkasjer
i de beskyttede kontrollene. Rapporten er
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-results.json`.

Oppryddingen fullførte. En separat kontroll i serveren uten testfilter fant
null gjenværende syntetiske jobber, også etter det mislykkede forsøket med
ukjent kilde. Testpluginen ble fjernet og testserveren stoppet.
Produksjonspluginen er uendret. Dette beviser de prøvde opprettelsesforespørslene,
ikke alle leseforespørslers skjult/ukjent-paritet, alle mål-enheter eller alle
foreldre-/kategori-varianter. Ferdig offlineinnhold og faktiske klienter er
fortsatt ikke verifisert. Full skjerming er fortsatt ikke bevist.
## Lesesvar for skjult og ukjent ID (2026-10-11)

Kjoringen med -RequireProtected -ProbeReadParity lagret 74 observasjoner i
bin/native-library-protected-read-parity-results.json. Begge eiere kunne lese
sin egen video (HTTP 200). Ingen fremmede private markorer ble returnert,
men alle 14 sammenligninger av skjult og ukjent ID hadde forskjellige svar.

- Direkte element: begge 404, men ulik svarkropp og Content-Type.
- ID-liste, blandet egen/annen ID-liste og ParentId: skjult 404,
  ukjent 200 med tomt resultat eller bare eget element.
- PlaybackInfo og stream HEAD: skjult 404, ukjent 500.
- Download HEAD: begge 404, men ulik Content-Type.

Arsaken i testgrensen er at CheckUrl avviser kjente fremmede referanser
med et tomt 404-svar, mens ukjente referanser gar videre til native Emby.
Dermed kan en innlogget bruker skille disse tilfellene. De tidligere
kontrollene av fravaer av metadata fanget ikke denne eksistensindikatoren.
Full skjerming er derfor fortsatt ikke bevist.

Videre losning som ma testes: listeforesporsler bor behandle utilgjengelige
referanser som manglende, med samme tomme/egenbegrensede resultat, telling
og paginering. Direkte element- og medieforesporsler trenger et konsistent
ikke-funnet-svar for bade manglende og utilgjengelige referanser, inkludert
status, kropp og Content-Type. Native 500 for manglende medie-ID bor ikke
kopieres som onsket sluttatferd. Mutasjoner trenger fortsatt samlet
forhandskontroll, slik at en blandet foresporsel ikke delvis utfores.
Dette er en anbefaling fra lokal inspeksjon, ikke en verifisert rettelse.

Produksjonspluginen er uendret. Etter kjoringen er ingen EmbyServer-prosess
aktiv. Ferdige offlinefiler og faktisk kompatibilitet med alle klienter
kan fortsatt ikke verifiseres i denne testinstansen.
## Rettelse og utvidet kontroll av lesesvar (2026-10-11)

Endringer er bare gjort i den isolerte testpluginen og verifikasjonsskriptet.
Produksjonspluginen er fortsatt uendret.

CheckUrl normaliserer manglende numeriske/GUID-baserte individuelle ressurser
pa de provde rutene til samme tomme 404 som utilgjengelige ressurser. Dette
gjelder GET/HEAD for direkte bruker-element, PlaybackInfo, Download og
Videos-ruter, samt POST PlaybackInfo. Faste rutenavn som Latest omfattes ikke.
Eierens POST PlaybackInfo har en egen positiv kontroll med MediaSources.

Listeforesporsler til Items og Users/{user}/Items tillater Ids og ParentId
som filtre, mens autentisert bruker fortsatt avgjor synlighet. Testgrensen
henter resultatet uten sidebegrensning, filtrerer utilgjengelige elementer,
og beregner telling og side etter filtrering. Dette ma gjores for bade native
QueryResult og StreamWriter med JSON/XML. Forste pagingforsok manglet dette
for StreamWriter og ble avvist av den eksisterende positive sidetesten.

Den samlede kjoringen med DLNA, Sync, nytt bibliotek, eierskifte, sletting,
flerkildejobb, blandet opprettelse og lesesvar bestod med 398 observasjoner.
Rapport:
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-results.json`.

Etterpa ble lesekontrollen utvidet med XML og stabile respons-headere:
Cache-Control, ETag, Last-Modified, Content-Range, Content-Length,
Content-Encoding og Transfer-Encoding, i tillegg til Content-Type.
Den avgrensede kjoringen bestod med 108 observasjoner og 42 sammenligninger
uten malte forskjeller eller fremmede private markorer. Den siste rapporten
`bin/native-library-protected-read-parity-results.json` erstatter den tidligere
mindre rapporten med samme navn. Egen video, POST PlaybackInfo, XML, ordinart
biblioteksinnhold, paginering og faktisk MP4-avspilling har positive kontroller.
Blandede ID-lister beholder bare egen video og totalantall 1, ogsa pa tom side 2.

HEAD pa Items-lister ga 404 ogsa for eierens egen ID hos begge brukere.
De seks sammenligningene av slike HEAD-ruter dokumenterer lik rutefeil,
men beviser ikke beskyttelse av en fungerende HEAD-liste. Eieren kan lese
samme lister med GET. XML-side 1 og 2 ble kontrollert som faktisk XML med
riktig elementantall og totalantall, ikke bare lik avvisning.

Begge kjoringene fullforte oppryddingen med vellykket prosessavslutning.
Etter siste kjoring er test-DLL-en borte og ingen EmbyServer-prosess aktiv.

Begrensninger: denne testen maaler ikke timing eller samtlige HTTP-headere.
Den beviser heller ikke alle andre ruter, fremmede Sync-mal/enheter,
ferdigproduserte offlinefiler eller alle faktiske klienter. XML/paging-kontrollen
ble kjort separat etter den samlede testen; den endret bare testskriptet.
Full skjerming er fortsatt ikke bevist.
## Sync-mal, enhetspolicy og dialogens malliste (2026-10-11)

Ny test: -RequireProtected -ProbeSync -ProbeSyncTargets. Begge brukere kunne
se hverandres native-a/native-b-mal. Gyldig privat egen kilde ga HTTP 200
og en faktisk ny native jobb ogsa med den andres TargetId og med et ukjent
TargetId. Det sier ikke at ferdige filer ble levert: faktisk Sync-konvertering
er fortsatt utilgjengelig. Moteksemplet er bevart i
`bin/native-library-sync-targets-before-target-validation.json`.

Deretter fikk begge syntetiske brukere EnableAllDevices=false og bare egen
native-enhet i EnabledDevices, med API-readback. Native Sync viste fortsatt
fremmede mal og opprettet jobber mot dem. Enhetspolicy alene beskytter derfor
ikke de provde Sync-rutene. Rapporten er bevart i
`bin/native-library-sync-targets-native-device-policy-only.json`.

Testpluginen handhever na eksplisitt den lagrede enhetspolicyen for TargetId
bade i URL og i Sync-DTO, og filtrerer native SyncTarget-lister. En utvidet
test fant deretter en separat lekkasje i Sync/Options uten valgt TargetId:
dialogens Targets inneholdt begge brukernes enhetsnavn. Den er dokumentert i
`bin/native-library-sync-options-targets-before-filter.json`. Testfilteret er
utvidet til denne nestede mallisten, i tillegg til de direkte mallistene.

Viktig forutsetning: dette er en avgrenset test med eksplisitte tillatte
enhets-ID-er. EnableAllDevices=true tolkes fortsatt som bred tillatelse av
testgrensen og beviser ikke privat mal-eierskap. Dette er ikke en ferdig
universell losning for nye eller delte enheter. En produksjonslosning trenger
en tydelig per-bruker rettighetsmodell for Sync-mal som ikke lar brukeren
selv overta en annen brukers registrerte enhets-ID. Den provde modellen kan
ogsa begrense server-/andre Sync-provider-mal som ikke er enhets-ID-er.
Ingen produksjonskode eller virkelige brukerpolicyer er endret.

Verifikasjonen har positive kontroller: eget mal finnes i listen og dialogen,
egen jobb opprettes i native manager, og egne Ready/Options/Data-ruter gir 200.
Ready og Data er tomme her og beviser ikke ferdig filoverforing. Fremmede og
ukjente mal gir 404 for Ready, Options, Data og jobbopprettelse. For de fire
avviste opprettelsene er hele det malte native tilstandsavtrykket for begge
brukernes jobber/jobbelementer uendret, ikke bare den filtrerte klientlisten.
Stabile snapshot-par samles for mutasjonskontrollene.

Sync/Options?format=xml gir 500 ogsa uten testpluginen hos begge eiere.
Serverstacken viser ObjectDisposedException i native ResponseHelper.WriteObject.
Beskyttet foresporsel ga samme feil. Denne XML-ruten har ingen fungerende
positiv kontroll og regnes ikke som bevist beskyttet. Dette gjelder ikke de
fungerende XML-listene for Items som ble provd tidligere.

Den avgrensede utvidede Sync-kjoringen bestod med 255 observasjoner.
Den samlede kjoringen med DLNA, Sync, nytt bibliotek, eierskifte, sletting,
flerkildejobb, blandet opprettelse, utvidede lesesvar og malpolicy bestod med
446 observasjoner og ingen fremmede private markorer i de beskyttede svarene.
Samlet rapport:
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-targets-device-policy-results.json`.
Alle testjobber, brukere og biblioteker ble ryddet opp med readback.
Prosessen avsluttet med exit 0; test-DLL-en er borte og testserveren stoppet.

Gjenstar blant annet alternative InternalTargetIds i Sync/Data, manglende/
tomme TargetId-varianter, delt enhet, nye enheter, server/cloud-provider-mal,
ferdige offlinefiler og faktiske klienter. Det er heller ikke bevist at alle
serverruter og header-/timing-varianter er dekket. Full skjerming er fortsatt
ikke bevist; disse resultatene beviser bare de konkrete provde kontrollene.
## Interne Sync-mal og manglende opprettelsesmål (2026-10-11)

-ProbeTargetVariants utvider den eksisterende Sync-maltesten. Interne mal-ID-er
hentes fra eierens faktisk opprettede native jobber. Begge har gyldige,
forskjellige InternalTargetId-verdier; det er ikke konstruerte positive ID-er.

For rettelsen godtok Sync/Data fremmede og blandede InternalTargetIds med 200.
Ingen ferdige filer ble returnert og de malte jobbdataene ble ikke endret, sa
HTTP 200 alene er ikke et bevist datalekkasjetilfelle. Lokal metodeinspeksjon
av SyncService.Post(SyncData) viser at et oppgitt eksternt TargetId overskriver
InternalTargetIds. Uten et eksternt mal kan det innsendte interne feltet brukes.
Moteksemplene er bevart i
`bin/native-library-sync-target-variants-before-validation.json`.
Manglende/null opprettelsesmål ga 400, tom streng ga 500, og mellomrom ga 404.
Ingen nye jobber ble funnet for disse variantene.

Testgrensen validerer na samtlige innsendte interne mal mot native ID-er som
svarer til den autentiserte brukerens eksplisitte EnabledDevices. Dette gjelder
ogsa blandede lister i begge rekkefolger og motstridende eksternt/internt mal.
Hele listen kontrolleres for handleren. Ved broad EnableAllDevices=true er
rettigheten fortsatt bred; det regnes ikke som bevist privat mal-eierskap.

Oppslaget bruker SyncManager.GetInternalTargetId(deviceId, false, token).
En ny metadata-observasjon i Surface bekrefter at den boolske parameteren heter
createIfNotFound, og at metoden kaller SyncRepository.GetTargetId. Valideringen
ber derfor ikke native manager opprette en ny malregistrering. Dette er lokal
metode- og parameterinspeksjon, ikke en paastand om alle mulige cache-endringer.
Observasjonen finnes under SyncTargetLookup i bin/api-inventory.json.

CreateSyncJob avviser na null, manglende, tomme og whitespace-baserte TargetId
for original opprettelse. Kontrollene viste 404 for alle fire varianter.
Dette fjerner ogsa den tidligere 500-feilen pa tom streng i den provde veien.

Den samlede kjoringen med -RequireProtected -ProbeDlna -ProbeSync -ProbeNewRoot
-ProbeDeletedSync -ProbeMultiSourceSync -ProbeMixedSync -ProbeReadParity
-ProbeSyncTargets -ProbeDevicePolicy -ProbeTargetVariants bestod med 486
observasjoner. De 20 nye variantforesporslene hadde alle uendrede tilstands-
avtrykk for begge brukeres native jobber og jobbelementer, og null nye jobber.
Eget internt mal ga 200 hos begge brukere. De 18 fremmede/blandede/ukjente eller
manglende opprettelsesvariantene ga 404. Egen ordinær jobbopprettelse med gyldig
eksternt mal har fortsatt en separat positiv kontroll.
Rapport:
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-targets-device-policy-variants-results.json`.

Jobber, brukere og biblioteker ble ryddet med readback. Kjoringen avsluttet med
exit 0. Etter kontrollen er test-DLL-en borte og ingen EmbyServer-prosess aktiv.
Produksjonspluginen er uendret.

Gjenstar blant annet Sync/Data der bade eksternt og internt mal er utelatt,
andre alternative referanseformer, delte/nye enheter, server/cloud-provider-mal,
brukere med brede enhetstillatelser, ferdige offlinefiler og faktiske klienter.
Eget internt Sync/Data-mal ga et tomt svar i dette miljoet; det beviser ikke
utlevering av en ferdig fil. Full skjerming er fortsatt ikke bevist.
## Sync/Data med implisitte mal (2026-10-11)

Verifikasjonen har na en passiv observator pa faktisk SyncManager.SyncData.
Den leser InternalTargetIds slik native manager mottar dem, uten a endre
argumenter eller returverdi. En admin-beskyttet fixture-rute viser bare sekvens,
om mal er eksplisitte, og en kopi av de interne ID-ene. For hvert testkall
sammenlignes sekvensen for og etter for a unnga a bruke et gammelt funn.
Ved avvisning forventes ingen ny native invokasjon.

For rettelsen kom foresporsler med utelatte eller tomme mal fram til manageren
uten riktig eksplisitt avgrensning. Foresporsel med InternalTargetIds=null ga
400, men observatoren bekreftet at manageren allerede hadde blitt kalt.
400 var dermed ikke bevist inputvalidering for native behandling, slik den
forste tolkningen antok. Rapporten for rettelsen er bevart i
`bin/native-library-sync-implicit-targets-before-scoping.json`.
Ingen ferdige filer ble returnert, og dette er ikke et bevist filutleveringstilfelle.

Testgrensen fyller na InternalTargetIds med eksisterende native mal-ID-er for
brukerens eksplisitte EnabledDevices nar Sync/Data mangler eksternt mal og
interne mal mangler eller er tomme. Oppslag bruker createIfNotFound=false.
Det gir 200 for utelatte mal, tom intern liste, null intern liste og tomt
TargetId, samtidig som native manager bare far det tillatte malet. Hvis ingen
tillatte mal kan finnes, eller feltet ikke kan skrives, avvises foresporselen.
EnableAllDevices=true er fortsatt en bred tillatelse og er ikke bevist isolert.

De 10 gyldige Sync/Data-variantene ble alle observert i den faktiske native
manageren med nøyaktig ett mal: eierens tillatte interne mal. De 10 fremmede/
blandede/ukjente Sync/Data-variantene ble avvist for native manager ble kalt.
Alle 28 variantforesporsler hadde uendrede native jobbelement-/jobbavtrykk for
begge brukere og null nye jobber. De aatte avviste opprettelsesvariantene er
med i disse 28; de bruker ikke SyncData-manageren.

Et samlet forsok stoppet under oppsett med PowerShell OutOfMemoryException.
Det regnes ikke som en bestatt kontroll, og aarsaken er ikke verifisert.
En etterfolgende full kjoring avsluttet med exit 0 og bestod 522 observasjoner:
-RequireProtected -ProbeDlna -ProbeSync -ProbeNewRoot -ProbeDeletedSync
-ProbeMultiSourceSync -ProbeMixedSync -ProbeReadParity -ProbeSyncTargets
-ProbeDevicePolicy -ProbeTargetVariants.
Rapporten med navnet
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-targets-device-policy-variants-results.json`
er oppdatert og erstatter den tidligere mindre kjoringen med samme navn.

Lokal metodeinspeksjon av SyncManager.SyncData og SyncDataUsingSyncJobItemIds
viser at InternalTargetIds kopieres inn i SyncJobItemQuery for GetJobItems.
Metodene bruker ogsa LocalItemIds og kan kalle UpdateSyncJobItemInternal.
Derfor ma local-ID-er og delt enhet undersokes separat; malavgrensning alene
beviser ikke eierskap til alle jobber som kan finnes pa et felles mal.
Disse metodereferansene er lagt til bin/api-inventory.json.

Opprydding av testjobber, brukere og biblioteker hadde vellykket readback.
Etter siste kjoring er test-DLL-en borte og ingen EmbyServer-prosess aktiv.
Produksjonspluginen er uendret. Ferdige offlinefiler er fortsatt ikke provd;
Sync/Data-svarene her er tomme. Delte/nye enheter, brede tillatelser,
LocalItemIds med ulike native referanseformer, server/cloud-provider-mal og
faktiske klienter gjenstar. Full skjerming er fortsatt ikke bevist.
## Delt enhet: Sync/Data endret en annen brukers private jobb (2026-10-11)

-ProbeSharedSync registrerer begge syntetiske brukere pa samme reelle native
DeviceId, native-shared-test, med vanlig innlogging og klientkapabiliteter.
Begge har eksplisitt tillatelse til dette malet. Testen oppretter private jobber
via Sync/Jobs, med hver sin bruker og kilde, og bruker den vanlige klient-ruten
Sync/JobItems/{id}/Transferred til a rapportere overforing. Readback viser at
native jobbelementene er Synced. Dette er en kontroll av metadata/status:
testen produserer ingen konvertert fil og endrer ingen lisens-/funksjonstillatelse.
Det er ikke en positiv kontroll av en ekte ferdig offlinekonvertering.

For rettelsen ga begge Keep own-forsok HTTP 200 og uendret egen tilstand, men
endret den andre brukerens native jobb-/jobbelementavtrykk. Enhetstillatelse og
filtrering av det ferdige HTTP-svaret var dermed utilstrekkelig. Moteksemplene
finnes i `bin/native-library-shared-sync-before-owner-filter.json`.
De to Remove own-forsokene i samme tidlige rapport hadde et feilkonstruert
PowerShell-input: tomt pipeline-resultat ble null LocalItemIds og ga 500.
Det er rettet til en eksplisitt tom array; disse feilene brukes ikke som
bevis for andre-bruker-mutasjon. Keep own-moteksemplene hadde gyldig input.

Runtime-inspeksjon viser at SyncJobItemQuery ikke har en UserId-egenskap.
Testpluginen har derfor en ekstra kontroll pa den faktiske native
SyncManager.GetJobItems-returen mens en autentisert Sync/Data-foresporsel
behandles. Private fremmede kildeelementer fjernes for Sync-manageren kan
kansellere/oppdatere dem. For private egne kilder kontrolleres ogsa at jobben
har riktig UserId. Offentlige/ikke-fixture-elementer beholder sin eksisterende
native behandling. Kallets bruker holdes i AsyncLocal og gjenopprettes sammen
med forrige metadatascope etter service-kallet. Dette er en isolert test av
interne hooks, ikke en ferdig produksjonsimplementasjon.

Den avgrensede kjoringen bestod med 249 observasjoner. Begge brukere og begge
handlingsmodi bestod: Keep own beholdt egne og andre brukerens jobbelementer;
Remove own ga en faktisk endring i egen native jobbtilstand uten a endre den
andre brukerens avtrykk. Det er derfor en positiv kontroll av en fungerende
mutasjonsvei, ikke bare tomme svar eller avvisninger. Sync/Data ga 200 i alle
fire tilfeller. Opprydding mellom tilfellene fjernet bare de aktuelle jobbene.

Den samlede kjoringen bestod med 554 observasjoner og exit 0:
-RequireProtected -ProbeDlna -ProbeSync -ProbeNewRoot -ProbeDeletedSync
-ProbeMultiSourceSync -ProbeMixedSync -ProbeReadParity -ProbeSyncTargets
-ProbeDevicePolicy -ProbeTargetVariants -ProbeSharedSync.
Rapport:
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-targets-device-policy-variants-shared-results.json`.
Den tidligere 522-kjoringen med annet rapportnavn er fortsatt separat.
De fire Shared Sync native state-radene viser OtherStateChanged=false;
bare de to Remove own-radene har OwnStateChanged=true.

Jobber, biblioteker og brukere ble ryddet med readback. Test-DLL-en er borte
og ingen EmbyServer-prosess er aktiv. Produksjonspluginen er uendret.

Dette beviser de provde Sync-metadata-mutasjonene pa delt enhet. Det beviser
ikke ferdig filoverforing, cache pa den faktiske klienten, alle LocalItemIds-
referanseformer, samtidige foresporsler pa delt mal, bred enhetspolicy,
server/cloud-providere eller alle faktiske appklienter. ItemIdsToRemove-kontrollen
bruker den numeriske kilde-ID-en i disse tilfellene; andre serialiserte ID-former
trenger egen kontroll. Full skjerming er fortsatt ikke bevist.
## LocalItemIds: skjult GUID ble oversatt til numerisk ID (2026-10-11)

-ProbeSharedReferences utvider testen pa delt enhet med native numeriske ID-er
og GUID-er i begge standardformater. Egne GUID-er er positive kontroller:
serveren gjenkjenner dem og beholder brukerens egne Synced-jobbelementer.
Status er rapportert gjennom den vanlige Transferred-ruten; ingen ferdig
konvertert fil er produsert.

For rettelsen returnerte Sync/Data en fremmed videos numeriske ID nar klienten
sendte dens GUID i LocalItemIds. Dette ga klienten en ny referanse til skjult
innhold. A gjenta den samme numeriske ID-en klienten allerede sendte inn,
er derimot ingen ny opplysning. Moteksemplet er lagret i
`bin/native-library-local-cache-alias-before-normalization.json`.

Testgrensen skiller derfor ut gyldig formaterte, utilgjengelige eller manglende
numeriske/GUID-cache-referanser for native behandling. Etter behandling legges
bare de nøyaktige innsendte tokenene tilbake i ItemIdsToRemove. Slik kan
klienten rydde cache uten at serveren oversetter skjulte referanser. Egne
referanser behandles fortsatt av native Sync/Data. Tidligere kontroll av
native GetJobItems hindrer mutasjoner av den andre brukerens private jobber.
Dette er en testprototype med interne hooks, ikke produksjonspluginen.

Den avgrensede rapporten har 393 observasjoner og 22 delt-enhetstilfeller:
`bin/native-library-protected-sync-shared-references-results.json`.
Ingen tilfeller endret den andre brukerens native jobb-/jobbelementavtrykk,
returnerte nye fjerningsreferanser eller mistet forventede cache-ryddetokener.
Egne numeriske/GUID-referanser beholdt egen jobb; bare fremmede/manglende
referanser eller tom liste utløste forventet endring i egen jobb.

Dette dekker de provde referanseformene og metadataendringene. Ferdige
synkroniserte filer, faktisk klientcache, samtidige foresporsler, brede
enhetstillatelser og server/cloud-mal er fortsatt ikke bevist. Full skjerming
for alle klienter er fortsatt uavklart.

Samlet kjoring med alle tidligere flagg og -ProbeSharedReferences bestod:
698 observasjoner, ingen rapporterte lekkasjer, exit 0. Rapport:
`bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-targets-device-policy-variants-shared-references-results.json`.
Opprydding hadde vellykket readback; test-DLL fjernet og testserver stoppet.


## Skjult mot manglende LocalItemIds (2026-10-11)

Testen sammenligner na fremmed numerisk ID, GUID N og GUID D med en manglende
referanse for begge brukere. Bare det konkrete innsendte cache-tokenet byttes
med en felles plassholder i hele det parsede JSON-svaret. HTTP-status og begge
brukeres faktiske native jobbendringer sammenlignes ogsa. Alle seks
sammenligninger bestod; egne GUID-er beholdt sine positive kontroller.

Ny avgrenset kjoring: 399 observasjoner, exit 0, ingen rapporterte lekkasjer.
`bin/native-library-protected-sync-shared-references-results.json` er oppdatert
og har seks SameNormalizedResponseAndState=true-rader. Tidligere 393 er den
eldre kjoringen uten disse seks sammenligningene; samlet 698-rapport er separat.

Dette beviser samme parsede svar, status og provde metadataeffekter for disse
referansene. Det beviser ikke lik svartid, alle HTTP-headere, ferdige filer
eller faktisk klientcache. Test-DLL er fjernet, opprydding bestod og ingen
EmbyServer-prosess er aktiv. Produksjonspluginen er uendret.

## Samtidig Sync/Data pa delt enhet (2026-10-11)

-ProbeConcurrentSync sender 24 foresporsler per scenario, annenhver fra hver
av de to syntetiske brukerne. Fire scenarioer dekker at aktor beholder egen
GUID-cache eller rydder egen jobb, mens den andre brukeren beholder sin cache.
Begge sender fremmed GUID i behold-scenarioene for a kontrollere at
AsyncLocal-subjekt og stale-cache-tokener ikke blandes mellom foresporsler.

En passiv prefix/postfix/finalizer-observator pa faktisk native SyncData
registrerer aktive kall fra autentiserte brukere til native Task er ferdig.
Den teller innkommende kall som overlapper et aktivt kall fra en annen bruker.
Den endrer ikke native Task, svar, funksjonstillatelse eller tidsplan og legger
ikke inn forsinkelser. Observatorens lock beskytter kun tellere.

Alle fire scenarioer bestod. Hver hadde 24 faktiske native kall og 24 HTTP
200-svar, ingen uventede cache-referanser og alle forventede ryddetokener.
CrossSubjectOverlaps var henholdsvis 16, 11, 4 og 4; dette er antall innkommende
kall med en aktiv annen bruker, ikke antall samtidige par. ActiveCallsAfter=0.
Begge behold-scenarioer endret ingen jobbtilstand. Begge rydd-scenarioer
endret egen native jobbtilstand uten a endre den andre brukerens avtrykk.

Avgrenset kjoring med alle tidligere Sync/cache-kontroller bestod med 431
observasjoner og exit 0. Rapport:
`bin/native-library-protected-sync-shared-references-concurrent-results.json`.
De 96 samtidige HTTP-kallene oppsummeres i fire rader; observasjonstallet er
ikke et antall unike HTTP-foresporsler. Rapporten inneholder dessuten de
seks tidligere skjult/manglende-sammenligningene.

Dette beviser de provde samtidige Sync/Data-metadata- og cache-tokenforlopene
med eksplisitt enhetspolicy pa ett delt mal. Det beviser ikke alle races,
ferdige offlinefiler, fysisk klientcache eller alle apper. Full skjerming er
fortsatt ikke bevist. Produksjonspluginen er uendret.

## Bred enhetspolicy og Sync/Data uten mal (2026-10-11)

-ProbeBroadSync bruker EnableAllDevices=true for begge vanlige testbrukere,
med readback av faktisk policy. De tidligere delt-enhet-, GUID-,
skjult/manglende- og samtidighetskontrollene kjorer med denne brede policyen.
Fire ekstra tilfeller sender Sync/Data uten TargetId eller InternalTargetIds.
Her ligger de to brukernes Synced-metadatajobber pa forskjellige reelle
native mal, native-a og native-b, mens begge sesjoner bruker delt DeviceId.

Native input-observatoren bekrefter tom InternalTargetIds-array i alle fire
implisitte tilfeller. HasExplicitTargets=true betyr her bare at native array
er ikke-null, ikke at den inneholder et mal. Testgrensen snevrer derfor ikke
kallet inn til brukerens EnabledDevices for a fa et passerende resultat.

Begge brukere kunne beholde egen GUID-cache uten a endre noen jobb. Begge
kunne rydde egen jobb via tom LocalItemIds uten a endre den andres native
jobbavtrykk. Fremmed GUID ble gjentatt som innsendt cache-ryddetoken, uten ny
numerisk referanse. Samtidighetskontrollene bestod igjen med 96 native/HTTP
kall og faktisk kryssbrukeroverlapp i alle fire scenarioer.

Kjoring: 469 observasjoner, ingen rapporterte lekkasjer, exit 0. Rapport:
`bin/native-library-protected-sync-shared-references-concurrent-broad-results.json`.
Opprydding bestod; test-DLL fjernet og ingen EmbyServer-prosess er aktiv.
Produksjonspluginen er uendret.

Dette lukker det konkrete hullet i beviset for private Sync/Data-metadatajobber
under bred enhetspolicy og implisitte device-mal. Det beviser ikke eierskap
eller personvern for selve enhetsnavnene; bred native policy tillater fortsatt
alle enheter. Det beviser heller ikke ferdige filer, server/cloud-providere,
appcache eller alle ruter. Full skjerming er fortsatt ikke bevist.

## Native IsVisible=false stopper ikke direkte tilgang (2026-10-11)

Dokumentasjonen for BaseItem har en virtuell IsVisible(User) som kan
overstyres, og en IsVisibleStandalone(User). Dette er en mulig mekanisme a
undersoke, men dokumentasjonen garanterer ikke at alle API-ruter bruker den.
-ProbeVisibility installerer kun passive postfix-observatorer pa faktisk
deklarerte BaseItem/Video-metoder; ingen returverdier endres.

For hver bruker kalles begge native metoder eksplisitt pa den andres
syntetiske video. Begge gir false. Observatoren registrerer tre kall (det ene
native kallet kan kalle det andre), som gir en positiv instrumenteringskontroll.
Deretter nullstilles observasjonen for hver HTTP-foresporsel mens den ekstra
privacy-guard fortsatt er deaktivert.

Begge brukere far likevel HTTP 200 og fremmede videometadata fra
Users/{actual-user}/Items/{foreign-video} og Items/{foreign-video}/PlaybackInfo
med faktisk UserId. Begge far ogsa hele 11071-byte MP4-filen fra
Videos/{foreign-video}/stream.mp4?Static=true og Items/{foreign-video}/Download.
Ingen av de atte foresporslene gir registrerte visibility-kall for den videoen.
Fravaer av registrerte kall alene utelukker ikke blant annet JIT-inlining;
det avgjorende moteksemplet er et faktisk false-resultat sammen med vellykket
uautorisert native tilgang. Det er ikke provd en egen persistert Video-subklasse
med override, og testen beviser ikke at alle mulige SDK-design er umulige.

Etterpa aktiveres tidligere testbeskyttelse og serveren startes om. De 58
vanlige beskyttelseskontrollene passerer fortsatt. Hele kjoringen har 76
observasjoner og exit 0. Rapport:
`bin/native-library-protected-visibility-results.json`.
Baseline-radene dokumenterer bevisst tillatt fremmed tilgang uten guard;
lekkasjeoppsummeringen pa slutten teller bare beskyttede kontroller.

En forste instrumenteringskjoring feilet fordi Harmony fikk en arvet
ReflectedType-referanse. Observatoren ble rettet til DeclaredOnly-metoder,
build bestod uten advarsler, og testen over er en ny komplett kjoring.
Opprydding bestod; test-DLL er fjernet og testserveren stoppet.
Produksjonspluginen er uendret.

Konklusjon: det eksisterende native synlighetsresultatet er ikke en generell
sikkerhetsgrense for de provde direkte rutene. En plan ma ikke godkjenne full
skjerming bare fordi IsVisible, EnabledFolders eller kanallisten ser riktig ut.
Kilde: https://dev.emby.media/reference/pluginapi/MediaBrowser.Controller.Entities.BaseItem.html
