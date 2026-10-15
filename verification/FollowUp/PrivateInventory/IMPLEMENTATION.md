# Privat kildeoversikt — implementering 2026-10-15

Oppfølging av [kontraktundersøkelsen](REPORT.md). Produksjonskode er nå endret.
Den tidligere stifilterprototypen er fortsatt forkastet; den nye implementeringen
bygger fra hele det faktiske native inventaret og beholder kanoniske kilder.
Lilflix er ikke endret.

## Hva som er implementert

- `PersonalYouTubeNativeSourceBarrier`: verifiserte Harmony-prefixer og
  finalizers på 13 repository-metoder, ti metoder for bibliotek-/mediestier og
  to CollectionFolder-metoder for bibliotekinnstillinger. Eksakte IL-hasher,
  signaturer/returtyper og fortsatt tilstedeværelse av patchene kontrolleres.
  Metodene inkluderer transaksjonswrapperne, direkte sletting, extradata og
  kildekonfigurasjon. Generelle named values inngår ikke: de brukes også til
  innstillinger som ikke endrer private kilder.
- `PersonalYouTubeNativeSourceInventory`: initial full innlesing, deretter
  gjenbruk til en kontrollert kildeendring, endret native objekt eller endrede
  virtual-folder-lokasjoner. Oversikten har kopierte ID/GUID-er, direkte
  foreldrekjeder, native collection folders og kanoniske kildestier. Den
  indekserer private kandidater etter begge identitetsaliaser og hver faktisk
  forelder; uregistrerte barn og reserverte røtter behøver ikke egne bindinger
  for å bli avvist. Kanoniske stialiaser, media-orphans og private fysiske
  forfedre dekkes også.
- `PersonalYouTubePrivateScopes`: append-only klassifikasjon lagres før
  journalpublisering, rotreservasjon og bindingspublisering. Den husker
  generasjoner, reserverte GUID-er og historiske ID/GUID-par. Den gir aldri
  tillatelse; bare den eksisterende profilen/bindingen/journalen kan gjøre det.
  En fullført migrering krever vellykket lesing av både eksisterende ledger og
  journal. Ingen nye filer opprettes for et rent offentlig bibliotek.
- Filene `private-source-scopes.json` og `private-source-scopes.required` er et
  varig par. Markøren binder JSON-innholdet med SHA-256. Begge skrives atomisk
  med flush, og publisering fortsetter først når begge er ferdige. Manglende,
  ufullstendig, skadet eller inkonsistent autoritet avvises. En korrupt global
  journal eller ledger kan bare isoleres når den uavhengige autoriteten er
  fullført og gyldig: kjente private kilder settes da i karantene, mens offentlig
  innhold kan fortsette. Eiertilgang gjenopprettes ikke fra indeksen.
- `PersonalYouTubeSourceAuthorityStamp`: query, resultat og faktisk skriver
  kontrollerer innholdshasher for tilgangsdokumentene, markørene og kontoens
  personlige profil. Tid/størrelse eller TTL brukes ikke som autorisasjonsbevis.
  Ny reservasjon og tilbakekalling kan dermed ikke godkjennes av en gammel
  forespørselsoversikt.
- Skriveren tar eksisterende eierlease, fullfører fersk native validering,
  tar en kilde-leselease for den validerte versjonen og gjør en siste kontroll
  uten native I/O. Native endringer venter til det godkjente listesvaret er
  ferdig skrevet. Lease-opprydding skjer også ved unntak; native skriveventing
  har grense på 30 sekunder. Lesekontroll som selv gjør en sen native oppdatering
  holdes utenfor leselåsen, slik at den ikke venter på sin egen lås.
  Helpermetoder med en eksisterende IDatabaseConnection som parameter venter
  aldri på lesere; ved konflikt avvises skrivingen umiddelbart. Det samme gjelder
  native skriving fra den aktive utleveringens egen asynkrone lesekontekst.
  Dermed holdes ingen slik transaksjon eller egen leselås mens den venter på seg selv.

Kald start og native endringer kan fortsatt kreve full native innlesing.
Mellom uendrede kall gjennomgås de beholdte objektenes identitets-/kildeegenskaper
i minnet; dette er fremdeles O(n), men ingen full native query og ingen
disk-/native-tilgangsavgjørelse per offentlig element. Private kandidater får
ferske tilgangsavgjørelser. Metadata og Tags beholder sine ferske kildekontroller.
Ukjent kontrakt eller mistet patch gir fullskanningsfallback for nye kall;
allerede registrerte svar fra den gamle cacheversjonen avvises.

## Verifikasjon

Eksakt verifisert DLL:
`D062C89BF60607A16A538DFC5A5E45225BD00E8DBCAF0897290FBE352861B780`.
Hashen er lest tilbake fra Release, den native testinstansen og ytelsesinstansen;
alle tre er like. Bygg: 0 feil og 0 advarsler.

| Faktisk native matrise | Observasjoner | Avvik |
|---|---:|---:|
| Metadata med nye kilde-/journal-/native skriveprøver | 119 | 0 |
| Tags, før faktisk skriver / etter skriverlease | 69 / 70 | 0 |
| Counts / Counts etter skriverlease | 107 / 112 | 0 |
| Search | 416 | 0 |
| Suggestions | 14 | 0 |
| GetItems telling/paging | 37 | 0 |
| GetItems før query / før resultat | 41 / 42 | 0 |
| GetItems før skriver / etter skriverlease | 42 / 44 | 0 |

Alle **12 native matriser**, med **1 113 observasjoner**, fullførte. Kildematrisen
ble i tillegg kjørt to ekstra ganger etter låserettelsen: **tre kalde løp med
119 observasjoner hver**, totalt **1 351 native observasjoner** uten avvik. De har
parede eier-/fremmedkontroller, manipulerte UserId-er, profilsletting, omstart,
telling/paging og de oppgitte race-grensene. Ingen ny test godkjennes på bare
tomme negative svar. [Native bevis](NATIVE-IMPLEMENTATION-EVIDENCE.json) lagrer
matriser, hasher og separat sluttoppslag.

Komponentprøver: **46/46** for kildeoversikt, manifest, migrering, korrupsjon,
foreldrekjeder/stialiaser, revokering og barriere; **16/16** i
[ItemListGate404](GATE404-IMPLEMENTATION.json); **7/7** i
[WitnessProbe](WITNESS-IMPLEMENTATION.json). Disse 69 kontrollene bruker
produksjonskode med adaptere; de er ikke 69 ekstra native HTTP-prøver.

### Sluttmåling

Samme isolerte syntetiske bibliotek med 20 000 filmer og 62 566 native
MediaItems, tre runder. Tallene er medianer for varme kall, i millisekunder.
Alle **51 sekvensielle og 18 parallelle** HTTP-kall ga 200. Antallene er uendret:
20 000 filmer, 30 sjangre, 500 studioer, 3 000 tagger, to views og 16 nyeste.
[Måledata](LATENCY-IMPLEMENTATION.json).

| Kall | Admin | Bruker |
|---|---:|---:|
| Items?Limit=12 | 571 | 558 |
| Views | 558 | 496 |
| Latest | 570 | 543 |
| Counts | 604 | 584 |
| Genres | 551 | 523 |
| Studios | 540 | 516 |
| Tags | 859 | 804 |

Servernøkkel: Counts 115 ms, VirtualFolders 53 ms, Items 61 ms.
Tags var tidligere 1 267–1 316 ms på `B27179ED…`; under ett sekund er nå nådd
for de sekvensielle varme kallene i dette biblioteket. Den syntetiske
ytelsesinstansen har ikke private A/B-data; de dekkes av korrekthetsmatrisene.

Seks samtidige hjemmekall (admin og bruker: Views, Items og Latest) fullførte
også uten feil. Medianene per actor/rute er **649–1 113 ms**. Dette gir ikke en
generell garanti om under ett sekund ved parallell last. Ingen av tallene er
målt på Lilflix, og kald oppbygging er ikke en varm-kall-måling.

[IMPLEMENTATION-EVIDENCE.json](IMPLEMENTATION-EVIDENCE.json) inneholder komponent-
prøvene. [NATIVE-CONTRACT.json](NATIVE-CONTRACT.json) inneholder de lokale native
kodekontraktene, inkludert repository-, bibliotek- og CollectionFolder-metoder.

Prøvemiljøet er isolert Emby 4.10.1.0 på Windows, med produksjonsgaten og
kontrollerte native A/B-biblioteker. Eksperimentell PrivacyGuard deaktiveres i
tilgangsmatrisene. Nye native prøver dekker aktivitet/gjenbruk, ekte SaveItems,
feil i faktisk Harmony-kjede, ny oppbygging, leser/skriver-eksklusjon,
bibliotekinnstillinger og offentlig/privat kontroll ved korrupt journal.
Den offentlige kontrollen får uttrykkelig channel-tilgang først; fungerende
positiv kontroll bekreftes før korrupsjon, og policyen gjenopprettes etterpå.

### Sluttopprydding

Testbrukere, private native biblioteker, mediefiler, profiler, scope-filer og
fixture-journal er fjernet. Begge servere er stoppet og pid-filen for ytelse er
borte ved separat readback. Fixture-verktøyets umiddelbare ServerStopped-felt
var false under prosessavslutningen; det senere separate prosessoppslaget er
true. Det syntetiske ytelsesbiblioteket og bygg beholdes i ignorert bin/obj.
Ingen lokale tokens eller rå serverlogger er lagt i de portable bevisene.

Mellomkandidater avdekket en selvventing når native validering foretok en sen
skriving under leselåsen, og for bred invalidering ved generelle named values.
Disse ble rettet før sluttløpet. Et testoppsett brukte også en offentlig kanal
uten channel-tilgang som positiv kontroll; det ble rettet med eksplisitt policy
og bekreftet positiv kontroll før korrupsjon. De avbrutte mellomløpene regnes
ikke som beståtte prøver av slutt-DLL-en. En senere ekstra gjentakelse avdekket
sporadisk venting; slutt-DLL-en har den nye transaksjons-/lesekontekstkontrollen
og bestod de tre kalde gjentakelsene etter denne rettelsen.

## Begrensninger

Dette er ikke generell skjermingsgodkjenning for de øvrige åpne A–K-hullene.
Linux, andre serverbuilds, konkurrerende tredjepartspatcher, direkte SQL utenom
de auditerte inngangene og nye kildeendringsracer krever videre verifikasjon.
En kildeendring midt i et kall kan avvise svaret; gammel kildeoversikt tillates
ikke for å opprettholde HTTP 200. Full nativ innlesing ved kald start er heller
ikke omfattet av målet for varme kall.

Et prosessavbrudd mellom indeksfilen og dens integritetsmarkør etterlater en
påviselig inkonsistens som feiler lukket; automatisk reparasjon av den er ikke
implementert. De nye filene må følge journal/bindinger/native data ved backup
og gjenoppretting. Hashmarkøren avviser endret eller foreldet JSON alene, men
erstatter ikke en kontrakt for koordinert gjenoppretting av alle data.
Dette beskriver den isolerte testfasen; ekte Google er ikke prøvd her.

## Versjonert utgivelse 2.0.11-alpha.1

2026-10-15: Versjonsnummeret er økt til `2.0.11-alpha.1` / assembly `2.0.11.0`.
DLL SHA256 er `2DE94E0F869D303F6E6C2870285B44FCA81852A125EFAE8B3B974C65609C1F66`.
Bygget har 0 advarsler og 0 feil. Kildematrisens 119 native observasjoner og
46 komponentkontroller er kjørt på nytt og bestod på denne DLL-en; testserveren
er stoppet og fixturen ryddet. Se [versjonert bevis](RELEASE-2.0.11-alpha.1.json).
De eldre fullmatrisene og ytelsestallene ovenfor beholder sin opprinnelige
DLL-hash. Lilflix-status dokumenteres i [utrullingsrapporten](../../PersonalChannels/LILFLIX-ALPHA-DEPLOYMENT.md).
