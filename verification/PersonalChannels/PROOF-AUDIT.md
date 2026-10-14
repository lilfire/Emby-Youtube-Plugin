# Revisjon av kravet om full skjerming

Oppdatering 2026-10-13: [PRODUCTION-SEARCH-MUTATION-RACES.md](PRODUCTION-SEARCH-MUTATION-RACES.md)
verifiserer profilsletting før/etter tilgangskontroll ved virkelig native
historikkmutasjon. To løp bestod 41/42 observasjoner. Før kontrollen
stanser sletting mutasjonen; etter kontrollen venter den på A sin lås,
mens B kan oppdatere. Arkiv og sluttopprydding er lest tilbake.
Andre mutasjoner, revokering og full skjerming gjenstår.


Oppdatering 2026-10-13: [PRODUCTION-SEARCH-HISTORY.md](PRODUCTION-SEARCH-HISTORY.md)
retter faktisk native historikkmutasjon på fremmede og slettede private
videoer. DTO nummer 17 validerer hele ID-rammen før første lagring og under
eierlåsen. Privat/offentlig matrise bestod 37/40 observasjoner; fem
regresjonsløp bestod også. Native datoer og permanente kopier er bevart i
et versjonert evidensarkiv. Mutasjonsracer og full skjerming gjenstår.


Oppdatering 2026-10-13: [PRODUCTION-SEARCH.md](PRODUCTION-SEARCH.md)
verifiserer GetItems-søk via begge ruteformer, egne/fremmede søkeord,
bruksidentitet, paging, sletting/omstart og begge native skrivergrenser.
Tre løp bestod 416, 420 og 421 observasjoner. Search/Hints sin innleste
native metode returnerer bare Array.Empty<string>(); body er inspisert.
Search-history-mutasjoner, Similar og resten av full skjerming gjenstår.


Oppdatering 2026-10-13: [PRODUCTION-METADATA-IMAGE-WRITERS.md](PRODUCTION-METADATA-IMAGE-WRITERS.md)
følger opp faktiske metadatabilder ved begge native skrivergrenser.
28 original-/80x45-løp via sjanger-/studio-navn, indeks og ID samt tag-ID
bestod 5 474 observasjoner. Sletting før kontroll gir generisk 404;
sletting etter kontroll venter på A-overføringen, mens B kan oppdatere.
Andre revokeringshendelser og hele den avtalte skjermingen gjenstår.


Oppdatering 2026-10-13: [PRODUCTION-METADATA-IMAGES.md](PRODUCTION-METADATA-IMAGES.md)
dokumenterer 56 ordinære lekkasjer i navnebaserte sjanger-/studiobilder,
og rettelsen gjennom faktisk tilgang, asset-kilde, filleser og skriver.
Fire private/offentlige original-/80x45-matriser bestod 191 observasjoner
hver. Referansefamilien inneholder nå 16 DTO-er; øvrige navnebaserte
bildefamilier og hele den avtalte skjermingen er fortsatt ubevist.


Oppdatering 2026-10-13: [PRODUCTION-METADATA-REFERENCES.md](PRODUCTION-METADATA-REFERENCES.md)
viser at filtrerte metadataoversikter ikke skjulte direkte navn-/ID-oppslag.
Den nye metadataresolveren krever tillatt native innholdskilde. Begge
191-observasjonsmatrisene med private og offentlige kilder bestod på samme
bygg. Dette beviser de prøvde oppslagene, ikke alle felt/ressurser eller
full skjerming.

Oppdatering 2026-10-13: [PRODUCTION-METADATA-LISTS.md](PRODUCTION-METADATA-LISTS.md)
bevarer før-scope-funnet og mellomløpet der query-kontroll ikke skjulte
merkelapper. Tag-ID-er avledes nå fra tillatte native kildelinker, og
bindingen og de anvendte query-ID-ene kontrolleres ved resultat/skriver.
De prøvde metadataoversiktene og slettingsgrensene passerer. Det beviser
ikke direkte metadataoppslag, andre kilder eller full skjerming.

Oppdatering 2026-10-13: [PRODUCTION-ITEM-COUNTS.md](PRODUCTION-ITEM-COUNTS.md)
viser et ordinært antallskall som røpet begge faktiske filmer. Ny kontroll
har native positive Movie-kontroller og egen avvisning av private ParentId-er.
Hjemmevideoenes nulltelling ble ikke godtatt som positive kontroller.
Antallstesten verifiserer den prøvde ruten, ikke alle metadata eller klienter.

Oppdatering 2026-10-13: [PRODUCTION-SUGGESTIONS.md](PRODUCTION-SUGGESTIONS.md)
viser at tidligere Views/Latest-bevis ikke dekket Suggestions. Ordinære
kall viste begge private videoer. Ny kontroll gir eget fungerende innhold
og riktig antall med filtrerte native queries samt faktisk skriverkontroll.
Dette øker den prøvde rutedekningen; universal skjerming er ikke oppnådd.

Ny faktisk API-feil/rettelse 2026-10-13:
[PRODUCTION-DISCOVERY-LISTS.md](PRODUCTION-DISCOVERY-LISTS.md) dokumenterer
normal Views-lekkasje som fortsatt fantes etter at request-/query-scopen
var utvidet. Det faktiske Folder[]-inputet filtreres nå før view-bygging.
Kildebevis krever faktisk filtrering og den anvendte exclusion-snapshoten.
Dette lukker den prøvde inngangen, ikke alle lister eller full skjerming.

Ny feil/rettelse 2026-10-13: [PRODUCTION-IMAGE-CACHE-RECIPE.md](PRODUCTION-IMAGE-CACHE-RECIPE.md)
bevarer diagnostikken av faktisk injisert B-produsentresultat til A (HTTP 200,
riktig dekodet B-bilde, IsolationPass=false). Ny produksjonskode krever lokal
original eller uavhengig cacheoppskrift. Det er ikke komplett cacheinnholds-
proveniens eller bevis for alle native kilder og innganger.

Oppdatering 2026-10-13: [PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
erstatter tidligere vurdering av manglende separat asset-leserbinding.
Native produsentinput/output følges nå til bundet leser; original bilde-/SRT-
feilinnsprøyting nås faktisk og avvises uten nye bundne leserkall. Hele den
avledede HTTP-/livsløpsmatrisen passerer 158 observasjoner. Rapportene er lest
tilbake. Komplett cacheproveniens og full skjerming er fortsatt ikke bevist.

Ny avledet kildeevidens 2026-10-12:
[NATIVE-DERIVED-ASSET-SOURCES.md](NATIVE-DERIVED-ASSET-SOURCES.md) identifiserer
native prosessor-/konverteringsresultat og faktisk 80x45 PNG/VTT fra andre
stier enn originalene (51 observasjoner hver). Dette er positive kilde-
og inspeksjonskontroller, ikke ferdig kildebinding eller fremmede avledede
isolasjonskontroller. Request-/kilde-/cachebevis og revokering gjenstår.
Full skjerming er fortsatt ikke oppnådd.

Ny kildeinspeksjon 2026-10-12:
[NATIVE-ASSET-SOURCE-PROVENANCE.md](NATIVE-ASSET-SOURCE-PROVENANCE.md)
bekrefter faktisk native originalkilde og uforandrede private PNG/SRT-bytes,
men leseren beholder metadatafabrikkens samme mutable options-objekt uten
videokildens separate leserbevis (51 observasjoner hver). Dette endrer neste
rettelseskrav; faktisk avledet asset-kilde/cache må bindes og støttes.
Ingen asset-filstimutering eller vanlig klientutnyttelse påvises i denne
inspeksjonsrunden. Full skjerming er fortsatt uoppnådd.

Ny HTTP-evidens 2026-10-12:
[PRODUCTION-ASSET-HTTP-VARIANTS.md](PRODUCTION-ASSET-HTTP-VARIANTS.md) bekrefter
HEAD/ETag/én range for Primary-PNG/SRT gjennom profilsletting og omstart:
158 observasjoner, egne 200/304/206-svar bevart, generiske avslag for
fremmede/anonyme/slettede referanser uten entityheadere. Variantspesifikke
skriver-racer, faktisk avledet kilde-/cachebinding og øvrige varianter/ruter
gjenstår. Full skjerming er fortsatt ikke oppnådd.

Ny sperreevidens 2026-10-12:
[PRODUCTION-ASSET-TRANSFER-LEASE.md](PRODUCTION-ASSET-TRANSFER-LEASE.md)
kontrollerer faktiske PNG/SRT-FileWriter etter tilgangskontrollen. A-sletting
når sperren og venter, B sin kanalendring fungerer, godkjent eget svar beholdes,
og sletting lagres etter frigjøring (58 observasjoner per rute). Senere I/O-
grenser, lange overføringer, faktisk avledet kilde/cache og andre varianter
er fortsatt uavklart. Full skjerming er ikke oppnådd.

Ny samtidighetsevidens 2026-10-12:
[PRODUCTION-ASSET-WRITE-REVOCATION.md](PRODUCTION-ASSET-WRITE-REVOCATION.md)
verifiserer faktisk FileWriter-pause før produksjonskontroll for både Primary
PNG og ekstern SRT. Profilsletting fullfører mens svaret venter; frigjøring
gir 404 uten entityheadere med én produksjons-WritesDenied (56 observasjoner
hver). Pause etter tatt skrivesperre, faktisk avledet kildebinding og øvrige
varianter er fortsatt uavklart. Full skjerming er ikke oppnådd.

Ny evidens for faktiske medieressurser 2026-10-12:
[PRODUCTION-PRIMARY-IMAGE-EXTERNAL-SUBTITLE.md](PRODUCTION-PRIMARY-IMAGE-EXTERNAL-SUBTITLE.md)
dokumenterer 28 faktiske private utleveringer før rettelsen og 50 observasjoner
etter nye produksjonskontroller. Egne Primary-PNG/SRT-filer fungerer; fremmede,
anonyme, slettede og blandede kilde-ID-er avvises. Native skriver-racer for
akkurat disse rutene, avledet kildebinding og øvrige HTTP-/ressursvarianter
er fortsatt uavklart. Full skjerming er fortsatt uoppnådd.

Ny evidens 2026-10-12:
[PRODUCTION-STATIC-SOURCE-BINDING.md](PRODUCTION-STATIC-SOURCE-BINDING.md)
supplerer den historiske feilen nedenfor. Separate native leseralternativer
og request-/resultatbevis avviser faktisk filstimutering i fire HTTP-varianter
(ti observasjoner hver). Tracen bekrefter separat leserkopi i 67 observasjoner.
Dette beviser den prøvde avgrensede rettelsen, ikke alle kilde-/cachegrenser,
revokeringer, serverbuilds eller klientfamilier.

Faktisk kilde 2026-10-12:
[NATIVE-STATIC-FACTORY-PROVENANCE.md](NATIVE-STATIC-FACTORY-PROVENANCE.md)
påviser tom FileWriter._filePath og den native factory-leserens kobling til
samme mutable StaticFileResultOptions (67 native observasjoner). Kontrollert
intern mismatch etter closure-opprettelse leverer faktisk B-filen til A
(åtte diagnostiske observasjoner, IsolationPass=false). Dette er ingen
ordinær klientutnyttelse, men kildebindingskravet er uoppfylt under den prøvde
feilen. Produksjonsrettelse og nye åpne-/cache-/304-kontroller gjenstår.

Statisk GetVideoStream 2026-10-12:
[PRODUCTION-STATIC-VIDEO-STREAMS.md](PRODUCTION-STATIC-VIDEO-STREAMS.md) dokumenterer
SHA-korrekt fremmed video via native stream-rute før rettelsen. Ellevte DTO og
native statisk kilde-/eierkontroll passerer nå full/HEAD/range/ETag med 76
observasjoner hver: andre kontoer og kilder avvist, faktisk ventende svar ved
fullført profilsletting, B sine svar og omstart beholdt. Private dynamiske/live/
transkodede GetVideoStream-kall er foreløpig avvist; kompatibilitet krever videre
implementering. Ingen full skjerming eller alle-klienter-garanti er oppnådd.

GetDownload-varianter 2026-10-12:
[PRODUCTION-DOWNLOAD-VARIANTS.md](PRODUCTION-DOWNLOAD-VARIANTS.md) identifiserer
og retter en 304-kompatibilitetsfeil med native EmptyHttpResult-skriveren.
Matching ETag og én range passerer 83 observasjoner hver, inkludert direkte
fremmed konto, ventende skriver etter fullført profilsletting og B sine tillatte
206/304 før/under/etter/restart. Native HEAD er ustøttet her; 78 observasjoner
gir 404 uten filinformasjon på tvers av kontoer/sletting/restart. Dette er ikke
andre HTTP-varianter, øvrige serverinnganger, andre builds eller full klientkjede.

GetDownload 2026-10-12:
[PRODUCTION-DOWNLOAD-REVOCATION.md](PRODUCTION-DOWNLOAD-REVOCATION.md) beskriver
faktisk FileWriter-lekkasje etter profilsletting og deretter en separat
Content-Disposition-lekkasje i 404-svaret. Rettet produksjonsskriver passerer
76 observasjoner med kropp, filheadere og kildehåndtak kontrollert, mens B
beholder tillatt tilgang. Regresjoner: PlaybackInfo 75, listeskrivesperre 44,
komponenter 186. HEAD/range/betingede svar og alle andre innganger gjenstår.
Den eldre Download-avgrensningen nedenfor er historisk; denne nye kontrollen
beviser fremdeles ikke universell skjerming.

Direkte svar 2026-10-12:
[PRODUCTION-REFERENCE-RESPONSE-REVOCATION.md](PRODUCTION-REFERENCE-RESPONSE-REVOCATION.md)
påviste metadatautlevering etter ferdig profilsletting. Direkte metadata og
GET/POST PlaybackInfo knyttes nå til eier, referansekontroll og skrive-sperre.
Metadata-racen passerer 60 observasjoner og GET PlaybackInfo-racen 74,
inkludert B sine positive GET/POST PlaybackInfo-kontroller. Download sin
senere filutlevering og øvrige innganger er fortsatt ikke bevist skjermet.

Pågående listerespons 2026-10-12:
[PRODUCTION-LIST-TRANSFER-LEASE.md](PRODUCTION-LIST-TRANSFER-LEASE.md) påviste
lekkasje etter siste skrivekontroll. En eier-sperre holdes nå gjennom native
skrivetask; profilsletting venter ved den samme sperren. 44 observasjoner
bekrefter ventende faktisk sletting og B sin uavhengige oppdatering; 186
komponentkontroller passerer. Andre mutasjoner/ruter og klientkjeden gjenstår.

Skriverinngang 2026-10-12: [PRODUCTION-LIST-WRITE-REVOCATION.md](PRODUCTION-LIST-WRITE-REVOCATION.md)
påviser lekkasje etter resultatkontroll, ved faktisk native WriteToAsync.
Ny produksjons-prefix avviser samme holdte forespørsel med 404; 42 observasjoner
passerer med fixture-skjerming av og ett målt produksjonsavslag ved skriving.
Revokering etter skriverinngangen under byteutlevering står fortsatt åpen.

Resultat-race 2026-10-12: [PRODUCTION-LIST-RESULT-REVOCATION.md](PRODUCTION-LIST-RESULT-REVOCATION.md)
påviste privat HTTP 200 etter ferdig profilsletting og ferdig native task.
Produksjonen kontrollerer nå registrerte sperrer før resultatet returneres;
samme test får 404 uten privat navn i 42 observasjoner. 178 komponentkontroller
passerer. Senere byteutlevering er fortsatt et åpent krav.

Liste-race 2026-10-12: [PRODUCTION-LIST-INVENTORY-REVOCATION.md](PRODUCTION-LIST-INVENTORY-REVOCATION.md)
påviser at en pauset gammel liste utleverte A etter ferdig profilsletting.
En SDK-fri oppfrisking av registrerte sperrer før native query lukket det
samme vinduet i 41 observasjoner. Komponentene har nå 169 kontroller og
235-observasjonsregresjonen passerer. Senere utleveringsvinduer og ny
uregistrert native publisering er fortsatt åpne krav.

Produksjonsliste 2026-10-12: [PRODUCTION-ITEM-LIST-GATE.md](PRODUCTION-ITEM-LIST-GATE.md)
beskriver native GetItems-ekskludering før telling/paging. 37 observasjoner
passerer med begge brukeres EnableAllFolders=true og fixture-skjerming av,
inkl. native countbaseline, falsk UserId, profilsletting og omstart. Den
235-observasjonsregresjonen passerer også. Samtidig revokering/publisering
etter inventaret og øvrige listefamilier består som åpne krav.

Første produksjonsservicekrok 2026-10-12:
[PRODUCTION-SERVICE-REFERENCE-GATE.md](PRODUCTION-SERVICE-REFERENCE-GATE.md)
beskriver ti DTO-er som sperres før native serviceutføring. 53 observasjoner
passerer med eksperimentell fixture-håndheving avslått, inkl. faktisk omstart,
uendret A-historie etter fremmede mutasjoner og positiv B-fil/PlaybackInfo.
430 native rute-DTO-er er inventert, men dette er ikke universell dekning.
De øvrige inngangene og fullskjermingskravene står fortsatt åpne.

Native oppløsning 2026-10-12: [PRODUCTION-NATIVE-ACCESS-RESOLUTION.md](PRODUCTION-NATIVE-ACCESS-RESOLUTION.md)
beskriver produksjonsavgjørelsen fra faktisk User/native element/foreldre/kildestier,
og varig avslag på fraværende gamle referanser. Komponentgrunnlaget er 160
kontroller; den utvidede native kjøringen omfatter 235 observasjoner, med
native sletting og senere omstart. Den universelle produksjonsgrensen og
de øvrige fullskjermingskravene består.

Produksjonskrok 2026-10-12: [PRODUCTION-NATIVE-CREATION-HOOK.md](PRODUCTION-NATIVE-CREATION-HOOK.md)
dokumenterer oppstartsinstallasjon av en kontraktkontrollert pre-insert-prefix.
37 native observasjoner passerer med fixture-reservasjonen fjernet, og 16
ytterligere observasjoner viser avvist oppretting ved faktisk prefixbortfall,
upåvirket B-innhold og reinstallasjon etter omstart. Produksjonens universelle
tilgangsgrense og ferdige publiserer gjenstår; full skjerming er ikke bevist.

Senere samme dag: [PRODUCTION-NATIVE-CREATION-CONTEXT.md](PRODUCTION-NATIVE-CREATION-CONTEXT.md)
flytter autoriteten for rotreservasjon fra syntetisk navneoppslag til en intern
produksjonskontekst med faktisk profilsnapshot. Komponenten og fixture-koblingen
er verifisert med 150 komponentkontroller og 35 native observasjoner, inklusive
det pauserte pre-source-vinduet. Produksjonskroker/publiserer og full garanti
er fortsatt åpne.

Ny kontroll 2026-10-12: [NATIVE-CREATION-PRE-SOURCE-WINDOW.md](NATIVE-CREATION-PRE-SOURCE-WINDOW.md)
påviste metadatautlevering til begge vanlige testkontoer inne i faktisk native
oppretting, før kildestier ble lagret. En ny varig GUID-reservasjon i
produksjonsjournalen lukket det samme målte vinduet gjennom fixture-koblingen.
Den beskyttede kjøringen har 35 observasjoner med faktisk omstart og positiv
A-tilgang etter aktivering; seks kontroller i pausen passerte. Komponentene
har nå 130 beståtte kontroller. Full skjerming er fortsatt ikke bevist, og
produksjonens opprettings-/tilgangskoblinger er fortsatt ikke installert.

Produksjonstillegg 2026-10-12: brukeren har autorisert implementering etter
planen. Personlig produksjonslager og autentiserte profilruter er implementert
og isolert verifisert med 36 lagerkontroller, 40 registerkontroller og 37 profil-HTTP-kontroller.
[PRODUCTION-NATIVE-BINDINGS.md](PRODUCTION-NATIVE-BINDINGS.md) beskriver varige
eier/samling/generasjonsbindinger som avviser native ID-/GUID-gjenbruk. Disse
er ennå ikke integrert med native publisering eller serverhåndheving.
[NATIVE-PRODUCTION-BINDING-INTEGRATION.md](NATIVE-PRODUCTION-BINDING-INTEGRATION.md)
har senere koblet dette registeret til eksperimentelle testkroker på faktisk
Emby 4.10.1.0: 51 observasjoner med beholdt native kilde etter profilsletting,
faktisk serveromstart og ny profilgenerasjon. Produksjonens native kroker,
publiseringskjede og alle-klientkontroll består som åpne krav.
[NATIVE-UNBOUND-DESCENDANT.md](NATIVE-UNBOUND-DESCENDANT.md) utvider senere
native-kjøringen til 81 observasjoner, med et faktisk innskannet element uten
egen binding. Det avvises også for eieren gjennom testkrokene, mens registrerte
positive kontroller består. Første private oppretting uten registrert ancestry
og produksjonens universelle servergrense er fortsatt åpne.
[PRODUCTION-PUBLICATION-JOURNAL.md](PRODUCTION-PUBLICATION-JOURNAL.md) legger
til varig Preparing/Active-tilstand og samlet native-/stiavgjørelse, med 36
nye komponentkontroller (totalt 112). Native-testen med 81 observasjoner
passerte også gjennom denne avgjørelsen uten journaloppføringer. Faktisk
native Preparing/Active-oppretting og første uregistrerte rotvindu er fortsatt
ikke verifisert; journalen er ikke en full produksjonspubliserer.
[NATIVE-PUBLICATION-STATE.md](NATIVE-PUBLICATION-STATE.md) har senere verifisert
Preparing/Active på faktiske registrerte native elementer: 86 observasjoner,
inkludert faktisk omstart mens A er Preparing og B beholder positive kontroller.
Første uregistrerte rotvindu og produksjonens universelle inngangsgrense består.
[NATIVE-ROOT-SOURCE-LOCATIONS.md](NATIVE-ROOT-SOURCE-LOCATIONS.md) har senere
bekreftet fysisk kildested via den faktiske ILibraryManager.GetVirtualFolders,
og ført alle kildesteder gjennom journalavgjørelsen. Seks nye kontroller øker
komponenttotalen til 118; native-regresjonen med 86 observasjoner passerer.
Tidspunktet for kildestedenes tilgjengelighet under første native oppretting
og den universelle produksjonsgrensen er fortsatt åpne.
[NEW-UNREGISTERED-NATIVE-ROOT.md](NEW-UNREGISTERED-NATIVE-ROOT.md) har senere
verifisert en faktisk ny rot uten testnavneprefiks/ID-binding fra journalens
interne sti: 27 observasjoner med omstart, Preparing-avslag og positiv kontroll
på samme rot etter aktivering. Kontrollene starter etter native-kallets retur;
tilgang mens opprettingen pågår og produksjonens universelle grense er åpne.
[PRODUCTION-PROFILE-UI.md](PRODUCTION-PROFILE-UI.md) dokumenterer nå faktisk
Chrome-verifisering av det innebygde brukermenypunktet, egne innstillinger,
kontobytte med fremmed URL-parameter, versjonskonflikt og sletting av egen
nøkkel. Testmiljøet er ryddet. Hovedserveren er ikke oppdatert. Disse endringene
publiserer ennå ingen personlige native medier og beviser ikke full skjerming.

Tillegg om konverteringsrace 2026-10-12:
[NATIVE-CONVERTED-SYNC-ROOT-RACE.md](NATIVE-CONVERTED-SYNC-ROOT-RACE.md)
har bekreftet sletting av rot/kilde mens den faktiske native Ready-lagringen
av en ferdig MPEG-4-fil var pauset. 28 observasjoner: 22 HTTP, fire native
retention-readbacks og to fysiske filkontroller. Native jobb/element var borte
etter frigjøring/restart, men utdatafilen ble liggende. Alle provde gamle
filkall ble nektet med null bytes; B beholdt SHA-korrekt fil. Dette beviser
ikke skjerming av en beholdt fungerende Sync-referanse eller andre racevinduer.
Den varige løsningen trenger eksplisitt binding/opprydding av avledede filer.

Tillegg 2026-10-12: [NATIVE-LIBRARY-RECREATION.md](NATIVE-LIBRARY-RECREATION.md)
viser vellykket gjenoppretting med ny fysisk mappe, men fire B-metadataavslag
ved gjenbruk av mappe-GUID. Dette er et uløst funksjonsavvik, ikke observert
krysskontolekkasje. [NATIVE-CONVERTED-SYNC-FILES.md](NATIVE-CONVERTED-SYNC-FILES.md)
lukker én konkret filvariant: ekte MPEG-4-konverterte native Sync-filer,
16 HTTP-kontroller med SHA-verifiserte eierfiler og null-byte fremmedavslag
før/etter restart. Original-radene nedenfor gir derfor ikke hele den nyeste
fildekningen. Full skjerming og produksjons-/alle-klientintegrasjon er fortsatt
ikke bevist.

Opprinnelig revisjon 2026-10-11. Konklusjon: **ikke bevist**. Tabellen nedenfor
beskriver undersøkelsen og de isolerte gjennomførbarhetstestene fra dette
tidspunktet; produksjonstillegget over beskriver senere implementert arbeid.

Kravet fra samtalen er separate personlige YouTube-samlinger som opptrer som
vanlige Emby-biblioteker i alle klienttyper. Andre vanlige brukere skal ikke
kunne lese innhold eller metadata, oppdage samlingen gjennom oversikter eller
endre dens tilstand. Losningen skal ligge i pluginen og ikke forutsette en
ekstern tilgangsport eller en bestemt Docker-nettverkstopologi.

Brukeren avklarte senere eksplisitt at skjermingen gjelder mellom Emby-kontoer
ved tilgang til serveren. Allerede lagrede data i en delt lokal
OS-/nettleserprofil er ikke del av denne servergarantien. Alle klienttyper
skal fortsatt kunne bruke bibliotekene.

| Krav | Autoritativ evidens | Status og gjenstaende arbeid |
| --- | --- | --- |
| Biblioteker, lister, metadata, direkte oppslag og avspilling | Native rapport med 698 observasjoner nedenfor; egne video-byte som positiv kontroll | Provde ruter passerer i den syntetiske modellen pa Emby 4.10.1.0. Ikke generell dekning av alle ruter eller versjoner. |
| Ingen kryssmutasjon av Sync-jobber | Native jobbavtrykk i tidligere rapporter og de nye Premiere-kjoringene nedenfor | Provde opprettings-, kansellerings- og offline-statusforlop passerer. Ferdige Original-filer er na produsert og lest i egne kontrollrader; dette gir ikke generell dekning av alle mutasjoner. |
| Delte enheter og overlapp mellom brukere | Concurrent-rapport med 431 observasjoner; fire scenarioer, 96 HTTP/native kall og malt kryssbrukeroverlapp | Provde Sync/Data-forlop passerer. Ikke alle samtidige eierskifter eller races. |
| Cache-referanser avslorer ikke skjult innhold | Seks SameNormalizedResponseAndState-kontroller og native tilstandsavtrykk i Concurrent-rapport | Numerisk ID og GUID N/D passerer. Sammenligner parsede svar og status; ikke svartid eller alle headere. |
| Ferdige offline-filer beskyttes | Hovedserverens baseline og `bin/native-library-protected-sync-real-files-results.json`: ekte ReadyToTransfer og byte/hash-kontroller for begge eiere | Isolert prototype beskytter provde ferdige Original-filer etter omstart: eier 200 og korrekt SHA256, annen bruker og anonym 404 uten filbyte. Ikke transkoding, faktisk appcache eller generell rutegaranti. |
| Faktiske klientapper og tilgang til serveren | NATIVE-WEB-CLIENT-OBSERVATIONS.md: faktisk Chrome/Emby Web med egen avspilling og brukerbytte; ingen faktisk TV-/mobilklientrapport | Webkontrollene dekker de provde handlingene. Andre klienttyper og deres serverforesporsler er uverifisert. Gammel lokal fanetittel er observert, men allerede lagrede lokale data er utenfor brukerens avklarte servergaranti. |
| Samme pluginbeskyttelse uavhengig av Docker-topologi | Prototypen kjorer inne i serveren, uten tilgangsport | Teknisk gjennomforbarhet vist i testinstallasjonen. Ingen deployert sikkerhetsgrense i produksjonspluginen. |
| Holdbar sentral handheving | `PrivacyGuard.cs`: Harmony pa RequestHandler, ServiceController.Execute, WebSocketConnection og SyncManager | Interne metoder er avhengigheter. Den dokumenterte IHttpServer-kontrakten nedenfor gir ingen generell tilgangskontroll-hook. Fravaer i denne kontrakten beviser ikke at ingen annen utvidelsesmulighet finnes. Trenger en dokumentert garanti eller eksplisitt versjonsavgrensning med kontroll av alle avhengigheter. |
| Nye, flyttede og slettede elementer/eierskap over restart | Lifecycle-/new-root-/deleted-sync-kontroller; native-owner-deletion-results.json og native-owner-deletion-quarantine-results.json; HistoricalOwners er RAM i PrivacyGuard | Forste native-eiersletting feilet etter restart. En liten testprototypeendring setter manglende eier til sperret sentinel; ti nye HTTP-observasjoner og guard Ready/ny BootId passerer med B egen metadata 200 og fremmed/gammelt token 404. Ikke generell varig eierhistorikk, slettet rot, kanal-/default-eier eller alle Sync-/mediareferanser. |
| Brede enhetstillatelser og alle sync-providere | Broad-rapport med 469 observasjoner: EnableAllDevices=true, fire implicit-target-kontroller med tom native target-array og fire overlappscenarioer | Private Sync/Data-metadatajobber passerer med bred policy, ogsa pa forskjellige device-mal uten innsendt mal. Enhetspersonvern, ferdige filer og server/cloud-providere er fortsatt uverifisert. |
| Personlig API-nokkel og kanaloppsett isolert i produksjon | Profilprototypens 71/73 runtime-kontroller nedenfor; produksjonspluginen er uendret | Provde profilruter, serverintern nokkeldekryptering, samtidige foresporsler og restart er isolert i testmodellen. Produksjonsfunksjon, YouTube-jobber, kvote og bibliotekbinding er ikke implementert/bevist. |

## Rapporter lest ved denne revisjonen

- `bin/native-library-protected-dlna-sync-new-root-deleted-sync-multi-source-mixed-create-read-parity-targets-device-policy-variants-shared-references-results.json`: 698 observasjoner, ingen ikke-baseline-rader med Other=true. Den kjoringen hadde exit 0 og opprydding.
- `bin/native-library-protected-sync-shared-references-concurrent-results.json`: 431 observasjoner, fire bekreftede overlappscenarioer. Den kjoringen hadde exit 0 og opprydding.
- `bin/sync-feature-gate.json`: funksjonen tillot ikke faktisk SyncPrepare-konvertering. At oppgaven fikk status Completed er ikke bevis for ferdige offline-filer.

Tallene gjelder separate kjoringer og skal ikke summeres. Rapportene inneholder
positive og negative kontroller, baseline-moteksempler og oppsummeringsrader;
observasjonstallet er ikke et antall unike ruter eller et universelt bevis.

Broad-tillegg: `bin/native-library-protected-sync-shared-references-concurrent-broad-results.json` ble lest etter revisjonen. Kjoringen bestod med 469 observasjoner og exit 0; begge policies var brede. Fire implisitte kall beholdt tom native target-array, og bare de to rydd-kallene endret egen tilstand. Ingen endret den andre brukerens avtrykk.

## Dokumentasjon kontrollert

- [Creating API Endpoints](https://dev.emby.media/doc/plugins/dev/Creating-Api-Endpoints.html) beskriver egne pluginruter, ikke sentral eierkontroll for alle native ruter.
- [IHttpServer](https://dev.emby.media/reference/pluginapi/MediaBrowser.Controller.Net.IHttpServer.html) dokumenterer GlobalResponse, AddParts, Stop og WebSocketConnected. Prototypens interne Harmony-kroker folger ikke av denne kontrakten.
- [Automatic Type Discovery](https://dev.emby.media/doc/plugins/dev/Automatic-Type-Discovery.html) beskriver blant annet oppstart og egne tjenester. Listen alene er ikke en fullstendig sikkerhetsgaranti eller bevis pa umulighet.
- [Offline Access](https://emby.media/support/articles/Offline-Access.html) beskriver serverkonvertering, bakgrunnsnedlasting og lokal offline-avspilling. Dokumentasjonen lister Android Mobile, iOS og Windows for offline-nedlasting; web kan starte nedlasting til andre enheter. Dette avgrenser hvilke klienter som trenger offline-kontroller, men reduserer ikke kravet om vanlige biblioteker i alle klienttyper.

## Beslutning

Full skjerming kan ikke godkjennes ut fra de tilgjengelige rapportene.
Neste bevis ma lukke konkrete hull i tabellen, ikke bare oke antall observasjoner.
Det er fortsatt mulig a undersoke varig eierhistorikk, enhetspersonvern og
providerkontrakter lokalt. Hovedserveren er na tilgjengelig via eksisterende HA-SSH,
og legitim serverklargjoring av Sync-filer er verifisert. Fysisk appcache er fortsatt
uverifisert. Ingen lisenssjekk skal omgaes eller ferdige filer fabrikeres som bevis.

## Hovedserver: ekte Sync-fil og bekreftet krysstilgang

2026-10-11 21:00 UTC: Eksisterende SSH-integrasjon i HA ga tilgang til
openmediavault og Emby-containeren emby_backup. System/Info bekreftet Lilflix
4.10.1.0 og forventet server-ID; Plugins/SecurityInfo rapporterte IsMBSupporter=true.
Ingen legitimasjon ble skrevet til rapporten eller sendt ut fra hosten.

MainServerNativeSyncProbe.py opprettet to midlertidige vanlige brukere, hvert
sitt homevideos-bibliotek og en syntetisk 6-sekunders video. Policies ble lest
tilbake med EnableAllFolders=false, ett eget biblioteks-GUID og IsAdministrator=false.
Begge sesjoner ble kontrollert for riktig bruker. Kun syntetiske enheter ble
registrert som Sync-mal; eksisterende mobiltelefoner ble ikke brukt.

Begge native Sync-jobber med Quality=Original og Profile=Original fikk
ReadyToTransfer. Eier og annen bruker hentet /Sync/JobItems/{id}/File med HTTP 200.
Alle fire svar var 11071 byte, hadde MP4-signatur og var byte-identiske med
prøvevideoen. Dette er ekte native klargjoring og filtilgang, ikke fabrikkert
Sync-status. Transkoding eller nedlasting i en fysisk klientapp ble ikke testet.
PrivacyGuard var ikke installert pa hovedserveren; dette er et baseline-moteksempel.

Etter testen bekreftet nye API-oppslag at testbrukere, biblioteker og Sync-jobber
var borte. Prøvemappen var fjernet; alle ryddeoperasjoner, inkludert sletting av
de syntetiske enhetene, fullforte uten feil. Ingen serverrestart ble utfort.
Den etterfolgende kontrollen nedenfor provde beskyttelsen i isolert miljo uten
a innfore den isolerte prototypens globale oppstartssperre pa hovedserveren.

## Isolert Premiere: ekte filer og en ny metadatalekkasje

Embys offisielle [Using Multiple Servers](https://emby.media/support/articles/Premiere-Multiple-Servers.html)
tillater samme Premiere-nokkel pa flere servere; enhetsgrensen gjelder samlet.
Eksisterende nokkel ble kryptert med en midlertidig offentlig RSA-nokkel pa
Docker-hosten, dekryptert lokalt i minnet og registrert gjennom testserverens
vanlige POST Plugins/SecurityInfo. GET av samme endepunkt bekreftet
IsMBSupporter=true. Klartekstnokkel ble ikke sendt til rapport eller chat.
Den midlertidige private overforingsnokkelen er slettet. Ingen feature- eller
lisenssjekk ble endret eller omgaatt.

Kjoring med RequireProtected, ProbeSync og ProbeRealSyncFiles fikk ekte
ReadyToTransfer for begge native Original-jobber. Filene gav 11071 byte og
samme SHA256 som den syntetiske kilden. For beskyttelsen fikk begge fremmede
brukere filen; etter aktivering og verifisert serverrestart fikk bare eier
filen, mens fremmed bruker og anonym fikk 404 uten filbyte.

Forste kontroll fant likevel to metadatalekkasjer i Sync/Items/Ready:
List<SyncedItem> har et nestet Item og en konvolutt med jobbnavn og filreferanser.
Filteret sjekket direkte ID-felter, og beholdt denne konvolutten.
Moteksemplet er bevart i bin/native-ready-file-metadata-before-filter.json.
ResponseObjectAllowed avviser na hele konvolutten nar nestet Item.Id er skjult;
den samme regelen er lagt inn for serialisert JSON og XML.

Ny fokusert kjoring fullforte med 231 observasjoner, ingen rapporterte
lekkasjer og exit 0. Begge egne filer passerte den sterke byte/hash-kontrollen,
og begge fremmede Ready-lister mistet den andre brukerens metadata.
Testpluginen ble fjernet, serveren stoppet, og native testbrukere, biblioteker
og jobber ble ryddet og lest tilbake. Dette er et avgrenset bevis for provde
serverruter i Emby 4.10.1.0, ikke full klient- eller produksjonsdekning.

Rapportfelter HasConvertedFile=false i eldre Shared Sync-kontroller var
hardkodet for a angi at disse kontrollene bare verifiserte metadata. De er
ikke bevis for fravaer av en fil, spesielt etter Premiere-aktivering. Nye
kjoringer bruker det presise feltet ConvertedFileVerified=false. Faktisk
filtilgang bevises av Real Sync-radene, ikke av disse metadatafeltene.

## Utvidet kontroll med Premiere og delte enheter

Den brede DLNA-/native-kjoringen fullforte med 536 observasjoner, ingen
rapporterte lekkasjer og exit 0. Den dekket blant annet nye rotmapper,
eierskifte, inkrementell skanning, sletting, restart, fler-element-jobber,
skjult/manglende svar, enhetspolicy og target-varianter, samt de ekte
Original-filene. SharedReferences-flagget i den kommandoen var uten effekt
fordi SharedSync ikke var valgt. Scriptet avviser na slike manglende
avhengigheter; denne rapporten er ikke evidens for delte enheter.

Delte enheter ble testet separat med alle relevante flagg aktivert:
`Run-NativeLibraries.ps1 -RequireProtected -ProbeSync -ProbeSharedSync
-ProbeSharedReferences -ProbeConcurrentSync -ProbeBroadSync -ProbeRealSyncFiles`.
Rapport: bin/native-library-protected-sync-shared-references-concurrent-broad-real-files-results.json.
Komplett kjoring hadde exit 0, 783 observasjoner og ingen rapporterte lekkasjer.

Begge vanlige brukere fikk EnableAllDevices=true ved bekreftet policy-readback,
og autentiserte sesjoner brukte samme syntetiske DeviceId. I 60 nye native
Sync-jobber, fordelt pa begge eiere og cache-/samtidighetsscenarioene, ble
ReadyToTransfer lest tilbake for ekte Original-filer. Alle 60 eierhentinger
gav HTTP 200, 11071 byte og korrekt SHA256; alle 60 fremmede og 60 anonyme
hentinger gav 404 uten filbyte. Alle 60 Ready-listekontroller viste eget
innhold uten den andre eierens metadata. Jobbene brukte de samme to
syntetiske kildevideoene; dette er ikke 60 uavhengige medieformater.

De fire samtidighetsscenarioene utforte 24 faktiske native kall hver,
96 totalt. Malte kryssbrukeroverlapp var henholdsvis 18, 19, 19 og 12;
alle hadde null aktive kall etter avslutning, og ingen feilstatus eller
feilrespons. Native jobbavtrykk bekreftet at kall ikke endret fremmed
tilstand. Native sync-funksjonssjekk rapporterte Allowed=true i denne
lisensierte kjoringen. Dette erstatter ikke en generell race-garanti.

Etter kjoringen var testpluginen fjernet og ingen testserverprosess i live.
Brukere, biblioteker og jobber ble ryddet med API-readback, og syntetiske
mediefiler ble fjernet. Personlige API-profiler, varig eierhistorikk,
transkoding/provider-dekning og faktiske klientapper er fortsatt uavklart
for kravet om full skjerming. Ingen produksjonsimplementasjon er levert.

## Native synlighetskontroll: nytt moteksempel

Ny native baseline med ProbeStrictUserPolicy hadde 56 observasjoner og exit 0.
Begge vanlige brukere hadde IsAdministrator=false, EnableAllFolders=false og
eget bibliotek-GUID, samt EnableRemoteControlOfOtherUsers=false og
EnableSharedDeviceControl=false ved policy-readback. Likevel fikk begge den
andres direkte metadata/PlaybackInfo og MP4-strom/nedlasting med HTTP 200
og 11071 byte. Rapport: bin/native-library-strict-policy-results.json.
Dette lukker antakelsen om at de tidligere moteksemplene bare skyldtes de
brede fjernstyringsrettighetene brukt i testharnessen.

Emby-teamets [forklaring fra 2019](https://emby.media/community/topic/69575-deny-access-to-libraries-and-videos-via-direct-urls/)
beskrev at direkte tilgang var tillatt for fjernstyring av en annen brukers
sesjon, og at nye utvidelsespunkter ikke alene loste dette. Den historiske
forklaringen er bakgrunn; dagens runtime-test, ikke dette gamle svaret,
er evidensen for oppforselen i 4.10.1.0. Testbrukere, biblioteker og filer
ble ryddet, og testserveren ble stoppet.

`bin/native-library-protected-visibility-results.json` har 76 observasjoner
og en komplett kjoring med exit 0. Begge native IsVisible-kontroller gir false
for fremmed video, mens atte direkte API-foresporsler uten ekstra guard likevel
gir metadata/PlaybackInfo eller hele MP4-filen med HTTP 200. De vanlige 58
beskyttelseskontrollene passerer etter at testgrensen aktiveres og restartes.

[BaseItem-dokumentasjonen](https://dev.emby.media/reference/pluginapi/MediaBrowser.Controller.Entities.BaseItem.html)
beskriver at IsVisible kan overstyres. Testen viser at korrekt negativt native
synlighetsresultat ikke er tilstrekkelig for de provde direkte rutene. Den
beviser ikke at en egen persistert subtype eller enhver annen SDK-losning er
umulig. Intern hook-handheving og end-to-end-kontroll er fortsatt uavklart som
holdbar produksjonslosning; full skjerming kan ikke godkjennes.
## Personlige innstillinger og eksisterende Admin-grense

Ny slettingskontroll uten MultiSource-flagg fullforte med 269 observasjoner og
exit 0 (bin/native-library-protected-sync-new-root-deleted-sync-real-files-results.json).
Etter sletting av eneste kilde forsvant den native jobben; eier og annen bruker
fikk begge 404, ogsa etter restart. Dette provde ikke beholdt privat historikk.

Et forsok pa privat/offentlig blandet jobb med to eksplisitte ItemIds viste
at native CreateSyncJob opprettet to separate jobber, hver med ItemCount=1 og
sin egen RequestedItemIds. Jobbnavnet kom fra medieelementet. Oppsettet var
derfor ugyldig for den tilsiktede historikk-kontrollen; det er ikke rapportert
som bestatt eller som en personvernlekkasje. Det eksperimentelle oppsettet er
fjernet fra testscriptet, og restene ble ryddet med API-/fil-readback.
Observasjon og opprydding: bin/public-survivor-native-separate-jobs.json.
Varig eierhistorikk for beholdte private referanser er fortsatt ikke bevist.

Se [PERSONAL-ISOLATION-REQUIREMENTS.md](PERSONAL-ISOLATION-REQUIREMENTS.md). Kodeinspeksjon bekrefter global konfigurasjon, kanalidentitet og kvoteteller i produksjonen. Runtime-testen av dagens Admin-konfigurasjon bestod med 67 observasjoner og exit 0: vanlige brukere fikk 403, anonym fikk 401, og de tre relevante konfigurasjonsverdiene var uendret. Den separate personlige profilprototypen bestod senere 71 kontroller uten sentral guard og 73 med guard, inkludert opprydding, samtidige HTTP-kall og restart. Disse kontrollene beviser ikke produksjonsfunksjon eller faktisk YouTube-/bibliotekbinding.

## Faktisk webklient og slettet-eier-feil

Chrome ble tilgjengelig og faktisk Emby Web 4.10.1.0 ble provd med to vanlige
brukere, egne native biblioteker og guard aktiv. Begge kunne spille egen
syntetiske video (blatt/rodt videobilde observert). Brukerbytte viste riktig
bibliotek, og gamle fremmede detaljlenker viste generell feil uten innhold
eller avspillingsknapp. Ved Tilbake til As tidligere side som B beholdt
nettleserfanen imidlertid As videotittel inntil reload. Full klientskjerming
pa en delt nettleserprofil kan derfor ikke godkjennes fra denne testen.

En separat test slettet A med readback. As gamle token og Bs fremmede
foresporsel gav 404, mens B fortsatt fikk egen metadata med 200. Etter
bekreftet restart gav alle fire provde foresporsler 500, inkludert Bs egen
metadata. Oppstartsloggen bekreftet Unknown root owner. Guardens persisterte
rotkobling krever fortsatt en eksisterende eier. Dette er et moteksempel for
brukbar gjenoppretting etter eiersletting, ikke en bestatt skjermingskontroll.

Se [NATIVE-WEB-CLIENT-OBSERVATIONS.md](NATIVE-WEB-CLIENT-OBSERVATIONS.md) for
handlinger, avgrensninger, rapport og verifisert opprydding. TV-/mobilapper,
offline/lokal cache og varig behandling av foreldrelost eierskap gjenstar.

## Native privatmerking og klientens egen lagring

En ny test uten guard provde dokumenterte MakePrivate og Items/Access pa
normal biblioteksrot og Video, som vanlig bruker og admin. MakePrivate gav
400, Items/Access None 403. Direkte fremmed metadata, PlaybackInfo og Download
fortsatte aa gi 200. Kjoringen hadde exit 0 og 14 observasjoner; den nye
nedlastingsraden har ikke byte/hash-bevis. Testen lukker ikke muligheten for
andre native elementtyper, men loser ikke private vanlige biblioteker i
dette oppsettet. Endelig prosess-readback bekreftet ingen testserver i live.

Se [REMAINING-BOUNDARIES.md](REMAINING-BOUNDARIES.md) for evidens, eksplisitte
begrensninger og konkrete krav til varig eierhandtering og klientisolering.
Emby dokumenterer at offline- og webnedlastinger lagres lokalt. At en ren
serverkontroll ikke kan styre lesing av allerede utleverte frakoblede kopier
er en slutning fra den mekanismen, ikke et runtime-funn av blandede appdata.

## Avgrenset eksperiment: sperret native rot uten eksisterende eier

Brukeren avklarte at allerede lagrede lokale data er utenfor servergarantien.
Dette lokale kontrollpunktet blokkerer derfor ikke denne garantien.

Bare i PrivacyGuard-testprototypen ble Unknown root owner endret til eier=-1
for en persistert native rot med manglende bruker-GUID. Ingen autentisert
bruker kan matche denne sperrede eierskapsverdien. Andre roter beholder eier.
Produksjonspluginen ble ikke endret.

Test-NativeOwnerDeletion.ps1 -RequireOrphanIsolation hadde exit 0 og ti
HTTP-observasjoner med eksplisitte forventede statuser. B fikk egen metadata
200 for/etter sletting og etter restart; B mot As video og As gamle token
fikk 404 uten markornavn. Offentlig serverinfo var 200 etter restart, og
guard var Enabled/Ready med ny BootId. Rapport:
bin/native-owner-deletion-quarantine-results.json. Den opprinnelige
500-rapporten er beholdt.

Dette lukker det konkrete metadata-/token-feilforlopet for en fortsatt
eksisterende native rot. Det beviser ikke slettet rot, default-eier,
kanaleier, beholdte Sync-referanser eller full route-/klientdekning.
Oppryddingen bekreftet brukere/biblioteker/filer fjernet; etterfolgende
prosess-readback bekreftet null testserverprosesser.

## Ferdige filer ved eiersletting og deklarerte ruter

Test-NativeOwnerReadyFiles.ps1 hadde exit 0, 31 observasjoner og fire
positive file-byte/SHA256-kontroller: A/B for sletting, B etter sletting og
etter restart. Gamle A-jobb-/jobbelement-/filreferanser ble avvist for B,
gammelt A-token og anonym. B beholdt eget innhold i lister og Ready-liste.
Passiv native GetJob-kontroll bekreftet at As jobb faktisk var fjernet av
Emby, ikke beholdt. Dette er derfor ikke et bevis for en bevart privat jobb
uten fortsatt tilgjengelige kildereferanser.

582 deklarerte RouteAttribute-oppforinger ble hentet fra innlastede
assemblier. Dette er kandidater med metoder/aliaser, ikke antall unike
registrerte, testede eller relevante sikkerhetsruter. HLS, bilder,
undertekster og stream-ID-baserte ruter trenger videre vurdering.
Se [NATIVE-READY-OWNER-DELETION.md](NATIVE-READY-OWNER-DELETION.md) for
autoritativ rapport, begrensninger og opprydding.

## Native PNG, SRT og HLS

En komplett ny mediekjoring med exit 0 hadde 60 HTTP-kontroller: begge eiere
for/etter restart, fem ressurser (PNG, SRT, HLS master, mediemanifest og
forste TS-segment), som eier, annen bruker og anonym. Alle eierkontroller
var 200 med faktiske nyttelaster; bildene matchet eget opplastet bildehash,
underteksten hadde eget merke, manifestene EXT-M3U og segmentene TS-syncbyte.
De 40 negative kontrollene gav 404 uten private markornavn.

En separat kilde-mismatch-kjoring hadde exit 0 og 64 rapportoppforinger:
60 ordinare kontroller og fire parvise HTTP-sammenligninger for
undertekstruten. Egen video med fremmed mediekilde-ID gav samme tomme
200-respons som egen video med ikke-eksisterende kilde-ID, uten fremmed
tekstmarkor. Dette er ikke et bevis for HLS-kildemismatch.

Se [NATIVE-MEDIA-ASSET-OBSERVATIONS.md](NATIVE-MEDIA-ASSET-OBSERVATIONS.md)
for positive kontroller, faktisk PlaySessionId, beholdte feilrapporter,
rapportenes presise betydning og opprydding. Andre aliaser, mutasjoner,
LiveStreamId-ruter og faktiske TV-/mobilklienter er fortsatt ikke lukket.

## Produksjonens YouTube-kilde og native klienter

Den faktisk innlastede MakeMediaSources, native-detektor og
NormalizeYouTubeMediaSources ble provd med en syntetisk YouTube-ID og tre
headerkombinasjoner. Native Theater uten nettlesermotor ble gjenkjent som
native og fikk DirectPlay=false, DirectStream=false, Transcoding=false og
ingen TranscodingUrl. Web og Theater med Chrome-lignende User-Agent beholdt
DirectPlay=true. Alle hadde watch-URL og RequiresOpening/Closing=false.

Dette er et konkret kompatibilitetspunkt for all-klient-kravet, ikke en
fysisk apptest eller en paastand om alle appversjoner. Lokale MP4/HLS-
kontroller kan ikke erstatte egen YouTube-avspilling i klienten. Vanlig
annonserte YouTube-kilde krever ikke LiveStreamId, men dette utelukker ikke
direkte API-ruter eller alternative kildeleverandorer.
Se [YOUTUBE-SOURCE-COMPATIBILITY.md](YOUTUBE-SOURCE-COMPATIBILITY.md) for
metoder, faktisk rapport, presise begrensninger og verifisert opprydding.

## LiveStream-ID og native metadata-oppslag

Ny read-only IL-inspeksjon av faktisk innlastet Emby 4.10.1.0 viste at
Post(GetLiveStreamMediaInfo) -> GetLiveStreamMediaSource -> GetLiveStreamInfo
bruker bare LiveStreamId og en felles _openStreams-tabell. Disse metodene
har ingen kontosjekk. Dette utelukker ikke eksterne request-filtre og er
ikke et runtime-bevis for fremmed tilgang til en gyldig privat strom.
Testguard unntar LiveStreamId fra elementreferanser og mangler en egen
eierbinding for slike ID-er. Denne grensen er fortsatt aapen dersom
private kilder kan opprette dem; RequiresOpening=false alene lukker den
ikke. Rapport, assembly-hash og opprydding er dokumentert i
[LIVE-STREAM-OWNERSHIP.md](LIVE-STREAM-OWNERSHIP.md).

Etterfolgende native kjoretest opprettet gyldige strommer gjennom
LiveStreams/Open med en syntetisk lokal provider. Begge vanlige eiere
fikk Open=200 og egne metadata=200. Den andre kontoen fikk ogsa
MediaInfo=200 med privat videonavn, lokal filsti og kilde-ID. Anonym fikk
401 og fremmed Open med privat ItemId fikk 404. Dette er to konkrete
metadata-lekkasjer i prototypen, ikke bare en aapen statisk hypotese.
Rapporten native-live-stream-access-results.json er fullfort med exit 0,
12 observasjoner og FullIsolationPassed=false. Ingen videobytes eller
dagens YouTube-stromflyt ble provd. Hele oppsettet, begrensningene og
verifisert opprydding er beskrevet i samme dokument. Full skjerming kan
derfor ikke godkjennes for denne prototypen.

Ny isolert retting binder LiveStreamId til faktisk lokal kildeeier etter
native Open og vurderer ID-en i referansekontrollen. To kjoringer med
verifisert restart mellom dem, 18 observasjoner hver, lukket det konkrete
MediaInfo-hullet: egne metadata=200, fremmed=404, anonym body=401, spoofet
UserId=404 og fremmed Close med kjent PlaySessionId=404. Eierens metadata
var fortsatt 200 etter Close-forsoket og egen Close=204. Baseline med de
to lekkasjene er beholdt. Denne avgrensede rettingen bygger pa lokal
kildesti og prosesslokale bindinger; den beviser ikke YouTube-eierskap,
prekontroll av blandede OpenToken/ItemId, samtidig bruk eller alle klienter.
Se [LIVE-STREAM-BINDING-EXPERIMENT.md](LIVE-STREAM-BINDING-EXPERIMENT.md).

Ny mixed-OpenToken-test viste at etterkontroll alene gav 404, men faktisk
opprettet en fremmed strom i native _openStreams i begge retninger.
Baseline er bevart. Prototypen binder naa private OpenToken ved native
kildeforberedelse og kontrollerer referansen for OpenMediaSource starter.
To rettingskjoringer med restart mellom dem gav 20 mixed-testobservasjoner
uten ekstra fremmed provider-Open eller native strom; egne Open/metadata/
Close virket. Tidligere stromisolasjon passerte ytterligere 36 observasjoner.
Dette er 56 konkrete rettingsobservasjoner, ikke et all-ruter/all-klient-
bevis. Ukjente/public-kombinasjoner, gamle tokens og andre kildeleverandorer
er fortsatt egne grenser. Se
[OPEN-TOKEN-PRECHECK-EXPERIMENT.md](OPEN-TOKEN-PRECHECK-EXPERIMENT.md).

Gammel-token-test etter ekte restart fullforte med 15 observasjoner.
Med privat ItemId ble B sin gamle gyldige token nektet for native Open,
baade for A og B. Med ItemId utelatt fikk A fortsatt 404, men en B-provider-
Open og en faktisk ekstra B-strom i native tabell. Senere gjenutstedelse
gav eksakt samme token, og B sin Open/MediaInfo/Close passerte med den.
Dette bekrefter en gyldig gammel referanse og en gjenværende sideeffekt,
ikke bare en hypotese eller tilfeldig ugyldig ID. Ingen tokenverdier ble
lagret i rapport. Se
[STALE-OPEN-TOKEN-OBSERVATIONS.md](STALE-OPEN-TOKEN-OBSERVATIONS.md).

Varig testregister binder naa SHA256(OpenToken) til bruker-GUID, med
schema-/formatkontroll og readback av lagring. Gammel-token-testen passerte
17 observasjoner etter ekte restart: fremmed privat ItemId og utelatt
ItemId ble nektet uten native sideeffekt, mens B kunne aapne/lukke med
sin gamle token for gjenutstedelse. Mixed-token og stromisolasjon passerte
ytterligere 10+18 observasjoner. Dette er 45 avgrensede kontroller og
lukker det paaviste gamle-token-moteksemplet. Konstruerbare aldri-utstedte
tokens, slettet eier, korrupt register, andre kildeleverandorer og fysisk
YouTube-klientavspilling er ikke bevist. Se
[TOKEN-LEDGER-EXPERIMENT.md](TOKEN-LEDGER-EXPERIMENT.md).

Slettet tokeneier + ny konto med samme navn er naa runtime-provd med
18 observasjoner. Gamle A-referanser uten ItemId ble nektet for B og
den nye samme-navn-kontoen med 404, og slettet A sin auth-token fikk 401,
for/etter verifisert restart. Ingen ekstra A-provider-Open/native strom
oppstod. B sine egne Open/MediaInfo/Close fortsatte aa virke, og ledger-
readback beholdt gammel bruker-GUID. Dette gjelder bevart privat rot og
allerede utstedt referanse, ikke alle livssyklus-/kildetilfeller. Se
[TOKEN-OWNER-RECREATION-OBSERVATIONS.md](TOKEN-OWNER-RECREATION-OBSERVATIONS.md).

Konstruert aldri-utstedt B-token var ikke i ledger, men kunne aapne en
B-strom nar A utelot ItemId, selv om svaret var 404. Senere utstedelse
gav identisk token og B sin positive kontroll passerte. Baseline er beholdt.
Ny kildekontroll i fixture-providerens OpenMediaSource sammenligner faktisk
elementeier med autentisert AsyncLocal-scope for strom opprettes. To
friske kjoringer lukket dette konkrete hullet (8+8), og mixed/metadata/
gammel-token-regresjon passerte 10+18+17. Siste kjoring observerte eksplisitt
kildeavslag med delta 1 og ingen provider-Open/native strom. Dette er 61
rettingsobservasjoner; samtidig scopeisolering, andre leverandorer og
faktiske YouTube-klienter er ikke bevist. Se
[UNISSUED-SOURCE-GUARD-EXPERIMENT.md](UNISSUED-SOURCE-GUARD-EXPERIMENT.md).

Samtidige native Open-oppgaver fra begge kontoer er naa provd med seks
HTTP-arbeidere og en await-forsinkelse for faktisk kildeeierkontroll.
Begge kjoringer (for/etter verifisert restart) hadde 36 observasjoner,
seks native Open-oppgaver, to subjects, fem cross-subject-overlapphendelser
og opptil seks aktive oppgaver. Egen tilgang/lukking virket, fremmed
metadata/Close ble nektet, og ingen native strommer stod igjen. Dette
beviser ikke alle interne kritiske seksjoner, konstruerte referanser under
last eller andre scheduling-forlop/klienter. Se
[CONCURRENT-STREAM-SCOPE-OBSERVATIONS.md](CONCURRENT-STREAM-SCOPE-OBSERVATIONS.md).

Felles ra YouTube-video-ID er kontrollert pa nytt med dagens prototype
og to vanlige kontoer: ni HTTP-observasjoner, separate Emby-identiteter,
egne metadata 200, fremmed 404 og uavhengig Played-verdi. Fremmed Played-
mutasjon ble nektet og B sin verdi forble false. Dette er syntetisk
kanalmodell, ikke produksjonens bibliotekimport. Tidligere lifecycle-
evidens viser dessuten at mutable IChannel.Name endret kanalidentitet
selv med uendret deklarert Id; en varig samlingsmapping er fortsatt
nodvendig. Se
[SHARED-VIDEO-IDENTITY-OBSERVATIONS.md](SHARED-VIDEO-IDENTITY-OBSERVATIONS.md).

Native vanlig-bibliotek-navnebytte er naa provd via ekte POST
Library/VirtualFolders/Name (204), med kontrollert midlertidig admin-
eierskap bare for adminhandlingen. Rot-ID/GUID var stabile; etter gjen-
oppretting av A-eierskap og faktisk restart virket gamle video-ID-er,
fremmed tilgang ble nektet og eget PlaybackInfo hadde korrekt filkilde.
Den styrkede kjoringen har 19 observasjoner med innholdskontroll; en
tidligere status-only-kjoring er bevart. Dette er en annen native modell
enn IChannel.Name-identiteten og beviser ikke YouTube-avspilling, rot-
flytting eller alle navne-/livssyklusendringer. Se
[NATIVE-LIBRARY-RENAME-OBSERVATIONS.md](NATIVE-LIBRARY-RENAME-OBSERVATIONS.md).

Sletting av native biblioteksrot er naa faktisk provd med 11 observasjoner:
ekte DeleteVirtualFolder 204, rot fravaerende i readback, B sitt eget
innhold korrekt 200 etter sletting, men HTTP 500 ogsa for B etter faktisk
omstart nar den slettede rotens mapping er beholdt. Dette er en konkret
tilgjengelighetsfeil i prototypen; ingen privat videomarkor ble observert
i de fire 500-svarene. Source-level oppstart krever at hver rot finnes.
Nodvendig videre arbeid er varig slettet-samlingstilstand og proveniens
for gamle referanser, samtidig som gyldige andre samlinger fortsatt
virker. Bare skipping av manglende rot beviser ikke dette. Se
[NATIVE-ROOT-DELETION-OBSERVATIONS.md](NATIVE-ROOT-DELETION-OBSERVATIONS.md).

Oppfolging: forste HTTP-svar etter omstart er et utilstrekkelig
beredskapskriterium. Med 30 sekunders guard-ready-venting bekrefter
gammel oppstartslogikk 503 (ikke bare den opprinnelige umiddelbare
500-observasjonen) og Unknown private library root i loggen. Et nytt
isolert native referanseregister bestod 15 rot-slettingskontroller:
B eget innhold og PlaybackInfo med korrekt filkilde fungerer etter
omstart, guard er klar og gamle slettede referanser er nektet.
Disk-readback bekrefter bevart slettet samling/medlems-ID og B sin
aktive eier-GUID. Navnebytte-regresjon med samme register bestod 19
innholdskontroller. Nye medlemmer mellom snapshots, avledede gamle
ressurser, gjenoppretting og native ID-gjenbruk er fortsatt uavklart;
ingen produksjonsimplementasjon eller alle-klienter-bevis. Se
[NATIVE-REFERENCE-LEDGER-EXPERIMENT.md](NATIVE-REFERENCE-LEDGER-EXPERIMENT.md).

Nytt medlem mellom snapshots er naa testet med ekte native scan og
SDK-sletting av bare det nye syntetiske itemet. Snapshot-prototypen
mistet privat klassifisering etter restart selv om native metadata
fortsatt svarte 404 (ingen observert lekkasje). Hendelseslagring for
ItemAdded/Updated/Removed bevarer naa numeric/GUID-referanser og
slettet tilstand. Ni growth-observasjoner og register-readback bestod;
rot-sletting (15) og navnebytte (19) bestod som regresjoner. Fortsatt
ikke bevist: nytt medlem fulgt av hel rot-sletting uten nytt snapshot,
gjenværende avledede ressurser, hendelsestiming/diskfeil/gjenoppretting,
produksjonsfunksjon eller alle klientfamilier. Se
[NATIVE-MEMBER-EVENT-PERSISTENCE.md](NATIVE-MEMBER-EVENT-PERSISTENCE.md).

Ny innskannet video fulgt av hel rot-sletting uten nytt Enable/snapshot
eller eierbytte er nå verifisert for metadata/varig klassifisering:
13 observasjoner, A fortsatt korrekt eget innhold før betrodd native
adminsletting 204, B nektet både godkjenning og native sletting 403,
SDK GetItemById bekrefter faktisk katalogfravær, uendret eierconfig-hash,
godkjenning uten ledger-hash-endring, og bevart slettet rot/nytt medlem
med opprinnelig A-GUID etter ready/restart. B beholdt korrekt eget
innhold. Gjenværende avledede ressurser/mediebytes og gjenoppretting/
ID-gjenbruk er ikke bevist av disse metadata-kontrollene. Se
[NATIVE-GROWTH-WHOLE-ROOT-DELETION.md](NATIVE-GROWTH-WHOLE-ROOT-DELETION.md).

Gjenværende native stream etter samme rot-sletting er nå faktisk
observert i _openStreams: A fortsatt metadata 200, B MediaInfo/Close
404 uten endring i native A-stream/provider-close-tall. B egne
strømmer fungerer. Etter restart er A-strømmen borte; gammel og
tilfeldig ukjent ID gir samme tomme MediaInfo 204/Close 204. Gammelt
A-OpenToken uten ItemId gir B 404/A 400 uten ny A-provider/native
åpning; B egen metadata/Close fungerer fortsatt. 35 observasjoner
bestod. Dette er beholdt kilde-METADATA, ikke transportbytes eller
Ready Sync-bevis; tilbakekalling for legitim original eier er heller
ikke bevist. Se
[NATIVE-DELETED-ROOT-LIVE-STREAMS.md](NATIVE-DELETED-ROOT-LIVE-STREAMS.md).

Native Ready Original-filer etter hel rot-sletting er nå kontrollert
med legitim sync-feature og eksisterende A-konto/uendret config:
31 observasjoner (29 HTTP, to native retention-readbacks), fire
komplette filer 200/11 071 bytes med korrekt SHA-256; sju avslåtte
filkall 404 med faktisk 0 raw payload-bytes. B egne filer/lister
virker etter sletting og restart, gamle A-job/jobitem/file-kall
nektes også for A og anonym. Native GetJob viser imidlertid A-jobben
borte i begge faser. Dette er IKKE en beholdt-Sync-jobb-test; mulig
foreldreløst item/klargjøring-slette-race/andre profiler er uavklart.
Se
[NATIVE-ROOT-READY-ORIGINAL-FILES.md](NATIVE-ROOT-READY-ORIGINAL-FILES.md).

Direkte native GetJobItem-retention er nå kontrollert uavhengig av
parent-jobben: eksisterende A-rad/parent og ReadyToTransfer før full
filhenting, eksisterende rad/parent og Transferring etter filhenting,
deretter konkret gammel rad borte etter rotsletting og restart (og
jobben borte). Styrket kjøring: 35 observasjoner, 29 HTTP og seks
native readbacks, med fire SHA-verifiserte fullfiler og sju null-byte
denials. Dette er ikke generell orphan-fravær eller beholdt Sync-
ressurs-tilgangsbevis; samtidighet/avbrudd/andre profiler gjenstår.
Se
[NATIVE-ROOT-SYNC-ITEM-RETENTION.md](NATIVE-ROOT-SYNC-ITEM-RETENTION.md).

Fersk native IL-inspeksjon identifiserer nødvendig overlappspunkt:
ProcessJobItem oppretter kanselleringshåndterer/ChainedToken før
SyncVideo, men SyncVideo skriver Status og kaller UpdateSyncJobItemInternal
direkte i tillegg til statushjelperen. UpdateSyncJobItemInternal kaller
SyncRepository.Update. En pause bare ved SetJobItemStatus kan derfor
bomme; riktig kandidat er den faktiske repository-forløperen med
runtime-ReadyToTransfer og forventet privat kilde/OutputPath. Ingen
samtidighetskjøring ennå, og ingen ny isolasjons-pass-count. Se
[NATIVE-SYNC-PREPARE-WRITE-SURFACE.md](NATIVE-SYNC-PREPARE-WRITE-SURFACE.md).

Samtidighet ved det konkrete native Ready-skrivepunktet er nå faktisk
kontrollert: én privat A-kilde pausert ved UpdateSyncJobItemInternal
med ReadyToTransfer/faktisk eksisterende forventet OutputPath; native
rot OG video slettet mens gate fortsatt Active/ikke TimedOut, uendret
eierconfig, kontrollert frigjøring. Denne versjonen klargjør Original
inne i POST Sync/Jobs, så opprettelseskallet måtte være asynkront.
26 observasjoner bestod: 22 HTTP, fire native retention-readbacks,
tre komplette SHA-korrekte B-filer og seks 0-byte file-denials. A-jobb
OG direkte item borte etter overlapp og restart; legitim sync-feature
observert før restart. Ett punkt/Original/4.10.1.0 er ikke alle race-
vinduer eller beholdt-Sync-ressurs-bevis. Se
[NATIVE-SYNC-PREPARE-ROOT-RACE.md](NATIVE-SYNC-PREPARE-ROOT-RACE.md).
