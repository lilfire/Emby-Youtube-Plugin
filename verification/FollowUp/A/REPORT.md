# A – API, oppdagelse og mutasjoner

Undersøkt 2026-10-14 på **isolert Windows Emby Server 4.10.1.0**, plugin
**2.0.10-alpha.1**. Produksjons-DLL SHA-256:
`AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
Utgangspunkt: `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`, med nye lokale
testfiler. Produksjonsmodulene er uendret. Lilflix og klientene er ikke endret.

**Konklusjon:** undersøkelsen påviser åpne P0-hull i Similar,
filmanbefalinger, metadatafamilier og spillelister. Dagens produksjonskontroller
er ikke full API-skjerming. Utvidet GetItems-paging og de fire undersøkte
tilbakekallingsgrensene fungerer innenfor prøvd scope. Kapittelets samlede
ferdigkrav er fortsatt ikke oppfylt; uverifiserte ruter og nye rettelser står
åpne i TODO. Avvikstallene i SUMMARY er testassertions, ikke antall sårbarheter.

## Testinngang og faktisk kode

`Run-A.ps1` bruker den eksisterende produksjons-/native-fixturens oppsett,
profilbinding, sletting, omstart og opprydding. To vanlige testkontoer har
`EnableAllFolders=true`, lest tilbake, og hver sin syntetiske native Movie
med privat binding til produksjonens `PersonalYouTubeNativeBindings`.
Den eksperimentelle privacy-guarden er eksplisitt deaktivert; produksjonens
service- og listekontroller må være installert før matrisen starter.

HTTP-kallene går til faktiske Emby-ruter. Binding av syntetiske native røtter
er en testadapter, og er ikke hele Google → buffer → publiseringskjeden.
Ingen Google-transport, yt-dlp, nøkler eller ekte privat innhold brukes.
`ApiAudit.cs` er bare kompilert inn i **PersonalChannelsFixture.dll**.
Den leser deklarerte ruter, servicemetoder, IL-hash og direkte kilde-/factory-
referanser, gir avgrenset readback av native userdata, og rydder bare
navngitte A-prøvespillelister innenfor fixturens `userplaylists`.

Privatløpet har både A og B privat. Offentligløpet lar A-roten være ubundet,
mens B fortsatt er privat. Begge kjører aktiv profil, lagret sletting av A
og faktisk serveromstart. Det offentlige innholdet består dermed av samme
native type og metadata som den private kontrollen. Dette er en vanlig
native offentlig bibliotekskontroll, ikke regresjon for alle medietyper.

## Rutekart og evidens

[ROUTES.csv](ROUTES.csv) inneholder alle **587 deklarerte ruter** i det
innlastede inventaret: rute/verb, faktisk DTO, identitetsfelt, servicemetode,
IL-hash, direkte native kildehenvisninger, returtype, factoryhenvisninger,
teststatus og evidensantall. Flere alternative HTTP-ruter deler samme DTO.
Manglende verb i RouteAttribute er merket ANY; det er ikke bevist at hvert
mulig HTTP-verb er registrert eller akseptert av serveren.

Dette er et deklarert inventar, ikke bevis for alle runtime-aliaser eller
hele transitive kilde-/skriverkjeder. «Prøvd» betyr den oppgitte matrisen,
ikke universal støtte. «Åpent hull: manglende rutebevis» er manglende bevis,
ikke påvist lekkasje. «Ikke relevant for A» flytter ikke andre kapitlers
ansvar og godkjenner ikke dem. Positive og negative innholdskontroller
forklares nedenfor; tomme svar regnes ikke som positiv innholdskontroll.

[SUMMARY.json](SUMMARY.json), [privat evidens](PRIVATE-EVIDENCE.json) og
[offentlig evidens](PUBLIC-EVIDENCE.json) er portable avlesninger. Rå, lokale
JSON-svar og full IL-inspeksjon ligger i ignorert `bin/`. Regenerering:

Begge sluttmatrisene fullførte **495 observasjoner**. Privatløpet har 121
og offentligløpet 127 mislykkede assertions, fordelt på de beskrevne hullene,
HTTP-/identitetsavvikene og manglende positive rating-kontrollene. Rutekartet
har 25 ruter med observerte avvik, 92 A-relevante ruter med manglende
rutebevis, 8 med avgrenset prøvd matrise og 462 utenfor A. De 84 eksplisitte
count/page-kontrollene i hvert løp bestod. Privatløpets native readback
bekrefter at alle tillatte egenmutasjoner beholdt de andre userdata-
tilstandene uendret.

```powershell
dotnet build verification/PersonalChannels/PersonalChannels.csproj -c Release --no-restore
powershell -NoProfile -File verification/FollowUp/A/Run-A.ps1
powershell -NoProfile -File verification/FollowUp/A/Run-A.ps1 -PublicSource
powershell -NoProfile -File verification/FollowUp/A/Run-Races.ps1
python verification/FollowUp/A/Build-RouteMap.py
```

Fixturen bruker den eksisterende isolerte porten 18096 og starter bare når
ingen Emby-prosess eller lytter på den porten er aktiv. Løpene er sekvensielle.
Delte fixture-journaler gjenbrukes bare etter verifisert opprydding.

## Påviste feil og minimale reproduksjoner

| Familie | Faktisk kontroll | Funn / status |
|---|---|---|
| Similar | `GET /Items/{ownVideo}/Similar?UserId={actualUser}` | Returnerer den andre kontoens private videotittel og ID. Det offentlige A-innholdet kan også returneres legitimt til B. |
| Alternative Similar | `/Movies`, `/Shows`, `/Trailers`, `/Albums`, `/Artists`, `/Games/{Id}/Similar` | Alle sju ruteformer bruker `Emby.Api.Library.GetSimilarItems` og returnerer samme fremmede native Movie i privatløpet. Ruteprefikset er ikke en medietypegaranti. |
| Filmanbefalinger | `GET /Movies/Recommendations?UserId={actualOrOther}` | Returnerer begge private videotitler/ID-er. Egne treff er positiv kontroll; fremmede treff er negativt moteksempel. |
| År | `GET /Years?UserId={actualOrOther}` | Begge kontoer får både 2001 og 2002, selv om hvert år bare finnes i én privat kilde. Offentlig A-år er legitimt for B. |
| Klassifisering | `GET /OfficialRatings?UserId=…` | Begge får `PrivateNativeRating_a` og `_b`. Dette er metadataoversikt, forskjellig fra brukerens like/rating-mutasjon. |
| Personer | `GET /Persons?UserId=…`, `/Persons/PrivateNativePerson_{a|b}?UserId=…` | Oversikt og direkte navn gir den andre kildens private personnavn/metadata. Eget navn returneres også. |
| Spillelisteoppretting | `POST /Playlists`, body med egen `UserId`, egen/fremmed/blandet `Ids` | Fremmede og blandede kilder aksepteres, og faktiske playlist-items gir fremmede titler/ID-er. |
| Spillelistetillegg | `POST /Playlists/{ownPlaylist}/Items?UserId={actual}&Ids={foreignVideo}` | Native tillegg aksepteres; etterfølgende `GET …/Items` viser fremmed video. Egen B-video gir positiv innholdskontroll. |

Similar-kallene øker verken service- eller query-tellerne for
`PersonalYouTubeItemListGate`. Faktisk handler er
`LibraryService.Get(GetSimilarItems)` med IL-hash
`0400230C308E1B7CAB29D8AEBE805809308502069BA78811E919219CB1D9C384`. Den bygger resultat via `GetSimilarItemsResult` etter
native itemoppslag. MovieRecommendations går gjennom
`MoviesService.Get(GetMovieRecommendations)` og
`GetRecommendationCategories`, med handlerhash
`DF0B862FB49E0DCACFEE281D84BACA421A975391EA3EA203F579BE84033A2ACE`.
Disse DTO-ene finnes ikke i produksjonslistens scope-tabell.

Metadata-/anbefalingsmoteksemplene består etter A-profilsletting og omstart:
ny serverutlevering skjer fortsatt gjennom de ubeskyttede familiene.
Spillelisteprøvene kjøres mens profilene er aktive, med faktisk native
tillegg og resultatreadback. Avledede spillelister etter profilsletting,
removal, innholdsracer og omstart har ennå ikke eget bevis.

Første egen A-spilleliste ble midlertidig lest som tom rett etter oppretting.
Den tomme responsen brukes ikke som positiv innholdskontroll. Fremmed tillegg,
blandet oppretting og B sin egen innholdsrespons ga reelle metadata.

## Fungerende og avgrensede kontroller

**GetItems:** begge native ruteformer (`Items` og `Users/{UserId}/Items`)
prøves med første/siste tilgjengelige side, side etter slutten, Limit=0,
SortName/descending, DateCreated/ascending, IsUnplayed, blandede batch-ID-er
og fremmed privat ParentId. Privat aktiv eier får eget treff/count=1;
batch-ID-er med begge kilder returnerer bare egen kilde; privat fremmed
ParentId gir tomt resultat/count=0. Limit=0 gir tom side med count=1.
Native side etter slutten gir count=0; dette må ikke feilaktig kreves lik
totalen fra en full side. Offentlig A og privat B prøves i samme matrise.
Dette er to kilder, ikke stor datamengde, alle filtre eller alle sorteringer.

**Favoritt, played-state og rating:** POST, DELETE og alternative
`/Delete`-POST former prøves med eget/fremmed element og eget/manipulert
UserId. Native userdata for begge kontoer og begge kilder leses før/etter.
Privat eier kan sette/nullstille egen favoritt/played-state; fremmed kilde og manipulert
UserId avvises uten endring av de fire tilstandene. `Likes`-DTO-en må
observeres gjennom faktisk native **Rating**; UserItemData har ikke et
Likes-medlem på denne builden. Tidlig testadapter antok Likes; den er rettet
til Rating før sluttevidensen. Likevel gir egen rating-set HTTP 200 uten
observerbar Rating-verdi i native readback. Rating-ruten har dermed
**manglende positivt mutasjonsbevis**, og godkjennes ikke som fungerende.
De to private rating-set-avvikene er ikke påvist personvernlekkasje.

Ved offentlig A-kilde aksepterer native mutasjoner også manipulert UserId.
Readback viser endring av den oppgitte andre kontoens favoritt/played-
tilstand. Produksjonsgaten lar offentlig innhold gå til native behandling.
Dette er et dokumentert identitets-/mutasjonsspørsmål for offentlig innhold,
ikke bevis på fremmed privat tilgang. Det krever eksplisitt kontraktvalg og
sammenligning med native baseline før en generell identitetsrettelse.

**Anonym:** Similar, anbefalinger, Years og Persons gir autentiseringsavslag.
Dette retter ikke lekkasjene mellom innloggede brukere. Refresh med kjent
privat ID aksepteres derimot med HTTP 200 fra også anonym forespørsel.
Handler-IL går til `QueueRefresh`; fullført metadata-/filendring er ikke
instrumentert. Status er åpen autentiserings-/bivirkningsundersøkelse, ikke
en påstand om bevist skade. UpdateItem-prøven med gyldig body avvises.

**Manglende positive innholdskontroller:** Artist/AlbumArtists/Prefixes og
MusicGenres er prøvd, men de syntetiske Movie-kildene gir ikke meningsfullt
positivt musikkinnhold. Person Credits gir ingen positiv credits-nyttelast.
`/Items/{personId}` gir 404 og brukes ikke som bevis for den egentlige
`/Users/{UserId}/Items/{Id}`-detaljruten. Disse er uttrykkelig uverifisert,
ikke godkjent ut fra tom respons. Øvrige navn-/ID-familier står i rutekartet.

## Samtidighet ved faktiske grenser

[RACE-EVIDENCE.json](RACE-EVIDENCE.json) dokumenterer fire nye sekvensielle
løp av eksisterende produksjonsprøver, alle Completed=true og exit 0:

| Grense | Observasjoner | Resultat |
|---|---:|---|
| Etter inventory, før native query | 41 | Sletting fullføres; oppdatert native query gir tomt autorisert svar/count=0. |
| Native task ferdig, før resultatwrapper | 42 | Tidligere resultat avvises med 404 etter sletting. |
| Faktisk `WriteToAsync`, før skriverkontroll | 42 | Tidligere resultat avvises med 404, uten privat innhold/entityheadere. |
| Etter skriverkontroll med eierlås | 44 | A-sletting venter; B-profilendring lykkes; godkjent A-svar skrives før sletting fullføres. Held=false/Waiting=0 etterpå. |

Pauser er timing-adaptere ved faktiske native metoder/tasks/writers, ikke
erstatning av HTTP-responsen. Query-/resultat-/skriverkontrollene er reell
produksjonskode. Prøvene omfatter ikke alle ubeskyttede nye familier,
favoritt-/rating-/played-mutasjoners I/O-racer, nye medlemmer eller alle
native metadata-/providerendringer. Request-scope alene godkjennes ikke.

Fixture-DLL for disse fire løpene hadde SHA-256
`EFB58F2EB800971C583B5E95DC1B87907ECF3ED2D1DC18998B82BFE99656797F`;
produksjons-DLL-en var den samme som oppgitt øverst. Sluttmatrisenes
fixturehash og source-commit er lagret separat i SUMMARY.

## Rettelsesforslag og avhengigheter

1. **A:** inkluder den verifiserte Similar-DTO-en i både kilde/listescope
   og frøreferansekontroll. Resultatfiltrering alene stopper ikke private
   frø, global telling/paging eller kildeendringer. Verifiser faktisk
   `GetSimilarItemsResult` og factory/skriver før allowlist utvides.
2. **A:** auditer anbefalingskategorienes samtlige kilder og eventuell
   cache før DTO/filtering integreres. Returnert kategori/etikett/teller
   kan lekke selv om videoarrayen filtreres.
3. **A:** bind Years, OfficialRatings og Persons til synlige autoriserte
   native kilder, inkludert shared/public metadata og direkte navn/ID.
   Indeks-ID-er trenger selvstendig kildeproveniens, slik Tags allerede har.
4. **A/E/F:** autoriser alle spillelistekilder før native oppretting/tillegg,
   bind avledede referanser til eier/generasjon, og prøv native persisted
   readback, removal, omstart og sletting. En spilleliste med privat kilde
   kan ikke uten videre behandles som offentlig bare fordi roten er ubundet.
5. **A/F:** avklar offentlig userdata-mutasjon med manipulert UserId og
   Refresh-autentisering. Ikke hev et observert 200 til bevist filendring.
6. **B/C/D/H:** bruk rutekartets faktiske DTO-er og kildehenvisninger, men
   ikke anta at A inventaret beviser Sync, asset/video-bytes eller klientstøtte.

Ingen allowlist eller produksjonshook er utvidet i denne undersøkelsen.
En rettelse må følges av positiv eier/offentlig kontroll, negativ fremmed/
slettet kontroll, telling/paging og de faktiske resultat-/skrivergrensene.

## Sluttopprydding og begrensninger

Begge sluttmatrisene har readback av slettede testbrukere og biblioteker,
fjernet testplugin/guard, slettede prøvefiler og fjernet profilmappe.
Prøvespillelister slettes native, etter kontroll av eksakte navn og sti
innenfor isolert `userplaylists`, og native oversikt leses tilbake.
Ingen A-spillelistemapper står igjen. Prosessstatus leses igjen etter at
stoppkallet har avsluttet: ServerStopped=true. Den eldre umiddelbare
native-cleanup-avlesningen med ServerStopped=false bevares som historikk;
SUMMARY og race-beviset inneholder den påfølgende sluttkontrollen.

Tidlige avbrutte spillelisteløp skyldtes API-sletteavslag og deretter en
feil antakelse om `playlists` versus faktisk `userplaylists`-sti. De brukes
ikke som komplette matriser. Alt deres syntetiske prøveinnhold ble ryddet
før de fullførte sluttløpene.

Bygg av plugin og fixture bestod uten feil/advarsler. Ingen tokens, API-
nøkler, mediefiler eller rå serverlogger er lagt til leveransen. Rute-/IL-
inventar og portable prøver inneholder syntetiske navn, ingen maskinlokale
mediestier. Full skjerming og kapittel A sin samlede støttegodkjenning
står fortsatt åpne.
