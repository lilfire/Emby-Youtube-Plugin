# A: item-list gate — fewer per-item costs (2026-10-14)

Oppfølging 2026-10-15: [betrodd kildeoversikt og native skrivebarriere](../PrivateInventory/IMPLEMENTATION.md)
er implementert og prøvd på DLL `D062C89B…`. Varme sekvensielle Items tar
0,56–0,57 s og Tags 0,80–0,86 s i samme syntetiske bibliotek. Seks parallelle
hjemmekall gir medianer på 0,65–1,11 s, alle med 200. Lilflix er fortsatt uendret.
Runde 1–4 nedenfor er historikk; den nye rapporten gir gjeldende status.

Kapittel A, punktet «Erstatt full biblioteksskanning …». Denne leveransen
erstatter **ikke** skanningen; den fjerner kostnaden per element. Ingen
produksjonsdata er brukt i målingene, og Lilflix er uendret av denne leveransen.

## Årsak (fra koden og Lilflix-gate-loggen)

For hvert av ~104 000 elementer per listekall gjorde den gamle prefixen:

- 2–3 JSON-lesinger fra disk (bindingsregister, journal og profil);
- `GetVirtualFolders()` og en foreldrevandring med `GetItemById`;
- for hvert Genre/Studio/Tag-objekt (2 829 på Lilflix) en egen native
  brukerspørring, med `GetItemLinks` for hver kilde.

Det siste forklarer hvorfor brukere (~31 s) var mye tregere enn servernøkkel (~6 s).
Servernøkkelen avvises direkte for indeksobjekter uten spørringer.

`denied=2829` for servernøkkel mot `denied=7` for brukere er forklart:
2 788 + 32 + 9 = 2 829 er nøyaktig de tre stiløse indekstypene (Genre/Studio/Tag)
i Lilflix sin `library.db`. Disse avvises alltid uten konto
(`PersonalYouTubeNativeAccess.DecideItem`, linjen med `authenticatedUser == null`).
Det er altså ingen lekkasje.

## Endring

- `PersonalYouTubeNativeBindings.Ledger`: én validert lesing per forespørsel,
  med oppslag i ordbøker. Profilen leses én gang per eier.
  `DecideItem` bruker samme kode.
- `PersonalYouTubePublicationJournal.Snapshot`: én lesing av register og journal per
  forespørsel. `DecideSources` bruker samme kode. Manglende eller korrupt fil
  feiler fortsatt hele forespørselen.
- `PersonalYouTubeNativeAccess.ListContext`: `GetVirtualFolders()` én gang, og
  foreldre slås opp i inventaret med fallback til `GetItemById`. Hvert element får
  fortsatt hele den ordinære avgjørelsen. Genre/Studio/Tag avgjøres med én
  kildespørring per type (bolker på 500 ID-er) i stedet for én per objekt.
  Koblingene verifiseres per kilde med `GetItemLinks`, med samme regel som før.
- Gaten logger `scanMs/ordinaryMs/metadataMs/metadataItems` når et kall tar over 1 s.

## Runde 2: indeksobjekter under 1 s (DLL `BB374DED…`)

Fordelingen viste at kostnaden lå i å materialisere kilder, ikke i lenkelesingen:
56 965 `BaseItem` fra 8 spørringer tok ~0,9 s, mens 13 167 `GetItemLinks` tok ~0,2 s.

- Kildespørringene bruker nå `GetInternalItemIds` med samme spørring. Dekompilert 4.10
  viser at både `LibraryManager.GetItemList` og `GetInternalItemIds` kjører
  `SetUserAndParents` og `QueryItemsInTransaction` med samme filter; ID-varianten
  velger bare `Id`. Kildene slås opp i forespørselens inventar. En ID som ikke
  kan hentes med `GetItemById`, hoppes over, slik den ville manglet i `GetItemList`.
- Én delt lesekontekst (`GetReadDataContext`) og én `GetItemLinks` per kilde for
  alle tre typer. En type godskrives fortsatt bare fra kilder som typens egen
  spørring returnerte.
- Diagnostikken logger også `metadataQueryMs/metadataLinkMs/metadataSources/metadataLinkReads`.

| Del av brukerkall (62 566 elementer) | Runde 1 | Runde 2 |
|---|---|---|
| Indeksobjekter (Genre/Studio/Tag) | 1,07–1,6 s | **0,44–0,46 s** |
| Hele kallet, median (Views/Items/Latest/Counts/Genres) | 1,6–1,9 s | **0,97–1,06 s** |
| Servernøkkel Counts / VirtualFolders / Items | 1,9 / 0,52 / 0,78 s | 1,9 / 0,52 / 0,78 s |

Resten av et brukerkall er skanning (~0,33 s) og ordinære avgjørelser (~0,24 s).
Servernøkkelens Counts på 1,9 s ble ikke undersøkt nærmere.
Matrisene på `BB374DED…` ga samme resultat som tabellen under: komponentprobe 16/16,
servernøkkel 36, Metadata 65, Counts 107, Suggestions 14 og Search 416 uten avvik, og
Standard med de 12 kjente Views-avvikene uten fremmed innhold.

## Runde 3: Counts med servernøkkel og Tags-ruten (DLL `7471D487…`)

**Counts med servernøkkel (1,9 s):** prefixen tok bare ~0,5 s, mens resten gikk med i native
`LibraryService.Get(GetItemCounts)`. Den kjører 7 separate spørringer (Album, Episode,
Movie, Series, Song, MusicVideo og Book), og hver av dem fikk alle 3 530 forbudte
Genre/Studio/Tag-ID-er som SQL-ekskluderinger. Nå gjelder dette: når en vanlig elementspørring
(`GetItemList/GetItemIds/GetItemsResult`) bare tillater konkrete medietyper, kan den ikke returnere
et indeksobjekt. Da registreres disse ID-ene som dekket av typefilteret i stedet for å sendes som
ekskluderinger. Aggregeringene for Genres/Studios/Tags får dem fortsatt eksplisitt. Coverage-kravet
(alle forbudte ID-er dekket i hver spørring) er uendret.

**Tags-ruten (35 s):** `VisibleTagIds` kjørte tre ganger per forespørsel (spørring, resultat og
skriver). Hver gang hentet den alle brukerens elementer og kjørte den gamle avgjørelsen per element.
Nå brukes samme kilde- og lenkeregel som for andre indeksobjekter. Dette gir samme mengde for
kjente tagger, fordi en kilde som lenker T direkte returneres av Ts egen `TagIds`-spørring.
Spørringen bruker prefixens resultat. Resultat- og skriverkontrollen kjører en fersk beregning
med nytt lagringsøyeblikksbilde og `GetItemById`. Nye tagger som ikke finnes i inventaret,
utelates, så resultatet kan bare bli strengere.

| Kall (62 566 elementer, median) | Før runde 3 | Runde 3 |
|---|---|---|
| Servernøkkel Counts | 1,9 s | **0,52–0,58 s** |
| Tags (bruker/admin) | 35,1 s | **2,3 s** (prefix ~1,0 s + 2 ferske kontroller à 0,6–0,95 s) |
| Øvrige brukerkall | 1,0–1,1 s | 1,0–1,26 s (uendret innen variasjon) |

Verifikasjon på `7471D487…`: komponentprobe 16/16, servernøkkel 36, Metadata 65, Counts 107,
Suggestions 14 og Search 416 uten avvik. Skriverkappløp uten avvik: Metadata/Tags 69,
Metadata/Tags med lease 70, Metadata/Genres 69, Metadata/Studios med lease 70, Counts/Counts 111
og Counts/Counts med lease 112. Standard og Standard/Latest-skriverkappløp gir bare de
12 kjente Views-avvikene, uten fremmed innhold.

Gjenstår: Tags er fortsatt over 1 s. De to ferske kontrollene er bevisst ikke gjenbrukt,
fordi de er tilbakekallingsgarantien.

## Runde 4: ferske kildehint for Tags (DLL `B27179ED…`)

Fortsettelse etter runde 3. Prefixen registrerer ett native kilde-ID per godkjent
metadata-ID i forespørselen. Ved resultat og skriver brukes kilde-ID-ene kun som
søkehint: en ny native brukerspørring med TagIds og ItemIds må returnere kilden,
og en ny lesekontekst kontrollerer kilde, foreldre, eierskap, journal og faktisk
taglenke. Tidligere tilgangsavgjørelser gjenbrukes ikke. Hvis hintene ikke dekker
taggene, kjører den opprinnelige, ubegrensede kildespørringen. De ferske kontrollene
trenger bare taggene som faktisk ble tillatt i native query, inkludert eventuelt
eksisterende ItemIds-filter; øvrige tagger kan ikke komme inn i resultatet.

Isolert Emby **4.10.1.0 på Windows**, samme syntetiske bibliotek og median av tre
runder, gir følgende. Alle 51 HTTP-kall ga 200 og antallene er uendret.

| Kall | Runde 3 | Runde 4 |
|---|---|---|
| Tags, admin / bruker | ~2,3 s | **1,316 / 1,267 s** |
| Items?Limit=12, admin / bruker | ~1,0–1,26 s | 1,107 / 1,105 s |
| Views, admin / bruker | ~1,0–1,26 s | 1,088 / 0,929 s |
| Counts, servernøkkel | ~0,55 s | 0,552 s |

Kravet under ett sekund er fortsatt åpent. Full biblioteksskanning er beholdt.
Lilflix er ikke endret eller målt i denne runden.

Eksakt SHA-256: `B27179ED140841FCA94525F9DB1941619148EA406F7FE47992E079905ACA3C3A`.
[Ytelsesbevis](LATENCY-WITNESSES.json), [komponentbevis](WITNESS-EVIDENCE.json)
og [native matriser](NATIVE-WITNESS-EVIDENCE.json) lagrer resultatene.

- Bygg: 0 feil og 0 advarsler. ItemListGate404-komponentprobe: 16/16.
- Ny WitnessProbe: 7/7. Fungerende hint, endret native synlighet, endret lenke,
  alternativ kilde, manglende kilde, endret forelder og deaktivert konto er prøvd.
  Dette er produksjonsresolver med bibliotekadapter over offentlige testkilder,
  ikke native SQL eller privat HTTP-eierskap.
- Faktisk native Metadata-matrise: 65 observasjoner uten avvik. Tags-skriverkappløp:
  69 uten avvik. Tags med skriverlease: 70 uten avvik. Matrisene har eierkontroll,
  fremmedkontroll, manipulert UserId, profilsletting og omstart.
- Ingen ekte Google-transport eller produksjonsdata. Native testbrukere,
  biblioteker, media, profilmappe og fixture-journal er fjernet. Begge isolerte
  servere er stoppet ved separat sluttoppslag; det syntetiske ytelsesbiblioteket
  beholdes under ignorert bin for reproduksjon.

Første metadataoppstart kolliderte med den fortsatt aktive ytelsesinstansen.
Første lease-oppstart traff også et kort prosessavslutningsvindu fra forrige
matrise. Begge oppstarter manglet observasjoner og er ikke regnet som beståtte;
de komplette matrisene over ble kjørt på nytt. Fixture-oppryddingens umiddelbare
ServerStopped-felt er false, mens det senere, separate prosessoppslaget er true.
Dette er en begrensning i testverktøyets oppstart/opprydding, ikke et observert
produktavvik. Ingen nye native feilinjeksjons-/Linux-prøver er utført.

## Verifikasjon runde 1 (isolert Emby 4.10.1.0, Windows, DLL `0904173A…`)

| Matrise | Observasjoner | Avvik |
|---|---|---|
| Komponentprobe ItemListGate404 | 16 | 0 |
| Servernøkkel + eierkontroller (`PERSONAL_YOUTUBE_A_PROBE`) | 36 | 0 |
| Metadata (Genres/Studios/Tags), `-RequireIsolation` | 65 | 0 |
| Counts, `-RequireIsolation` | 107 | 0 |
| Suggestions, `-RequireIsolation` | 14 | 0 |
| Search, `-RequireIsolation` | 416 | 0 |
| Standard, `-RequireIsolation` | 26 | 12 kjente Views-avvik |

Standard-avvikene er de samme 12 Views-radene som på HEAD. De skyldes en ekstra
«Playlists»-visning i testmiljøet. Ingen av dem har fremmed innhold, og eget
innhold er til stede der det skal være.

Komponentproben setter nå en ekte `PersonalYouTubeNativeAccess` over en tom
datamappe, fordi prefixen alltid bygger en listekontekst.

## Ytelse (separat isolert instans, port 18097, syntetisk bibliotek)

Biblioteket er laget av `New-SyntheticLibrary.ps1`: 20 000 `.strm`-filmer med NFO.
Det gir 62 566 elementer, inkludert personer, og 3 530 Genre/Studio/Tag. Målingen er gjort av
`Invoke-GateLatency.ps1`, med median av 3 runder.

| Inngang | Basislinje | Ny |
|---|---|---|
| Bruker/admin: Views, Items?Limit=12, Latest, Counts, Genres | 42,6–44,4 s | 1,64–1,95 s |
| Servernøkkel: Counts / VirtualFolders / Items | 13,5–14,9 s | 0,55–1,90 s |

Antallene er identiske i begge løp (20 000 filmer, 30 sjangre, 2 visninger, 16 nyeste).
Tidsfordeling for nye brukerkall er scan ~0,3 s, ordinær ~0,3 s og metadata ~1,2–1,6 s.
**Kravet `< 1 s` er ikke nådd.** Metadata-bolken, med `GetItemLinks` per kilde,
er nå den største gjenværende kostnaden.

Basislinjen er bygget fra samme kilde uten denne endringen, i en annen mappe. Hashen
(`715AFC2C…`) er derfor ikke lik den installerte `4FC47099…`, sannsynligvis fordi
byggestien ligger i DLL-en. Kildeinnholdet er det samme.

## Begrensninger

- Ingen måling på Lilflix. En kopi av Lilflix sin `library.db` til PC-en ble avvist
  av tillatelsessjekken (produksjonsdata). Kopien på OMV er slettet, og ingenting
  ble overført.
- Det syntetiske biblioteket mangler private A/B-data. Kostnaden for private
  avgjørelser er dekket av korrekthetsmatrisene, ikke av ytelsesmålingen.
- Tags-ruten har nå ferske kildehint, men medianen er fortsatt over ett sekund.
- Full skanning gjenstår (~0,3 s her, ukjent på Lilflix). Det gjør også en betrodd
  privat kildeoversikt og eventuell caching med invalidering.
