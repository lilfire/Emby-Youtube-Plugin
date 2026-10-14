# Samlet status for personlig YouTube og full skjerming

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


Ny rettelse 13. oktober 2026: [PRODUCTION-METADATA-REFERENCES.md](PRODUCTION-METADATA-REFERENCES.md)
bevarer 40 ordinære lekkasjer gjennom direkte metadata-navn og ID-er.
Genre/Studio/Tag får nå tilgang fra en faktisk synlig og tillatt
innholdskilde. Navne-DTO-ene er inkludert i referanse-/skriverkontrollen,
totalt 15 DTO-er. Privat og blandet offentlig/privat matrise bestod 191
observasjoner hver, inklusive utelatt UserId, sletting og omstart.
Øvrige metadataressurser, samtidighetsgrenser og full skjerming gjenstår.

Ny rettelse 13. oktober 2026: [PRODUCTION-METADATA-LISTS.md](PRODUCTION-METADATA-LISTS.md)
bevarer ordinære metadata-lekkasjer. Tre nye DTO-er gir åtte listefamilier.
Merkelapper krevde binding til tillatte native kilde-linker; en query-prefix
alene skjulte ikke den globale indeksen. Seks skriver-/slettingsløp bestod
363 observasjoner, og et eget løp med anonymt og private metadata-ID-er
bestod 65. Direkte metadatareferanser, øvrige varianter og full skjerming
er fortsatt ubevist.

Ny rettelse 13. oktober 2026: [PRODUCTION-ITEM-COUNTS.md](PRODUCTION-ITEM-COUNTS.md)
bevarer antallslekkasje med faktiske filmer. DTO nummer fem normaliserer
bruker og filtrerer native telling; private ParentId-er avvises særskilt.
Egen positiv kontroll, fremmede numeriske/GUID-referanser, påstått/utelatt
UserId, anonymt, sletting/omstart og begge skrivergrenser bestod 111 og 112
observasjoner. Nulltelling av hjemmevideoer er uttrykkelig ikke et bevis.
Øvrige metadata- og klientkrav og full skjerming er fortsatt uferdige.

Ny rettelse 13. oktober 2026: [PRODUCTION-SUGGESTIONS.md](PRODUCTION-SUGGESTIONS.md)
bevarer et ordinært forslag-kall som viste begge private videoer. DTO nummer
fire normaliserer nå faktisk bruker, filtrerer native queries og fører det
typede resultatet gjennom native factory og felles skriverkontroll.
Eget innhold, sletting/omstart og begge skrivergrenser bestod 18 og 19
observasjoner. Full skjerming og alle klienter er fortsatt ubevist.

Ny rettelse 13. oktober 2026: [PRODUCTION-DISCOVERY-LISTS.md](PRODUCTION-DISCOVERY-LISTS.md)
beskriver en faktisk normal API-lekkasje i bibliotekoversikt/nyeste.
Listefamiliene er utvidet til tre DTO-er, og det faktiske view-mapparrayet
filtreres før visninger og antall bygges. En inventarliste uten filtrert
resultatkilde regnes ikke lenger som bevis. Egne lister og skriver-racer
passerer i avgrensede tester; øvrige innganger og full skjerming gjenstår.

Ny rettelse 13. oktober 2026: [PRODUCTION-IMAGE-CACHE-RECIPE.md](PRODUCTION-IMAGE-CACHE-RECIPE.md)
beskriver en kontrollert produsentfeil som før rettelsen leverte B sin
cache-PNG til A. Lokale bilde-resultater må nå matche en uavhengig beregnet
cacheoppskrift eller en godkjent original. Produsent-/cachefeilene avvises
i 52 observasjoner hver; HTTP-/livsløpsmatrisen passerer 158 og faktisk
godkjent skriver med ventende sletting passerer 58. Siste bygget er rent,
rapportene er lest tilbake og testmiljøet er ryddet og stoppet.
Dette styrker filstibindingen;
cacheinnhold, mellomfiler/providers og undertekst-cache er fortsatt åpne.

Oppdatering 13. oktober 2026: [PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver installert binding av native bilde-/undertekstinput og output til
den separate fil-leseren. Originale A/B-filstibytter avvises for begge ruter
(52 observasjoner hver, faktisk Injected=1, ingen nye bundne leserkall).
Hele den avledede PNG/VTT-matrisen med HEAD/ETag/range, profilsletting og
omstart passerer 158 observasjoner. Eldre avsnitt nedenfor beskriver også
tilstanden før rettelsen. Avledet PNG/VTT passerer også faktiske skriver-
racer før og etter kontrollen (56/58 observasjoner per ressurs). Fersk
sluttkontroll bekrefter at isolerte testdata er fjernet og serveren stoppet.
Komplett cacheproveniens, øvrige innganger,
YouTube-henting og alle klientfamilier gjenstår; full skjerming er ikke bevist.

12. oktober 2026. **Ikke ferdig, ikke bevist fullt skjermet, ikke utrullet til hovedserveren i disse implementeringsrundene.** Arbeidet følger brukerens godkjenning av produksjonsimplementering etter planen, med isolert verifisering først.

## Det som finnes

- Personlige innstillinger i Emby-web: egen API-nøkkel og kanal-ID-er, serverlagring med kryptert nøkkel, revisjonskontroll, sletting og generasjoner. Lagret nøkkel returneres ikke til klienten.
- Produksjonsregistre for eier, samling, generasjon og native referanser, med varige tombstones og journal for opprettelse.
- Versjonsavgrensede native produksjonskroker for opprettelse, ti eksplisitte tjeneste-DTO-er og GetItems-listefamilien. Flere konkrete lekkasjer gjennom gamle referanser og samtidige forespørsler er påvist og rettet i isolerte tester.
- Listekontroller før query, etter native resultat og ved skriverinngang. Siste endring samordner eierens profilendringer med hele native skrivetasken. Faktisk sletting må vente ved eierens sperre når godkjent skriver allerede holder den; B kan fortsatt oppdatere sin profil.

## Det som gjenstår for den avtalte løsningen

1. Koble brukerens nøkkel og kanaler til faktisk YouTube-henting, kvoter, cacher og bakgrunnsjobber. Publisere og gjenopprette komplette personlige native biblioteker sikkert, inkludert kanalendringer og opprydding.
2. Dekke øvrige lister, direkte medier/ressurser, bilder/undertekster/HLS, rå/batch/XML/socket/DLNA, sync/offline og øvrige serverinnganger. Den eksisterende eksperimentelle fixture-skjermingen er ikke ferdig produksjonshåndheving for disse.
3. Samordne tilgang med nye native innsettinger/reparenting, register/journalendringer og bruker-/tokenrevokering. Verifisere nødvendige fail-closed-egenskaper og kompatibilitet på faktisk støttet serverbuild. De nye krokene er kontrollert mot isolert Windows Emby 4.10.1.0; dette er ikke bevis for alle Docker-/Linux-builds.
4. Verifisere faktisk YouTube-avspilling og vanlig bibliotekbruk på alle klientfamilier. Web- og lokale prøvevideotester beviser ikke hele denne kjeden.

## Siste konkrete verifisering

Avledede asset-kilder er nå faktisk kontrollert:
[NATIVE-DERIVED-ASSET-SOURCES.md](NATIVE-DERIVED-ASSET-SOURCES.md).
Native IL-inspeksjon finner ImageProcessor sitt tuple-resultat og
SubtitleConversionJob.OutputPath som koblingspunkter. Et 80x45 PNG og en
VTT med riktig A-innhold leveres fra andre stier enn originalene (51
observasjoner per løp). Dette identifiserer implementeringskravet; faktisk
request-/kilde-/cachebinding, fremmede avledede kall og deres racer gjenstår.

Faktisk Primary-PNG-/SRT-leserkilde er nå sporet, med 51 observasjoner hver:
[NATIVE-ASSET-SOURCE-PROVENANCE.md](NATIVE-ASSET-SOURCE-PROVENANCE.md).
Begge bruker native static-file-leser med delt mutabelt options-objekt og tomt
FileWriter._filePath. Videokildens separate leserbevis brukes ikke på assets.
Dette identifiserer nødvendig rettelse; det er ingen injisert asset-feil eller
påvist vanlig klientutnyttelse. Avledede bilde-/undertekst-/cachekilder må
undersøkes og støttes før kildebinding kan regnes som ferdig.

HEAD, matching ETag og én range for Primary-PNG/SRT passerer nå 158
observasjoner med aktiv profil, faktisk sletting og omstart. Egne svar har
200/304/206 med korrekte størrelser, validatorer og byteprefiks; fremmede,
anonyme og gamle slettede referanser får generisk 404 uten entityheadere.
Se [PRODUCTION-ASSET-HTTP-VARIANTS.md](PRODUCTION-ASSET-HTTP-VARIANTS.md).
Dette er normal HTTP-/livsløpskontroll; variantspesifikke skriver-racer,
faktisk avledet kilde-/cachebinding og andre varianter/ruter gjenstår.

Eierens sperre for godkjent bilde-/undertekstskriver er nå faktisk kontrollert:
58 observasjoner per rute bekrefter ventende profilsletting, B sin uavhengige
kanalendring, korrekt tillatt svar og lagret sletting etter frigjøring.
Se [PRODUCTION-ASSET-TRANSFER-LEASE.md](PRODUCTION-ASSET-TRANSFER-LEASE.md).
Dette supplerer før-kontroll-racen nedenfor. Lengre I/O-/bytegrenser og
faktisk avledet kilde-/cachebinding er fortsatt åpne krav.

Ventende faktiske FileWriter-svar for Primary-bilder og eksterne SRT-er
avvises etter fullført profilsletting: 56 observasjoner per rute,
generisk 404 uten entityheadere og nøyaktig én ny produksjons-WritesDenied.
Se [PRODUCTION-ASSET-WRITE-REVOCATION.md](PRODUCTION-ASSET-WRITE-REVOCATION.md).
Dette supplerer den tidligere ressursstatusen nedenfor; pause etter tatt
skrivesperre, andre varianter og faktisk avledet kildebinding gjenstår.

Primary-bilder og eksterne SRT-undertekster er nå kontrollert i produksjonen:
[PRODUCTION-PRIMARY-IMAGE-EXTERNAL-SUBTITLE.md](PRODUCTION-PRIMARY-IMAGE-EXTERNAL-SUBTITLE.md).
Før rettelsen leverte 28 forventede avslag private prøvefiler med HTTP 200,
også anonymt, etter profilsletting og omstart. Tretten-DTO-kontrollen avviser
nå disse rutene og fremmede kilde-ID-er i 50 observasjoner, med egne filer
bevart. Ressursspesifikke skriver-racer, øvrige varianter og kildeproveniens
gjenstår; dette er ikke full skjerming.

Ny kildebinding er dokumentert i
[PRODUCTION-STATIC-SOURCE-BINDING.md](PRODUCTION-STATIC-SOURCE-BINDING.md).
Det tidligere kontrollerte filstibyttet avvises nå for fullfil, HEAD, range
og matching ETag: ti fullførte observasjoner hver, faktisk Injected=1,
404 uten entityheadere og null nye kall til den bundne leserdelegaten.
Runtime-tracen fullfører 67 observasjoner med separate leseralternativer.
Nedlasting/PlaybackInfo-regresjonene fullfører 83/75 observasjoner.
Den tidligere uferdige kildebindingen nedenfor beskriver utgangspunktet;
øvrige beviskrav og full klientstøtte er fortsatt åpne.

[NATIVE-STATIC-FACTORY-PROVENANCE.md](NATIVE-STATIC-FACTORY-PROVENANCE.md)
identifiserer faktisk filfabrikk: FileWriter har tomt filstifelt og leseren
beholder et mutabelt filalternativ-objekt. En kontrollert intern A/B-mismatch
leverte B sin SHA-korrekte prøvefil til A til tross for A sine uendrede gyldige
video-/kilde-ID-er. Dette er feilinnsprøyting, ikke et påvist vanlig klientangrep.
Kildebindingen er derfor fortsatt uferdig. Runtime-tracen fullfører 67
observasjoner; mismatch-diagnostikken fullfører åtte med IsolationPass=false.

[PRODUCTION-STATIC-VIDEO-STREAMS.md](PRODUCTION-STATIC-VIDEO-STREAMS.md) påviser
og retter faktisk avspilling av fremmed prøvevideo gjennom GetVideoStream.
Statisk fullfil, HEAD, range og matching ETag passerer 76 observasjoner hver,
inkludert fremmed konto/kilde-ID, manglende kilde-ID, ventende svar ved
profilsletting og B sin tillatte tilgang etter omstart. Private dynamiske,
live og transkodede GetVideoStream-kall er foreløpig avvist; disse må få
ferdig provenienskontroll for å oppnå avtalt klientstøtte. Andre medieruter
og den fulle YouTube-/klientkjeden gjenstår.

[PRODUCTION-DOWNLOAD-VARIANTS.md](PRODUCTION-DOWNLOAD-VARIANTS.md) dekker én
rangevariant og matching ETag med faktisk ventende native svar og profilsletting:
83 observasjoner hver, med B sine tillatte 206/304 bevart. HEAD er native
ustøttet på GetDownload; 78 observasjoner kontrollerer 404 uten privat
filinformasjon på tvers av kontoer, sletting og omstart. Andre HTTP-varianter,
serverinnganger og den fulle klientkjeden gjenstår.

[PRODUCTION-DOWNLOAD-REVOCATION.md](PRODUCTION-DOWNLOAD-REVOCATION.md)
dekker faktisk GetDownload ved profilsletting. Den skjerpede testen passerer
76 observasjoner: 404 uten privat kropp eller filheadere, lukket kildehåndtak
og B sine tillatte svar bevart. Andre medieruter gjenstår; den nyere
variantkontrollen er beskrevet over. Dette er ikke full skjerming.

[PRODUCTION-REFERENCE-RESPONSE-REVOCATION.md](PRODUCTION-REFERENCE-RESPONSE-REVOCATION.md)
dekker den siste direkte metadata-lekkasjen ved profilsletting. Metadata-racen
passerer 60 observasjoner og siste GET PlaybackInfo-regresjon 75, med B sine tillatte
GET/POST PlaybackInfo-svar beholdt. Faktisk medieutlevering og alle øvrige
innganger er fortsatt ikke ferdig dekket.

[PRODUCTION-LIST-TRANSFER-LEASE.md](PRODUCTION-LIST-TRANSFER-LEASE.md) beskriver den siste påviste lekkasjen, produksjonsendringen og dens grenser. 44 native observasjoner bekrefter ventende faktisk profilsletting og B sin uavhengige oppdatering. 186 komponentkontroller passerer. Skriverinngangsregresjonen passerer fortsatt med 42 observasjoner og 404 for en forespørsel holdt før skrivekontrollen mens sletting fullfører.

Testantall er avgrenset evidens, ikke et mål på hvor nær en universell garanti er. Den fullstendige planen og beviskravene står i [PLAN-FULL-SKJERMING.md](PLAN-FULL-SKJERMING.md) og [PROOF-AUDIT.md](PROOF-AUDIT.md).

Siste native livsløpsregresjon fullførte 235 observasjoner med omstarter verifisert. Isolert testmiljø er ryddet og prosessen faktisk stoppet, lest tilbake i `bin/production-item-list-transfer-lease-cleanup.json`.

Etter GetDownload-headerrettelsen passerer PlaybackInfo-regresjonen 75,
listeskrivesperren 44 og komponentkontrollene 186. Seneste opprydding og
endelig stoppet prosess er lest tilbake i `bin/production-download-cleanup.json`.

Etter utvidelsen med EmptyHttpResult passerer full nedlasting 76, PlaybackInfo
75 og listeskrivesperren 44. Endelig opprydding og stoppet prosess er lest
tilbake i `bin/production-download-variants-cleanup.json`.

Etter statisk GetVideoStream-utvidelse passerer matching-ETag-nedlasting 83,
PlaybackInfo 75, listeskrivesperre 44 og komponenter 186. Opprydding og faktisk
stoppet prosess er lest tilbake i `bin/production-static-video-cleanup.json`.
Separat proveniens fra godkjent kandidat til faktisk skriverkilde ved kilde-/
cacheendring er fortsatt et gjenværende krav, sammen med dynamiske skrivere.
