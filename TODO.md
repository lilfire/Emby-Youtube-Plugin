# TODO: personlig YouTube etter lukket alfa

Oppdatert 2026-10-15. Utgangspunkt: `2.0.10-alpha.1`, commit `e49dc06`.
Alfaen er installert og aktivert på Lilflix. Denne listen er en arbeidsfordeling
for videre undersøkelser, ikke en godkjenning av full skjerming eller alle klienter.

## 0. Felles rammer og arbeidsfordeling

Dokumentet inneholder bare åpne oppgaver. Ferdige oppgaver fjernes fra listen;
resultater og historikk lagres i separate rapporter. «Ikke verifisert» betyr
ikke «påvist lekkasje».

### Regler for parallelle agenter

- Bruk ett kapittel per agent og separate worktrees/arbeidsgrener ved kodeendringer.
  Ikke endre en annen agents filer eller gjenbruk dens aktive fixture.
- Start med undersøkelse og reproduksjon. Oppgi faktisk produksjonskode versus
  testadapter.
- Rapporter i `verification/FollowUp/<kapittel-ID>/REPORT.md`; nye tester legges
  i samme agents mappe. Lokale tokens, nøkler, mediefiler og rå logger skal ikke committes.
- Oppgi commit/DLL-hash, Emby-versjon, plattform, faktisk testinngang, resultat,
  begrensning og sluttopprydding. Skill ekte Google fra simulert transport.
- Hver tilgangstest skal ha positiv eierkontroll og negativ fremmedkontroll.
  Ved behov: anonym, manipulert UserId, slettet referanse og vanlig offentlig innhold.
- Delte filer eies av koordinator: `PersonalYouTubeNativeAccess.cs`,
  `PersonalYouTubeNativeBindings.cs`, `PersonalYouTubeTransferLease.cs`,
  `Plugin.cs`, `PluginEntryPoint.cs`, `PluginConfiguration.cs`, `AssemblyInfo.cs`,
  prosjektfiler, README og denne TODO-filen. Send konkrete endringsforslag dit.
- Endringer i andre kapitlers moduler foreslås i rapporten og integreres av
  fileieren/koordinatoren. Kapitlene nedenfor gir eksklusivt eierskap til øvrige filer.
- Lilflix, stue-TV, HA/ADB, testporter og eksisterende fixture-journaler er delte
  ressurser. Koordinator avtaler tidsluker; bruk egne container-/fixture-navn,
  porter og datamapper. Ingen parallell stopp/start eller brukerbytte på samme ressurs.
- Undersøk isolert først. Ikke installer nye kandidater, endre hovedserveren
  eller kjør belastnings-/feilinjeksjonstester der som del av denne TODO-en.

### Prioritet og koordinering

P0: personvern og korrekt tilbakekalling før sterkere skjermingspåstander.
P1: stabilitet, klientstøtte og drift før bredere testutgivelse.
P2: forbedringer etter at nødvendig verifisering er på plass.

| ID | Arbeidsområde | Eksklusivt kodeeierskap | Avhengigheter |
|---|---|---|---|
| A | API, oppdagelse og mutasjoner | ServiceReferenceGate, ItemListGate, QueryCoverage | Leverer rutekart til B/C/D/H |
| B | Sync, live-referanser, varsler og DLNA | Nye tester/rapport under FollowUp/B | A; koordinering av premium-/klientmiljø |
| C | Bilder, undertekster og cache | AssetSourceGate | A; D for samtidighet |
| D | Video, transport og tilbakekalling | StaticSourceGate | A; C/E for kilde- og livssyklusgrenser |
| E | Native eierskap, journal og gjenoppretting | NativeCreation, NativeCreationHook, NativePublisher, PublicationJournal, Lifecycle | F/G for integrasjon |
| F | Profiler, nøkler og identitet | Store, Service | E/G for integrasjon |
| G | Jobber, katalog, buffer og lagringsbudsjett | Catalog, VideoBuffer, Jobs, JobRuntime, InitialRefresh, StorageBudget | E/F |
| H | Klientkompatibilitet | Nye tester/rapport under FollowUp/H | A/B/D og avtalt klienttilgang |
| I | Bruker-/administratorgrensesnitt | Configuration-filer, YouTubeConfigSaveService | F/G for kontrakter |
| J | Plattform, avhengigheter og installasjon | Nye verktøy/rapport under FollowUp/J | E/G og koordinator for native kontrakter |
| K | Evidens, regresjon og dokumentasjon | Nye verktøy/rapport under FollowUp/K | Samler alle kapitler; koordinator integrerer |

Filnavn i tabellen med korte navn viser til `PersonalYouTube<Navn>.cs` i roten.
A–K kan begynne med egne undersøkelser parallelt. Avhengigheter betyr at en
integrert rettelse eller støtteerklæring må vente på relevant leveranse.

## A. API-dekning, oppdagelse og mutasjoner — P0

### Utgivelsesblokker: item-list-gate gir 404

[Feilrapport](docs/BUG-2026-10-14-item-list-gate-404.md) og
[undersøkelse](docs/INVESTIGATION-2026-10-14-item-list-gate-and-todos.md).
Servernøkkelrettelsen (DLL `4FC47099…`) er installert på Lilflix: HA
`embymedia` er `loaded`, og ingen 404 er sett siden. Innloggede brukere får nå
200, men hvert listekall tar ~31 s (servernøkkel ~6 s) i gatens fulle skanning.
Alfa-innstillingen deaktiverer ikke tilgangsgatene.

- [ ] Følg med på innloggede brukeres tidligere 404. Den er ikke reprodusert
  på ny DLL, og brukerlogikken er uendret; diagnostikken logger nå fase og
  unntakstype. Prøv også tomme og cachede resultatkilder samt fremmedkontroll.
- [ ] Fullfør støtte- og gjenopprettingsbevis for den implementerte
  [private kildeoversikten og skrivebarrieren](verification/FollowUp/PrivateInventory/IMPLEMENTATION.md):
  Linux/andre builds, nye mappe-/kildeendringsracer, tap/konkurranse om patcher
  og prosessavbrudd mellom scope-JSON og integritetsmarkør. Tapt eller skadet
  klassifikasjonsautoritet feiler lukket; automatisk reparasjon er ikke levert.
- [ ] Utvid målingene til større private A/B-samlinger, kald oppbygging,
  langvarig native scan-/publiseringslast og parallelle hjemmekall. Kandidat
  `D062C89B…` har varme sekvensielle Items på 0,56–0,57 s og Tags på 0,80–0,86 s
  ved 62 566 syntetiske elementer; seks parallelle kall gir medianer på
  0,65–1,11 s. Under ett sekund er ikke dokumentert for all parallell last.
- [ ] Etter separat avtalt installasjon: bekreft aktive brukeres Items/Views
  på Lilflix med 200, fungerende eierkontroll og fremmedskjerming, samt
  Items?Limit=12 under ett sekund. Kandidaten er ikke installert der.
  Registrer eksakt DLL-hash og faktisk native tilstand.
- [ ] Avklar en faktisk tilgjengelig og personverntrygg midlertidig løsning
  sammen med J; alfa av stopper bare jobbstart, og DLL-rollback alene er
  ikke dokumentert trygg ved gjenværende private native-/Sync-/cachedata.

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/A/REPORT.md),
[587 deklarerte ruter](verification/FollowUp/A/ROUTES.csv) og portable
HTTP-/state-/race-bevis i samme mappe. Produksjonskode og Lilflix er uendret.
Kapittelet er fortsatt åpent: matrisene påviser hull, ikke full skjerming.
Ferdige undersøkelser og deres begrensninger er flyttet til rapporten.

- [ ] Lukk påvist lekkasje i Similar, inkludert alle sju alternative ruter,
  private frø, før-query-filtrering, telling/paging og faktisk skriver.
- [ ] Lukk påvist lekkasje i MovieRecommendations; bind kategori-, kilde-,
  teller- og cacheproveniens før utvidelse av produksjonskontraktene.
- [ ] Lukk påviste metadatahull i Years, OfficialRatings og Persons, også
  direkte personnavn. Fullfør resterende navn-/ID-familier og Credits med
  meningsfullt positivt og negativt innholdsbevis; tomme svar er ikke nok.
- [ ] Lukk påvist fremmed kildebruk og metadatautlevering via oppretting,
  tillegg og lesing av spillelister. Prøv removal, avledet eierskap,
  tilbakekalling, omstart, manipulerte referanser og native persisted state.
- [ ] Avklar rating-set som gir 200 uten native Rating-endring, offentlig
  userdata-mutasjon med manipulert UserId, og Refresh som aksepteres også
  anonymt. Skill native baseline og faktisk bivirkning fra bare HTTP-status.
- [ ] Fullfør rutekartets åpne bevis: transitive native datakilder, faktiske
  factory-/skriverkjeder, runtime-aliaser og ikke prøvde ruter. Deklarert
  inventar/IL er ikke et fullstendig rutebevis.
- [ ] Utvid beståtte GetItems-prøver til større flersidige blandede samlinger
  og øvrige sorteringer/filtre. Behold offentlige og private positivkontroller
  og filtrering før telling/paginering.
- [ ] Utvid beståtte query-/resultat-/skriver-racer til nye rute-/metadata-
  familier og faktiske mutasjons-/kildeendringer. Verifiser avslag uten
  private navn, ID-er, tellere og entity-headere i alle støttede forløp.

Ferdig når hver aktuell rute har eksplisitt status: prøvd, ikke relevant,
ikke støttet eller åpent hull, med eget positivt/negativt bevis.
Startkilder: PRODUCTION-SUGGESTIONS, PRODUCTION-ITEM-COUNTS,
PRODUCTION-METADATA-LISTS, PRODUCTION-METADATA-REFERENCES,
PRODUCTION-SEARCH og PRODUCTION-SEARCH-MUTATION-RACES i verification/PersonalChannels.

## B. Sync/offline, live-referanser, varsler og DLNA — P0

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/B/REPORT.md),
[73 deklarerte ruter](verification/FollowUp/B/ROUTES.csv) og portable eier-/
fremmed-/livssyklusbevis i samme mappe. To produksjonsmatriser og to separate
GUID-prototypereproduksjoner fullførte. Produksjonskode og Lilflix er uendret.
Kapittelet er fortsatt åpent: påviste hull og manglende støttebevis gjenstår.
Ferdige undersøkelser og deres begrensninger er flyttet til rapporten.

- [ ] Lukk påvist fremmed tilgang til Sync-jobb-/jobitemmetadata, Original-
  og konverterte filbytes samt Ready-mål. Bind avledede referanser, mål og
  faktiske skriverkjeder til autentisert eier og aktiv samling/generasjon.
  A sine gamle filer ble utlevert etter produksjonsprofilsletting og omstart.
- [ ] Lukk påvist Sync-oppretting med fremmed kilde og manipulert UserId.
  Utvid til blandede kilder, øvrige mutasjoner, direkte jobitem, cloud-/
  folder-sync og faktiske nedlastingsklienter. Manglende miljø er ikke bestått.
- [ ] Integrer en løsning på reprodusert mappe-GUID-gjenbruk sammen med E:
  gjenbrukt fysisk mappe gir fire metadataavslag i prototypen; ny mappe virker.
  Behold historiske konfliktavslag. Prøv produksjonsbindinger og Sync ved gjenbruk.
- [ ] Implementer og prøv varig eier-/generasjons-/filproveniens og trygg
  orphan-opprydding uten avhengighet av fortsatt GetJob/GetJobItem. Native
  sletting av ferdig jobb fjernet filen i nye prøver; historisk rotsletting
  under klargjøring etterlot filer. Disse hendelsene må dekkes hver for seg.
- [ ] Utvid Original-/konvertert Sync-racer i produksjonen: sletting under
  ffmpeg, flere profiler, kansellering, prosessavbrudd, omstart, slettet konto
  og eksisterende utdata etter slettet kilde/eier. Historiske Ready-racer er prototype.
- [ ] Lukk påvist fremmed OpenToken/Open, privat MediaInfo og fremmed Close
  som fjerner eierens strømmetadata. Gamle A-tokens og metadata virker etter
  profilsletting før omstart. Definer eier-/consumer-/generasjonsmodell og
  riktig avslag for gamle referanser etter restart.
- [ ] Fullfør live-transportbytes med D: eierens statiske forespørsel med
  syntetisk live-kilde gir 404. Negative svar uten fungerende eiertransport
  beviser ikke byteskjerming. Prøv faktiske providers/transkoding og tilbakekalling.
- [ ] Lukk påvist fremmed video-ID i kontrollert native WebSocket
  LibraryChanged. Prøv naturlige bibliotek-/jobbvarsler, Sessions, status,
  køer og fjernstyring med paret eier-/fremmedkontroll og aktivitetsskjerming.
- [ ] Avklar DLNA og andre innganger uten entydig bruker med fungerende
  discovery, positiv SOAP-/ressurskontroll og negativ privat kontroll.
  Alle nye SOAP-prøver ga 404 også for eier, og er derfor uverifiserte.

Ferdig når inngangene har en tydelig støtte-/tilgangsmodell og verifiserbare
tester. Serverens nye utlevering er innenfor kravet; allerede nedlastede
kopier uten serverkontakt er utenfor den avklarte servergarantien.
Startkilder og historiske prototypebegrensninger finnes i B-rapporten.

## C. Bilder, undertekster og cacheproveniens — P0

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/C/REPORT.md),
[native kjedeinventar](verification/FollowUp/C/NATIVE-INVENTORY.json),
[proveniensforslag](verification/FollowUp/C/PROVENANCE.md) og syv portable
produksjonsmatriser i samme mappe. Alle løp fullførte, med to påviste
cacheinnholdshull. Produksjonskode og Lilflix er uendret. Beståtte avgrensede
prøver og deres begrensninger er flyttet til rapporten; C er fortsatt åpent.

- [ ] Lukk påvist utlevering av B-bilde og B-undertekst når A sin ellers
  godkjente cachefil inneholder B-bytes. Attester betrodd produksjon og faktisk
  åpnet innhold; hash beregnet ved første cachetreff er ikke proveniens.
- [ ] Implementer uavhengig undertekstproveniens, inkludert forventet
  outputoppskrift/sti, kilde-/trackfingerprint og aktiv eier/generasjon.
  Native SubtitleConversionJob.OutputPath alene er ikke nok. Embedded
  mov_text-ekstraksjon virker i nye prøver; embedded cacheforgiftning,
  JSON-/bitmap-undertekster og øvrige konverteringer gjenstår.
- [ ] Fullfør GetCachedImage sin konkrete implementasjon og øvrige
  provider-/lokaliserings-/enhancement-kjeder. Prøv mellomfilbytte,
  sammensatte bilder og øvrige input-/outputformater med faktisk eierinnhold.
  IL-inventaret og prøvd PNG/JPEG/GIF er ikke generell providerstøtte.
- [ ] Prøv original-/native-metadatabytte mellom produsent, leser og senere
  I/O, samt Linux rename/inode-bytte. Windows blokkerte de to prøvde
  cacheoverskrivingene etter skriverkontrollen; dette er ikke flerplattformbevis.
- [ ] Utvid faktisk tilbakekalling til lange/avbrutte asset-overføringer,
  senere I/O og låsetimeout. Fullført tokenrevokering/kontosletting avviser
  nye GET/HEAD/betingede/range-oppslag; allerede autorisert overføring gjenstår.
- [ ] Definer og implementer eiersikker fysisk cacheopprydding. To native
  A-cachefiler beholdes etter profilsletting og omstart i nye readback-prøver,
  selv om HTTP-oppslag avvises. Testverktøyets opprydding er ikke produktpurging.

Ferdig når støttede asset-forløp har dokumentert kjede fra tillatt kilde til
utleverte bytes, og øvrige forløp er eksplisitt avgrenset.
Startkilder: PRODUCTION-IMAGE-CACHE-RECIPE, PRODUCTION-ASSET-SOURCE-BINDING,
PRODUCTION-ASSET-HTTP-VARIANTS og PRODUCTION-METADATA-IMAGE-WRITERS.

## D. Video, transport og tilbakekalling — P0

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/D/REPORT.md),
[38 deklarerte ruter](verification/FollowUp/D/ROUTES.csv) og 18 fullførte
portable produksjonsmatriser i samme mappe. Audio utleverer fremmed komplett
MP4; HLS utleverer fremmede spillelister; originalfilbytte før native åpning
kan levere fremmede bytes. Statisk tilbakekalling, native metadata-/parentracer,
eierlås, ekte TCP-avbrudd og offentlig kontroll er prøvd med begrensningene i
rapporten. Produksjonskode og Lilflix er uendret. Ferdige undersøkelser er
flyttet til rapporten; påviste avvik og resterende støttebevis holder D åpent.

- [ ] Lukk fremmed medieutlevering via tre prøvde audio-ruter og fremmed
  HLS-spilleliste-/referanseutlevering. Bind alle relevante alternative
  innganger og gamle avledede referanser til eier/aktiv generasjon.
- [ ] Fullfør dynamisk video, faktisk HLS/transkoding, universal audio og
  live providers med fungerende eiertransport. Prøvde private dynamiske
  kall gir 404; HLS-segmenter gir 400 også til eier. Disse er ikke støttebevis.
- [ ] Implementer betrodd originalinnholdsbinding sammen med E/G/C. A sin
  godkjente originalsti leverer B-bytes også ved filbytte etter autorisering
  før native åpning. Sti-/delegatbinding alene løser ikke dette.
- [ ] Utvid native kilde-/parentracer til aktive publiseringsjournaler,
  hel bibliotekflytting, senere I/O og Linux rename/inode-bytte. Windows
  blokkerte overwrite etter åpnet leser og skriverkontroll; dette er ikke
  flerplattformbevis. Felles korrupt bindingsfil blokkerer også B; E må avklare
  gjenoppretting og hvordan berørte samlinger avgrenses.
- [ ] Prøv kanal-/nøkkelendring via virkelig SaveForRefresh/NativePublisher
  og aktiv publisering sammen med F/G. MyProfile Save i Draft med direkte
  fixture-registrering beholder gammel transport; det er ikke full publiseringskjede.
- [ ] Definer maksimal låseventetid og kansellering. Godkjent overføring
  fullfører før profilsletting; ett ekte avbrudd under 64 MiB TCP-mottrykk
  frigir låsen og lagrer slettingen. Wait har ingen timeout, og heng/andre
  native avbruddsforløp og langvarig belastning gjenstår. Behold fungerende B
  og offentlig kontroll når dette utvides.
- [ ] Avklar native suffix-/multiple-range-kompatibilitet for støttede klienter:
  bytes=-128 gir første 129 bytes og multiple range gir bare første intervall,
  også på offentlig innhold. Utvid til andre codecs, faktiske klienter og builds.

Ferdig når transport- og revokeringssemantikk er eksplisitt og testet ved
faktiske I/O-grenser, med bytes/headere og samtidighetsbevis.
Startkilder: PRODUCTION-STATIC-SOURCE-BINDING, PRODUCTION-DOWNLOAD-VARIANTS,
PRODUCTION-REFERENCE-RESPONSE-REVOCATION og ANDROIDTV-ALPHA-RESULT.

## E. Native eierskap, journal og crash recovery — P0/P1

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/E/REPORT.md),
[Windows-bevis](verification/FollowUp/E/WINDOWS-EVIDENCE.json),
[Linux-bevis](verification/FollowUp/E/LINUX-EVIDENCE.json) og kildehasher i
samme mappe. 87/89 komponentobservasjoner og syv faktiske .NET-prosessavbrudd
per plattform fullførte. Native bibliotek er en SDK-adapter, ikke en kjørt
Emby-server. Produksjonskode og Lilflix er uendret. Ferdige komponentprøver
og begrensninger finnes i rapporten; E er fortsatt åpent.

- [ ] Lukk påvist journalmismatch: gyldig binding uten journal-entry kan
  tillates for eier uten privat kildebane og mangler i query-denials.
  Publikasjonsrevisjon avvises ved resume, men ikke i tilgangsavgjørelsen.
  Samordne kontraktene og prøv native resolver/query med parete kontroller.
- [ ] Lukk påvist oppstarts-/feilisolasjonsgap: korrupt A-profil avbryter
  RepairInterrupted, og korrupt global journal sperrer også B. Bevar fail
  closed og dokumenter en varig modell som isolerer berørte samlinger.
- [ ] Fullfør native hendelsestiming for vekst, flytting/reparenting,
  rot-/kontosletting og ID-gjenbruk. Komponentprøver bevarer registrerte
  tombstones og avviser konflikter; aldri registrerte fraværende barn har
  ingen proveniens. Prøv uten nye snapshots, også gamle avledede referanser.
  Historisk hendelsesledger og B sin mappe-GUID-reproduksjon er prototype.
- [ ] Fullfør faktiske Emby-jobber og native restart på begge plattformer:
  Waiting/Preparing, Buffering, Publishing, aktivering før Ready og opprydding.
  Nye prosessavbrudd dekker produksjonskomponentgrenser med bibliotekadapter,
  ikke downloader, native database, brukerpolicy eller avbrudd midt i flush.
  Utvid journalens påviste rename-feil til disk-/volumfeil og senere I/O.
- [ ] Lukk påvist orphan-gap for tilbakekalt staging opprettet før Begin,
  som journalbasert CleanupAsync ikke finner. Definer trygg retry ved native
  rotfjerning før diskavslag og håndtering av ukjente filer med fungerende B.
- [ ] Lukk påvist Linux-lenkehull: selve konfigurert lagringsrot kontrolleres
  ikke og kan følges under staging-sletting. Generasjonslenke avvises i prøven;
  Windows-lenkeprøver er skipped. Prøv også path-/symlink-/inodebytte mellom
  validering, native mutasjon og sletting, samt øvrige foreldreløse kopier.
- [ ] Verifiser faktisk runtime-tap av creation/service/list-/skriverkroker
  og delvis installasjon på siste produksjonsbygg, også etter jobbstart og
  før aktivering. SDK-adapteren bekrefter bare avslag når creation-krok er
  utilgjengelig før oppretting; eldre hook-loss-bevis bruker testbro.
- [ ] Prøv samlet backup/restore med faktisk native DB, kontoer og policy.
  Avklar at eldre konsistent backup kan gjeninnføre slettet generasjon, og
  om nøkkeltap skal sperre allerede aktivt lokalt innhold. Komponentrestore
  og avslag på ukjent journalversjon er prøvd; migrasjon og full native
  mismatch-håndtering gjenstår sammen med F/G/J.

Ferdig når hver feilfase har en gjentakbar gjenopprettings-/sperremodell,
ingen ubundet privat publisering og fungerende kontroll for annen eier.
Startkilder: FollowUp/E/REPORT, NATIVE-MEMBER-EVENT-PERSISTENCE, NATIVE-GROWTH-WHOLE-ROOT-DELETION,
PRODUCTION-NATIVE-BINDINGS, PRODUCTION-NATIVE-CREATION-HOOK og Docker-sluttrapporten.

## F. Profiler, nøkler og brukeridentitet — P0/P1

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/F/REPORT.md),
[58 native integrasjonsobservasjoner](verification/FollowUp/F/INTEGRATION-EVIDENCE.json)
og separate Windows-/Linux-lagerbevis i samme mappe. Produksjonskode og Lilflix
er uendret. Ferdige undersøkelser er flyttet til rapporten; F er fortsatt åpent.

- [ ] Implementer varig tilbakekalling og fysisk opprydding etter native
  kontosletting sammen med E/G. Prøven avviser gamle sesjoner og ny konto med
  samme navn/ny GUID, men gammel profil med kryptert nøkkel og media blir liggende.
- [ ] Prøv samlet backup/restore av profil, nøkkel, journal, bindingsdata og
  native bibliotek, inkludert gjenopprettet konto med samme GUID. Et gammelt
  matchende profil-/nøkkelpar gjenaktiverer gammelt snapshot i lagerprøven.
- [ ] Utvid timingprøvene til forsinket katalogtransport gjennom native
  arbeider, kontosletting/deaktivering under arbeid og A-tilbakekalling mens B
  arbeider. Native publiseringslease og sent katalogsvar er prøvd hver for seg.
- [ ] Håndhev/valider private lagrings- og backuprettigheter sammen med J.
  Linux-lageret oppretter 0755/0644 ved umask 0022; Windows-nøkkelen arver brede
  lokale ACL-er i testmiljøet. Prøv annen OS-bruker og faktisk Docker-serverkonto.
- [ ] Definer sikker servernøkkelrotasjon/migrering og mismatch-håndtering.
  Nøkkeltap, korrupt ciphertext, profilnøkkelrotasjon og matchende nøkkelrestore
  er prøvd; kontrollert rotasjon av selve krypteringsnøkkelen gjenstår.
- [ ] Håndhev én skriver per datamappe eller implementer prøvd flerprosess-
  koordinering. Separat prosess kan lagre mens PublishIfCurrent holder sin
  prosesslokale lås; atomisk filbytte er ikke en samlet publiseringstransaksjon.
- [ ] Fullfør tidsutløpt sesjon og rå malformed/oversized bodymatrise for alle
  profil-/diagnostikkruter i siste integrasjon. Manipulert identitet, anonym,
  deaktivert, revokert og slettet konto er prøvd med positiv eier-/adminkontroll.

Ferdig når identitet, hemmeligheter og generasjoner er verifisert gjennom
den komplette produksjonskjeden, med eksplisitte begrensninger for restore/flerprosess.
Startkilder: PRODUCTION-PROFILE-STORE, PRODUCTION-PROFILE-SERVICE og
PERSONAL-ISOLATION-REQUIREMENTS; sistnevntes prototypepunkter er historiske.

## G. Jobber, Google, videobuffer og lagringsgrenser — P1/P2

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/G/REPORT.md)
og [44 komponentobservasjoner](verification/FollowUp/G/WINDOWS-EVIDENCE.json).
Produksjonsmoduler er prøvd med syntetisk katalog-/nedlastertransport og ekte
syntetiske parent/child-prosesser; ingen ny Google-/native-serverprøve.
G har ikke endret produksjonskode eller Lilflix. Ferdige undersøkelser,
prosjektkvotemodell og manuelt oppdateringsvalg er flyttet til rapporten.

- [ ] Lukk påvist katalog-body-heng: ResponseHeadersRead lar body-lesing
  overskride HttpClient.Timeout. Innfør samlet deadline og avgrenset retry;
  én katalogjobb må ikke kunne holde global lease ubundet.
- [ ] Lukk påvist prosessheng når avsluttet downloader etterlater child som
  holder stdout/stderr åpne. Prøv faktiske yt-dlp/Node/FFmpeg og underprosesser
  ved timeout, profilendring, server-KILL og omstart sammen med E/J.
- [ ] Lukk påvist duplikatfeil i metadata-Single og manglende side-/request-
  grense ved nye tokens uten utvalgsframdrift. Prøv motstridende metadata,
  refill/fordeling, nye videoer og store kanaler før utvidet støtte.
- [ ] Valider faktisk container og støttede lyd-/videospor før publisering;
  nullbytes med MP4-navn godtas i bufferprøven. Prøv ekte providerfeil,
  slettet/privat video, innloggingskrav og formatfeil med sanitert eierstatus.
- [ ] Prøv fysisk fullt/forsvinnende volum, ekstern plassendring etter
  allowance, staging/native dobbeltkopi og diskfeil gjennom native publisering.
  Logisk budsjett reserverer ikke fysisk plass; forsvunnet media telles som null.
  Avklar per-fil cleanup/retry med E; første release-feil kan stanse resten.
- [ ] Prøv kørettferdighet, mange eiere/kanaler og minne-/CPU-belastning i
  faktisk JobRuntime. 32 leases fullførte, men global heljobbserialisering,
  dictionary-levetid og Notify-ventekjeder har ingen bevist last-/ventegaranti.
- [ ] Utvid bestått komponent-eierscope, sen nøkkelrotasjon og foreldet
  jobbstatus til native ReadActive/cache og ekte delt Google-prosjekt med F/E.
  Global QuotaTracker teller ikke Catalog og er ikke personlig kvoteregnskap;
  avklar korrekt bruker-/administratorinformasjon sammen med I.

Ferdig når feilmønstre gir riktig eierstatus, begrenset ressursbruk,
kontrollert opprydding og gjenoppretting uten hemmelighets-/nøkkelfallback.
Startkilder: CLOSED-ALPHA, DOCKER-ALPHA-RELEASE-RESULT og produksjonsmodulene.

## H. Faktiske klienter — P1

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/H/REPORT.md),
[konkret klientmatrise](verification/FollowUp/H/CLIENTS.csv), faktiske web-/
stue-TV-observasjoner og portable eier-/fremmed-/tilbakekallingsbevis i samme
mappe. Webs HomeSections/Sections utleverer fremmede biblioteksnavn og
videotitler; vanlige Views-/detalj-/statiske videokontroller avviser fremmed
tilgang. Stue-TV 1.8.54g/Android 12 spiller begge eieres eget innhold og
skjuler A etter lagret profilsletting. H sin separate Windows-server og
prøvedata er ryddet; TV/nettverk er tilbakeført. Produksjonskode og Lilflix
er uendret av H. Avgrensede resultater finnes i rapporten; H er fortsatt åpent.

- [ ] Lukk påvist web-hjemmelekkasje sammen med A: HomeSections,
  smalllibrarytiles og latestmedia-seksjoner trenger eget eier-/generasjons-,
  kilde-/skriver- og telling/paging-bevis. Prøv øvrige seksjonstyper separat.
- [ ] Undersøk 404 på webklientens egen thumbnail og prøv bildevisning med
  fungerende eierkontroll. Gjenta klientmatrisen på integrert DLL etter rettelser.
- [ ] Test Android mobil og nyere Android TV. Pi har Android 16/2.5.03g,
  men var ikke del av avtalt TV-prøve. Øvrige tilgjengelige versjoner gjenstår.
- [ ] Test iPhone/iPad, Apple TV og native Samsung/LG-TV etter avtalt tilgang.
  Disse mangler faktisk prøve i klientmatrisen; fravær er ikke støtteavslag.
- [ ] Prøv virkelig Google → Docker → klientavspilling samlet. Eksisterende
  TV-bevis bruker Windows-backend og historisk bufret video, separat fra
  ekte Google i Docker. H gjør ingen ekte Google-katalogforespørsel.
- [ ] Utvid korte video-/SRT-/pauseprøver til seek og varig resume etter
  app-/serverrestart, øvrige spor og feilstatus. Fysisk lyd er ikke hørt;
  aktiv track alene, særlig samplet gain -inf, er ikke en lydgodkjenning.
- [ ] Prøv gamle native TV-referanser og klientcache etter tilbakekalling,
  samt aktive overføringer sammen med D. Nye A-webdetaljer/statiske kall
  og TV-hjem etter lagret profilsletting er prøvd med fungerende B-kontroll.
- [ ] For download-/Sync-klienter: verifiser filoverføring fra serveren
  sammen med B. Allerede lagrede frakoblede kopier har annet omfang.
- [ ] Avklar hvor personlige innstillinger kan åpnes: meny/skjema er prøvd
  i Emby-web, ikke dokumentert som native innstillingsside i hver app.

Ferdig når hver klient/versjon/backend har egne positive og negative prøver,
eller tydelig «uverifisert/ikke støttet» med konkret årsak.
Startkilder: BROWSER-ALPHA-RESULT, ANDROIDTV-ALPHA-RESULT og KNOWN-LIMITS.

## I. Brukerflyt, administratoroppsett og metadata — P1/P2

Undersøkelse og UI-rettelser utført 2026-10-14: [rapport](verification/FollowUp/I/REPORT.md),
60 beståtte nettleserkontroller med produksjonskontroller/DOM og simulert transport,
14 produksjonsvalideringskontroller og tre reproduksjoner på originalkoden.
Ferdige avgrensede prøver er flyttet til rapporten. Ingen kandidat er installert
på Lilflix. I er fortsatt åpent for native integrasjon og fysisk metadataavlesning.

- [ ] Fullfør feilvisning gjennom isolert ekte Emby-arbeider og nettleser:
  nøkkelavslag, verktøy, budsjett, provider, publisering og gjenoppretting.
  Ny prøve dekker visningen av alle kjente feilkoder med simulert transport.
- [ ] Fullfør samtidige faner, revisjonskonflikt, dobbel mutasjon og utløpt
  sesjon med native serverpersistens. Nye DOM-prøver dekker svarrekkefølge,
  konto-/serverbytte og navigasjon; reproduserte UI-feil er rettet.
- [ ] Prøv HTML-entiteter på gammel Android TV sammen med H og avklar
  Overview-kontrakten med G/E før metadatarettelse. Kildeundersøkelsen
  reproduserer koding/dobbel koding, men beviser ikke TV-gjengivelsen.
- [ ] Verifiser ny administratorvalidering via ekte HTTP, avslag uten mutasjon,
  lagret konfigurasjon og restart. Prøv utførbarhet/verktøyversjoner og status
  for deaktivert arbeider/manglende kroker; dagens kontroller er komponent/DOM.
- [ ] Avklar med F/G om brukerflyten skal vise eksakte effektive utvalgs-/
  lagringsgrenser. Forklaring av metadata-nøkkel, buffer, manuell oppdatering
  og administratorens delte grenser er lagt inn; dynamisk readback gjenstår.

Ferdig når alle viktige tilstander har prøvd visning/handling og korrekt
serveravlesning, uten uklar nøkkelbruk eller private feildetaljer.
Startkilder: BROWSER-ALPHA-RESULT, PRODUCTION-PROFILE-UI og ANDROIDTV-ALPHA-RESULT.

## J. Serverversjoner, plattformer og distribusjon — P1

Undersøkelse utført 2026-10-14: [rapport](verification/FollowUp/J/REPORT.md),
37 Windows-/Linux-komponentobservasjoner, native IL-inventar og åtte
pakkeobservasjoner. Container-recreate er prøvd med eget verktøy/syntetiske
data. [Installasjonsplan](verification/FollowUp/J/INSTALLATION-PLAN.md) og
pakkeverifikator er levert. Ingen Emby-server ble startet; produksjonskode,
allowlist og Lilflix er uendret. Avgrensede funn er flyttet til rapporten.

- [ ] Prøv andre faktiske Emby-builds og isolert IL-avvik i ellers støttet
  kontrakt. Offline 4.10.1.0-inventar og avvist SDK-adapter er ikke nok.
  Verifiser også gamle private biblioteker ved manglende tilgangskroker.
- [ ] Prøv Harmony-konflikter og versjonsoppgradering på faktiske native
  innganger. Syntetisk prefix-konflikt omgår kontroll mens metadata består;
  definer karantene som beskytter eksisterende samlinger ved patch-tap.
- [ ] Prøv Linux Preparing og ekte Windows server-KILL under Buffering på
  siste bygg. Nye komponentprøver dekker cancellation med syntetisk nedlaster,
  ikke native arbeider, reelle verktøy eller alle orphan-forløp med G/E.
- [ ] Prøv ARM64, andre serverplattformer, faktisk tjenestekonto, annen
  OS-bruker og private backuprettigheter med F. Linux miljøstripping er prøvd;
  verktøy som krever egne bibliotekstier trenger særskilt wrapperkontroll.
- [ ] Utvid container-recreate til faktisk Emby-state og yt-dlp/Node/FFmpeg.
  Prøv verktøyoppdatering, versjons-/arkitekturmismatch og ffprobe. Dagens
  filkontroller håndhever ikke en generell verktøyversjonskontrakt.
- [ ] Gjennomfør installasjonsplanens komplette native installasjon,
  oppgradering og rollback. Bevis sletting av alle personlige/avledede objekter,
  også fra slettede kontoer, før eldre tilgangskontroll installeres.
- [ ] Integrer ren commit-/versjonsbundet bygg- og prerelease-prosess med K.
  Pakkeintegritet er prøvd, men status er ikke bundet til godkjenningstester.
  Ingen binær utgivelse er publisert som del av J.

Ferdig når støttet kombinasjon og avslag ved unsupported kombinasjon er
dokumentert og prøvd, med sikker installasjons-/tilbakeføringskjede.
Startkilder: alpha-package/INSTALL, Build-ClosedAlphaPackage og LILFLIX-ALPHA-DEPLOYMENT.

## Leveransemal for hver agent

Rapporten skal inneholde:

1. Kapittel/oppgave-ID, avgrensning og filer som ble undersøkt/endret.
2. Funnets status: påvist feil, manglende bevis eller produktvalg.
3. Minimal reproduksjon, positiv/negativ kontroll og faktisk miljø/kildehash.
4. Foreslått løsning og eventuelle endringsforslag til en annen fileier.
5. Utførte kontroller, gjenstående usikkerhet og eksplisitte støttebegrensninger.
6. Opprydding/readback, nye filer og avhengigheter for integrasjon.

Koordinator integrerer rapporter og felles kode sekvensielt, kjører relevant
regresjon og oppdaterer denne listen. Ingen agenter er startet av denne planen.
