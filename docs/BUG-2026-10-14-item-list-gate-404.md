# BUG: PersonalYouTubeItemListGate gir 404 «Items not found» på alle item-lister (2.0.10-alpha.1)

**Alvorlighet:** Høy. Biblioteket er utilgjengelig for API-nøkkel-klienter, og også for innloggede brukere sitt hjemskjermbilde/visninger.
**Versjon:** Emby.YouTubePlugin 2.0.10.0 (commit `e49dc06`, «Add personal YouTube closed alpha 2.0.10-alpha.1»)
**Server:** Lilflix, Emby 4.10.1.0 (linuxserver/emby, container `emby_backup` på OMV, 10.0.2.10:8096)
**Oppdaget:** 2026-10-14 via Home Assistant (Spook / `embymedia` sto i setup_retry)

## Tidslinje
- 2026-10-14 13:10:44: `plugins/Emby.YouTubePlugin.dll` byttes, og Emby startes på nytt.
- 13:10:52: `Emby.YouTubePlugin.PluginEntryPoint` starter, og gaten installeres.
- 13:17:26: første `ResourceNotFoundException: Items not found.` i `embyserver.txt`.
- Fra da av får alle kall til gatede endepunkter 404. Før restarten (loggen fra 14.10 00:00 til 13:10) finnes ingen slike 404.

## Observerte 404-er siden 13:10 (`logs/embyserver.txt`)
| Tjeneste | Klient | Antall |
|---|---|---|
| ItemsService (`/Items`, `/Users/{id}/Items`) | 10.0.0.80 (Home Assistant) | 109 |
| UserLibraryService (`/Users/{id}/Items/Latest`) | 10.0.0.80 | 19 |
| SuggestionsService | 10.0.0.80 | 19 |
| LibraryService (`/Items/Counts`) | 10.0.0.80 | 14 |
| LibraryStructureService (`/Library/VirtualFolders`) | 10.0.0.80 | 14 |
| UserViewsService / ItemsService | 10.0.0.95 (Emby Web, LAN) | 2 + 2 |
| UserViewsService / ItemsService | 195.18.252.9 (ekstern klient) | 2 + 2 |

Eksempel (10.0.0.95, innlogget bruker `624b240310c241faab1ec2ddbbec4a4b`). Dette kallet brukte **32,6 s** før det endte med 404:
```
Response 404 to 10.0.0.95. Time: 32585ms. GET /emby/Users/624b…/Items?SortBy=DateCreated&recursive=true&Filters=IsUnplayed&…&Limit=12&IncludeItemTypes=Movie
```
Stacktrace (samme for alle): bare `ServiceHandler.ProcessRequestAsync`, `ResourceNotFoundException: Items not found.`. Det stemmer med at Harmony-prefixen setter `__result` og returnerer `false`.

Uautentiserte kall gir fortsatt 401, så endepunktene finnes. Bare autentiserte kall får 404.

## Rotårsak(er) i `PersonalYouTubeItemListGate.BeforeService` (linje 211–242)

### 1. Kall med API-nøkkel (uten bruker) avvises alltid (bekreftet ut fra koden)
```csharp
var user = _authorization!.GetAuthorizationInfo(__2).User;
if (user == null || user.Policy.IsDisabled) throw new ResourceNotFoundException("Items not found.");
```
Kall som autentiseres med en API-nøkkel (`api_key` / `X-Emby-Token` fra Innstillinger → API-nøkler) har ingen `User`. Derfor feiler alle gatede endepunkter for slike klienter, også `GetVirtualFolders` og `GetItemCounts`. Admin-unntaket på linje 222 hjelper ikke her, fordi det sjekker `user.Policy.IsAdministrator` etter null-sjekken.
Dette rammer blant annet Home Assistant-integrasjonen `embymedia` (troykelly/homeassistant-emby). Den kaller `/Items/Counts`, `/Library/VirtualFolders` og `/Items?IncludeItemTypes=BoxSet&Limit=0&Recursive=true` ved oppstart, og blir stående i setup_retry.

**Forslag:** Når `user == null` og tokenet er en gyldig server-API-nøkkel, slipp kallet gjennom urørt. API-nøkler er server-/admin-scope i Emby. Alternativt kan man bruke admin-semantikk: ingen personlige YouTube-elementer med mindre de eksplisitt er delt. Uansett: ikke gi 404.

### 2. Innloggede brukere får også 404 (observert, men eksakt unntak er ukjent)
Kall med vanlig brukertoken (`/Users/{id}/Items`, `/Users/{id}/Views`, `/Items/Latest`) får også 404. Det gjelder både Emby Web på LAN, en ekstern klient og HA-integrasjonen `emby_library`. `user` er da ikke null, så feilen må komme fra et unntak lenger ned i `try`-blokken. Det unntaket blir til 404 i catch-all-en på linje 241:
```csharp
catch (Exception) { __result = Task.FromException<object>(new ResourceNotFoundException("Items not found.")); return false; }
```
Kandidater: `_countsParent!` / `_access!` / `_library!` er null, `DecideItem` kaster, eller timeout/kansellering i full-scan (se punkt 3). Det er umulig å se hvilken fordi unntaket svelges. `data/youtube-plugin.log` (sist skrevet 18:11) inneholder ingen linjer om gaten.

**Forslag:**
- Logg unntaket (type, melding, endepunkt, bruker-id) i `PluginFileLog` før det gjøres om til 404.
- Fail-open for elementer som ikke er personlige YouTube-elementer. En feil i gaten bør ikke ta ned hele biblioteket. Vurder heller å filtrere bort bare personlige elementer, og la resten gå gjennom.

### 3. Full biblioteksskanning ved hvert listekall (ytelse)
```csharp
inventory = _library!.GetItemList(new InternalItemsQuery { Recursive = true });
var denied = inventory.Where(item => _access!.DecideItem(item, user) == Access.Denied)...
```
Dette kjører for **hvert** kall til GetItems/Latest/Views/Suggestions/Counts/Genres/Studios/Tags, over hele biblioteket. Emby Web brukte 32 s på et kall med Limit=12. Hjemskjermen sender mange slike kall parallelt.
**Forslag:** Cache settet med nektede id-er per bruker, og ugyldiggjør cachen ved ItemAdded/ItemRemoved/policy-endring. Alternativt kan man begrense skanningen til personlige YouTube-mapper i stedet for hele biblioteket.

## Slik reproduserer du
1. Installer 2.0.10-alpha.1 og restart Emby.
2. `curl "http://10.0.2.10:8096/Items/Counts?api_key=<server-API-nøkkel>"` gir 404 (forventet 200 med tellinger).
3. Logg inn i Emby Web som vanlig bruker. Hjemskjermens rader/visninger feiler, og `UserViewsService` / `ItemsService` gir 404 i `embyserver.txt`.

## Midlertidig løsning
Rull tilbake til forrige versjon (2.0.9.x, commit `f96f2ee`) eller slå av gaten. Restart deretter Emby. HA-integrasjonen `embymedia` prøver på nytt automatisk (hvert 10. minutt), eller den kan lastes inn på nytt manuelt.

## Status 2026-10-14: punkt 1 rettet og verifisert isolert (ikke på Lilflix)
- `PersonalYouTubeItemListGate.BeforeService` godtar null-bruker bare når tokenet
  slås opp i `IAuthenticationRepository` som én aktiv nøkkel uten konto
  (`UserId == 0`). Scope får ingen bruker, så alle personlige elementer og
  biblioteker ekskluderes (samme semantikk som `Guid.Empty`). Nøkkelen sjekkes på
  nytt ved resultat og skriving. Anonym, ukjent, inaktiv og konto-token gir fortsatt avslag.
- Sanert, rate-begrenset diagnostikk (`[YT] Item-list gate denied|failed|info`)
  ved prefix-, service-, resultat- og skrivergrensene: DTO, fase, auth-type,
  unntakstype, tid og antall. Ingen tokens, ID-er, navn eller meldinger.
- Komponentprobe: 16/16 (`verification/FollowUp/ItemListGate404`).
- Isolert Emby 4.10.1.0 med ekte API-nøkkel og private A/B-biblioteker
  (`Invoke-ServerKeyProbe.ps1` via `PERSONAL_YOUTUBE_A_PROBE`): 36 observasjoner,
  0 feil i aktiv fase, etter profilsletting og etter restart. Counts, VirtualFolders,
  Items, Users/Items, Views og Latest gir 200 (34–81 ms) uten private referanser.
  Eierkontroller ser eget innhold; anonym og ugyldig nøkkel gir 401.
- Den vanlige `-RequireIsolation`-matrisen gir 12 Views-avvik på grunn av en ekstra
  «Playlists»-visning. HEAD-baseline gir nøyaktig de samme avvikene, så de kommer
  fra testmiljøet, ikke fra denne endringen.
- DLL SHA256: `4FC47099FCB9833CEC2BFA1522A73051EBDB32F1B3EE0EDE9EFF35F2575E7983`.
- Gjenstår: installasjon på Lilflix, HA-reload og måling der. Punkt 2 (innloggede
  brukeres 404) kan nå diagnostiseres fra loggen. Punkt 3 (full skanning) er fortsatt åpent.

## Status 2026-10-14 kl. 20:55: installert og målt på Lilflix
- `plugins/Emby.YouTubePlugin.dll` på Lilflix har SHA256 `4FC47099…7983`, og
  `emby_backup` ble startet 17:56:55Z. DLL-en er bygget fra arbeidstreet
  (ikke committet) og inneholder også kapittel I sine UI-endringer.
- HA: `embymedia` (Lilflix), `emby_library` og `dlna_dms` er `loaded`.
- Ingen `Items not found` i `embyserver.txt` og ingen `denied`/`failed` fra
  gaten i `youtube-plugin.log` siden installasjonen.
- Lesende probe via `docker exec emby_backup curl localhost:8096` med eksisterende
  aktive tokens (lest read-only fra `authentication.db`, ikke skrevet ut):

  | Inngang | Status | Tid |
  |---|---|---|
  | Bruker 1 (admin) Views / Items?Limit=12 / Latest / Counts | 200 | 31,2–32,0 s |
  | Bruker 2 Views / Items?Limit=12 / Latest / Counts | 200 | 30,4–34,1 s |
  | Server-API-nøkkel Counts / VirtualFolders / Items / Latest / Suggestions (HA) | 200 | 5,7–10,0 s (gate-logg) |

- Gate-loggen viser at hele tiden ligger i prefixen: `phase=slow-prefix`,
  `scanned=104269`, ~31 s for bruker og ~6 s for servernøkkel. To samtidige
  brukerkall tok ~60 s hver. Emby-containeren lå på ~100 % CPU under prøven.
- Bruker-API-et returnerer `denied=7` for bruker 1 og 2, mens servernøkkel gir
  `denied=2829`. Forskjellen er ikke undersøkt; den bør forklares (eierskap
  versus offentlig innhold) før punkt 3 endrer hvordan nektede ID-er beregnes.
- Punkt 2: logikken for innloggede brukere er uendret bortsett fra diagnostikk,
  og 404 er ikke reprodusert på ny DLL. Eksakt tidligere årsak er derfor fortsatt
  ukjent. Ny diagnostikk vil logge fase og unntakstype hvis det skjer igjen.
- Akseptanse: API-nøkkel → 200 og HA `loaded` er oppfylt. Bruker → 200 er oppfylt
  for bruker 1 og 2. `< 1 s` er **ikke** oppfylt (~31 s); det krever punkt 3.

## Oppfølging 2026-10-14 kl. 21:50: kostnad per element (isolert, ikke installert)
- Avviket 2829 mot 7 er forklart: det er alle Genre/Studio/Tag-objekter, som alltid
  avvises for servernøkkel. Det er ingen lekkasje.
- Ny DLL `0904173A…` leser register, journal og virtuelle mapper én gang per
  forespørsel og avgjør indeksobjekter i bolk. På et syntetisk bibliotek med 62 566
  elementer går brukerkall fra ~43 s til ~1,7 s, og servernøkkelkall fra ~14 s til
  0,5–1,9 s. Alle isolasjonsmatriser består (se
  `verification/FollowUp/ItemListScan/REPORT.md`). Kravet `< 1 s` er ennå ikke nådd.
- Runde 2 (`BB374DED…`): indeksobjektene tar nå ~0,45 s, og hele brukerkall
  ~1,0 s isolert. Alle matriser gir samme resultat. Ikke installert på Lilflix.

## Akseptansekriterier for fiks
- `/Items/Counts`, `/Library/VirtualFolders` og `/Items` med API-nøkkel gir 200.
- `/Users/{id}/Views` og `/Users/{id}/Items` gir 200 for alle aktive brukere, og personlige YouTube-elementer er fortsatt skjult for brukere uten tilgang.
- Unntak i gaten logges i `youtube-plugin.log`.
- Et `/Users/{id}/Items?Limit=12`-kall bruker < 1 s på Lilflix.
