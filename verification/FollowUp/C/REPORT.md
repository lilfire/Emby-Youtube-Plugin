# C – bilder, undertekster og cacheproveniens

Undersøkt 2026-10-14 på isolert **Windows Emby Server 4.10.1.0**, plugin
**2.0.10-alpha.1**, commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`.
Produksjons-DLL SHA-256:
`AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
Fixture-DLL SHA-256:
`F890627BFB0BD1438536C7C4EF2D79A75CDFB5B195228C30F19D143C22EFD0FD`.

**Konklusjon:** bildets uavhengige stioppskrift beviser ikke innholdet. På både
bilde- og undertekstcache utleverer produksjonsintegrasjonen B-bytes ved lokal
utskiftning av A sin ellers godkjente cachefil. C kan ikke godkjennes som full
skjerming. Produksjonskode, hovedserver og Lilflix-installasjon er uendret.

## Testinngang og avgrensning

[Run-C.ps1](Run-C.ps1) gjenbruker produksjonsfixturen uten å endre andre
kapitlers filer. Scriptet leser `Test-ProductionMediaAssets.ps1`, krever kjente
testseams og setter inn C-prober i minnet. Delte porter brukes sekvensielt;
det er ingen parallelle agenter. Fixturen bruker faktiske Emby-ruter på den
isolerte porten 18096, to syntetiske native Video-biblioteker, vanlige kontoer
med tilbakeleste brede folder-rettigheter og produksjonens profiler/bindinger.
Eksperimentell PrivacyGuard er deaktivert og lest tilbake, også etter omstart.

Cacheprøven er administratorstyrt lokal feilinjeksjon. Den viser en manglende
innholdskontroll, **ikke at en vanlig HTTP-klient kan skrive cachefiler**.
Riktig A/B-innhold bevises gjennom dekodet blå/rød 80×45 PNG og ulike komplette
SHA-256; undertekster har forskjellige eiermarkører og native WEBVTT-utdata.
Bare en unik ny fil i riktig native cachefamilie kan brukes. Endret filinnhold
og opprinnelig LastWriteTime gjenopprettes med hash-readback etter prøven.

Embedded-prøven bruker ekte FFmpeg `mov_text` inne i den syntetiske MP4-en.
Sidecar fjernes før native scanning, og PlaybackInfo må identifisere nøyaktig
ett undertekstspor med `IsExternal=false`. Dette er virkelig native ekstraksjon,
ikke en adapter som returnerer en ferdig undertekstfil. Hele etterfølgende
VTT-/HTTP-/livssyklusmatrisen bruker dette sporet.

Public-prøven lar A være vanlig native innhold uten personlig rotregistrering;
B er fortsatt privat. Den bekrefter offentlig levering til begge autentiserte
kontoer og negativ tilgang til B, før/etter sletting av A sin profil og omstart.
Anonym tilgang til offentlig A er ikke en godkjent del av denne prøven.

Ingen Google, yt-dlp, API-nøkler, ekte privat innhold eller fysiske klienter
brukes. Dette er produksjonskontroller rundt syntetiske native kilder, ikke
hele publiseringskjeden fra Google. Ingen ny kandidat er installert på Lilflix.

## Resultater

[SUMMARY.json](SUMMARY.json) og syv portable `*-EVIDENCE.json` er lest tilbake.
Alle løp fullførte: **1 246 observasjoner**, med **to feilede assertions** i
Content. Observasjoner inkluderer readback/diagnostikk; tallet er ikke antall
uavhengige tilgangstester eller en generell garanti.

| Løp / inngang | Observasjoner | Resultat |
|---|---:|---|
| Content: cacheinnhold, formater, konto/token og HTTP | 235 | To påviste cacheinnholdshull; øvrige boolske assertions bestod. |
| Embedded: ekte mov_text → SRT/VTT/ASS/SSA | 205 | Eierinnhold virker, fremmed/anonym avvises, profilsletting og omstart bestod. |
| Public: vanlig A og privat B | 122 | Offentlig kompatibilitet og privat negativkontroll bestod. |
| ImageRace / SubtitleRace | 170 + 170 | Fullført profilsletting mens faktisk skriver er pauset før produksjonskontrollen gir 404 uten private entityheadere. |
| ImageLease / SubtitleLease | 172 + 172 | Etter kontrollen venter sletting på eierlåsen; riktig A-innhold leveres, så sletting lagres. B virker og kan lagre egen profil mens A venter. |

### Påviste cacheinnholdshull

1. Eier A og eier B får egne native utdata med forskjellige hasher.
2. Proben finner A sin nye, faktiske cachefil ved lengde/hash, innen riktig
   cachefamilie. Historiske identiske bildebytes og native temp-filer utelukkes.
3. Filens sti og endringstid beholdes, mens bytes erstattes med B sitt faktisk
   observerte native utdata. Ingen native bruker-/rotbinding endres.
4. A sin ordinære asset-forespørsel gir **200 med komplette B-bytes** for både
   PNG og WEBVTT. Bildet dekodes til B sin rødfarge; begge svar matcher B-hashen.
   AssetGate er fortsatt installert og `ImageRecipeVersion=1`; leserkallet nås.
5. B sitt direkte oppslag av A avvises, B sitt eget innhold fungerer, og etter
   filgjenoppretting får A igjen korrekt eget innhold.

Bildets `ImageCandidate`/`ImageOutputAllowed` kontrollerer sti/oppskrift og fersk
kildereferanse. `FinishSubtitle` registrerer native jobbs `OutputPath` med en
input-callback, uten en tilsvarende uavhengig outputoppskrift. Ingen av disse
kontrollene etablerer innholdsproveniens for en allerede eksisterende cachefil.
Dette bekreftes både i kildekoden og ved de to faktiske utleveringene.

### Filbytte etter skriverkontroll og tilbakekalling

Begge cachefiler ble også forsøkt overskrevet etter at den faktiske native
skriveren var pauset **etter produksjonens autoriseringskontroll**. Windows
avviste `WriteAllBytes` med IOException fra filhåndtaket. Begge ventende svar
leverte riktig A-innhold, uten B-bytes. Prøven beviser denne Windows-grensen;
den beviser ikke pluginens innholdskontroll eller Linux rename/inode-semantikk.

Fire separate profilracer bruker produksjonens `MyProfile/Delete` og readback
av `Deleted`, faktisk ventende HTTP og faktisk eierlås. Disse er små fullførte
overføringer ved en deterministisk pause. Store/lange eller klientavbrutte
overføringer, timeout på låsen og revoke under senere I/O er fortsatt åpne.

I Content og Embedded tilbakekalles B sin faktiske syntetiske sesjonsnøkkel med
native `Auth/Keys/{Key}`. Gamle sesjoner får 401 på bilde og 404 på undertekst,
også med HEAD, If-None-Match og range, uten private entityheadere/bytes. Ny
autentisering til **samme konto og samme private innhold** gir fungerende
positiv kontroll. Deretter slettes B sin aktive konto med native Users/Delete;
readback bekrefter fravær, og den nye gamle sesjonen avvises på samme måter.
Dette beviser nye forespørsler etter fullført revokering, ikke revokering av en
allerede autorisert lang overføring eller fysisk klientcache.

### Formater, native kjeder og cache-retensjon

PNG, JPEG og GIF er faktisk dekodet med riktig dimensjon/eierfarge og registrert
native bildeformat. SRT, WEBVTT, ASS og SSA har meningsfullt eget innhold og
negativ fremmedkontroll for både eksternt og embedded spor. Det er ikke bevis
for alle codecs, image input-formater, bitmap-undertekster eller providers.

[NATIVE-INVENTORY.json](NATIVE-INVENTORY.json) inneholder 57 inspiserte metoder
med IL-hash og relevante native kall. Den avgrensede køen er ikke trunkert,
men interface-implementasjoner utenfor de fire utvalgte typene og mer enn fire
kallnivåer er ikke fullstendig inspisert. `GetCachedImage` nås gjennom
ILibraryManager; den konkrete implementasjonen er ikke komplett inspisert.
`GetSupportedImage`, converted-image-cache, enhancers og eget enhanced-image-
trinn finnes i kjeden. De er ikke alle nye runtime-prøver: lokalisering, andre
providers, fremmede enhancer-utdata, mellomfilbytte og sammensatte bilder er
**uverifisert**. Ingen støtteallowlist er utvidet.

De to observerte A-cachefilene finnes med opprinnelig hash etter profilsletting
og faktisk omstart, selv om nye HTTP-oppslag avvises. Produksjonens generelle
native bilde-/undertekstcache er derfor **ikke fysisk purget** i disse prøvene.
Testverktøyets senere målrettede opprydding er ikke en produktegenskap.

## Leveranse, rettelsesforslag og gjenstående arbeid

[PROVENANCE.md](PROVENANCE.md) beskriver en separat, uavhengig attestmodell for
bilde og undertekst: betrodd original/track, eier/generasjon, full oppskrift,
betrodd produksjon, forventet outputsti og hash av samme åpne bytes som sendes.
Attesten må etableres ved produksjon, ikke ved første uverifiserte cachetreff.
Modellen er et **endringsforslag**, ikke implementert produksjonsproveniens.

C må lukke de to innholdshullene og attestere undertekstutdata uavhengig av
native jobbretur. E/F må levere original-/generasjonsproveniens; koordinator/D
må integrere verifikasjon av faktisk åpnet fil og senere I/O i felles gates.
Native metadata-/originalbytte mellom produsent og leser, Linux rename,
embedded cacheforgiftning, JSON-/bitmap-konvertering, unsupported providers og
avbrutte/lange overføringer trenger egne parete prøver. TODO beholder dette
som konkrete åpne oppgaver; ingen universell skjerming erklæres.

## Reproduksjon og opprydding

Kjør hvert `Run-C.ps1 -Mode <navn>` sekvensielt fra et rent, stoppet isolert
miljø. Navnene er Content, Embedded, Public, ImageRace, SubtitleRace,
ImageLease og SubtitleLease. Kjør deretter `Collect-C.ps1`. Den krever
Completed/readback, nøyaktig to forventede Content-avvik og ingen øvrige
boolske avvik, og eksporterer portable bevis uten tokens, URL-er eller lokale
absolutte stier. Fixture-build og isolert server må allerede være tilgjengelige.

Alle syv cleanup-rapporter bekrefter slettede testkontoer/biblioteker, kildefiler,
fixture/guard, personlige profiler og fraværende fixture-journal. Den tidlige
native snapshoten har `ServerStopped=false`; wrapperen venter deretter og
bekrefter **ServerStopped=true** for hvert løp. Nye cacheutdata fra de siste
løpene slettes under kontrollerte isolerte cachefamilier, med readback, etter
retensjonsmålingen. Historisk generisk cache slettes ikke globalt.

Innledende diagnostikk stoppet ved tvetydige cachekandidater og Windows sin
delingslås. Disse er ikke beståtte prøver. Filbytes ble gjenopprettet og fixture-
opprydding verifisert; bare de syv fullførte sluttløpene er portable evidens.
Sluttkontroll bekrefter stoppet Emby-prosess og frigitt testport. Ingen tokens,
rå logger, mediefiler eller maskinlokale inspeksjonsfiler er med i leveransen.
