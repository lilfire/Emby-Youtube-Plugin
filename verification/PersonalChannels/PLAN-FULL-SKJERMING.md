# Plan for å kunne bevise full skjerming

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
supplerer direkte metadata-navn og ID-er, med positiv offentlig kontroll.
Referansefamilien dekker nå 15 konkrete DTO-er. Gjenstående krav nedenfor,
inklusive metadataressurser, delte felt, revokering og klientkjede, består.

Oppdatering 2026-10-13: [PRODUCTION-METADATA-LISTS.md](PRODUCTION-METADATA-LISTS.md)
supplerer vanlige native metadataoversikter. Åtte konkrete liste-DTO-er
er scoped, med særskilt kildebinding for den globale merkelappindeksen.
Direkte metadatareferanser og resten av de fulle kravene gjenstår.

Oppdatering 2026-10-13: [PRODUCTION-ITEM-COUNTS.md](PRODUCTION-ITEM-COUNTS.md)
supplerer bibliotekoppdagelse med faktisk native telling av filmer og
private bibliotekreferanser. Fem konkrete DTO-er er nå scoped. Den fulle
planens gjenstående ruter, klientkjede og øvrige krav gjelder fortsatt.

Oppdatering 2026-10-13: [PRODUCTION-SUGGESTIONS.md](PRODUCTION-SUGGESTIONS.md)
supplerer discovery med faktisk forslag-rute, egen positiv kontroll og
begge skrivergrenser ved profilsletting. Listekontrollen dekker nå fire
konkrete DTO-er. Resten av kravene nedenfor gjelder fortsatt.

Oppdatering 2026-10-13: [PRODUCTION-DISCOVERY-LISTS.md](PRODUCTION-DISCOVERY-LISTS.md)
følger opp vanlige bibliotekoversikter/nyeste med direkte API-evidens.
Tre DTO-er er scoped, faktisk mappe-input filtreres før native view-bygging,
og ingen inventarliste alene godkjennes som et resultatkildebevis.
Andre innganger og den øvrige avtalte løsningen er fortsatt uferdige.

Ny rettelse 2026-10-13: [PRODUCTION-IMAGE-CACHE-RECIPE.md](PRODUCTION-IMAGE-CACHE-RECIPE.md)
følger opp det påviste hullet i ubetinget registrering av native bilde-output.
Uavhengig lokal cacheoppskrift er implementert; komplett cacheinnhold,
mellomfiler/providers, undertekst-cache og resten av løsningen gjenstår.

Oppdatering 2026-10-13: [PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver produksjonsbinding og beståtte originale asset-filstibytter.
Hele avledet PNG/VTT-matrise med HTTP-varianter, sletting og omstart passerer
158 observasjoner. Tidligere beskrivelser av manglende asset-leserbinding
nedenfor er historiske. Komplett cacheproveniens og resten av løsningen gjenstår.

Status 2026-10-12: **ikke oppnådd**. Dette er en konkret plan og gjennomgang av kildekode og testresultater, ikke en godkjenning av full skjerming. Etter at planen ble skrevet, svarte brukeren «Tillat implementering etter planen», med isolert verifisering først. Produksjonsimplementering er dermed autorisert; de gjenværende beviskravene gjelder fortsatt.

## Hva som skal bevises

Hver autentisert Emby-konto skal kunne bruke egen YouTube-nøkkel og egne kanalvalg. Samlingen skal fungere som vanlige Emby-biblioteker i alle klienttyper. En annen vanlig konto skal ikke oppdage, lese, spille av, laste ned eller endre samlingen gjennom serveren, også med direkte eller gamle referanser, delte enheter, samtidige kall og omstart. Håndhevingen skal ligge i pluginen uten en ekstern tilgangsport eller avhengighet av Docker-nettverket.

Allerede utleverte lokale kopier på samme enhet er utenfor brukerens avklarte servergaranti. Bibliotekets navn, kanalvalg og metadata er derimot private serverdata selv om selve YouTube-videoen er offentlig. Sikkerhetsgrensen her gjelder vanlige Emby-kontoer, ikke en administrator som kontrollerer serverens filer/prosess.

## Faktisk nåtilstand

Oppdatering 2026-10-12: Native avledet bildekilde kommer fra ProcessImage sitt
tuple-resultat, og undertekstkjeden bruker konverteringsjobbens OutputPath.
Faktisk 80x45 PNG/VTT gir korrekte A-bytes med forskjellige stier fra
originalfilene (51 observasjoner hver). Se
[NATIVE-DERIVED-ASSET-SOURCES.md](NATIVE-DERIVED-ASSET-SOURCES.md).
Bindingen må følge kilde/transformasjon/resultat til filfabrikk og leser,
med cachetreff og originalsnarveier bevart. Dette er ikke ferdig implementert.

Oppdatering 2026-10-12: Faktisk original Primary-PNG-/SRT-fabrikk er sporet
(51 observasjoner hver). Begge bruker samme native mutabelt options-objekt
som leserdelegaten; FileWriter._filePath er tom. Se
[NATIVE-ASSET-SOURCE-PROVENANCE.md](NATIVE-ASSET-SOURCE-PROVENANCE.md).
Native originalkilder er identifisert, men leser-/cachebevis må implementeres
også for avledede varianter slik at vanlige klienter fortsatt fungerer.

Oppdatering 2026-10-12: Native HEAD/ETag/én range for private Primary-PNG/SRT
er kontrollert med egne positive 200/304/206-svar og generiske avslag for
fremmede/anonyme/slettede referanser før/etter omstart (158 observasjoner).
Se [PRODUCTION-ASSET-HTTP-VARIANTS.md](PRODUCTION-ASSET-HTTP-VARIANTS.md).
Variantspesifikke skriver-racer og avledet kilde/cache, andre HTTP-/medieruter
og full klient-/YouTube-kjede er fortsatt åpne krav.

Oppdatering 2026-10-12: Bilde-/SRT-FileWriter pausert etter produksjonskontroll
holder nå faktisk eierens sperre. A-sletting venter med Draft-readback; B kan
lagre kanalvalg; frigjøring gir korrekt eget svar før sletting lagres. 58
observasjoner per rute. Se
[PRODUCTION-ASSET-TRANSFER-LEASE.md](PRODUCTION-ASSET-TRANSFER-LEASE.md).
Dette supplerer før-kontroll-racen nedenfor; senere I/O-/bytegrenser, lange
overføringer og faktisk avledet kildebinding gjenstår.

Oppdatering 2026-10-12: De to nye medieressursenes faktiske FileWriter er nå
pausert før produksjonskontrollen mens A-profilsletting fullfører. Begge
venter og avvises så med generisk 404 uten entityheadere, fra faktisk
produksjonskontroll. 56 observasjoner per rute. Se
[PRODUCTION-ASSET-WRITE-REVOCATION.md](PRODUCTION-ASSET-WRITE-REVOCATION.md).
Dette er ikke sletting etter tatt skrivesperre, sendt innhold eller alle
HTTP-/kildevarianter. De fullstendige kravene består.

Oppdatering 2026-10-12: Faktiske private Primary-PNG/SRT-svar var tilgjengelige
for andre kontoer/anonymt og etter sletting. To nye produksjons-DTO-er avviser
nå dette, med aktuelle eier-/kandidatkontroller og felles skriverkontroll.
50 observasjoner inkluderer fremmede/manglende kilde-ID-er, lagret sletting
og omstart. Se [PRODUCTION-PRIMARY-IMAGE-EXTERNAL-SUBTITLE.md](PRODUCTION-PRIMARY-IMAGE-EXTERNAL-SUBTITLE.md).
Ressursspesifikke racer, andre varianter og faktiske avledede kilder gjenstår.

Oppdatering 2026-10-12: Den prøvde statiske filstifeilen nedenfor er nå rettet
med separate metadata-/leseralternativer, request-/resultatbevis og kontroller
ved native lesing/skriving. Fire mismatch-varianter fullfører ti observasjoner
hver med faktisk mutasjon og 404 uten entityheadere eller nye leserkall.
Se [PRODUCTION-STATIC-SOURCE-BINDING.md](PRODUCTION-STATIC-SOURCE-BINDING.md).
De bredere kilde-, rute-, revokerings- og klientkravene er fortsatt åpne.

Faktisk kildefabrikk 2026-10-12: Runtime-trace viser at FileWriter._filePath
er tom, mens native factory-leseren beholder et mutabelt filalternativ-objekt.
Kontrollert intern mismatch etter closure-opprettelse leverer B sin faktiske
prøvefil til A med uendrede A-video-/kilde-ID-er. Dette er feilinnsprøyting,
ikke et påvist vanlig klientangrep. Kildebinding før lesing/cache og ved
skriving er fortsatt uferdig; konkrete rettelseskrav står i
[NATIVE-STATIC-FACTORY-PROVENANCE.md](NATIVE-STATIC-FACTORY-PROVENANCE.md).

Statisk GetVideoStream 2026-10-12: Fremmede kontoer kunne faktisk hente hele
prøvevideoen uten den nye DTO-kontrollen. Den ellevte produksjons-DTO-en og
native kandidat-/eierkontroll retter dette for statiske kilder. Full/HEAD/range/
ETag passerer 76 observasjoner hver, med ventende svar ved sletting og omstart.
Se [PRODUCTION-STATIC-VIDEO-STREAMS.md](PRODUCTION-STATIC-VIDEO-STREAMS.md).
Private dynamiske/live/transkodede kall er foreløpig avvist og må implementeres
for avtalt klientstøtte; øvrige innganger og ekte YouTube-kjeden gjenstår.

GetDownload-varianter 2026-10-12: native EmptyHttpResult-skriveren for 304
har nå samme produksjonskontroll som StreamWriter/FileWriter. En rangevariant
og matching ETag passerer 83 observasjoner hver. Native HEAD er ustøttet på
denne ruten; 78 observasjoner bekrefter 404 uten privat filinformasjon. Se
[PRODUCTION-DOWNLOAD-VARIANTS.md](PRODUCTION-DOWNLOAD-VARIANTS.md). Andre
HTTP-varianter og medieinnganger, faktisk YouTube og klientdekning gjenstår.

GetDownload 2026-10-12: Faktisk FileWriter kontrolleres nå ved skriverinngang.
Påløpt filinnhold og private headere er avvist etter fullført profilsletting i
76 observasjoner. Se [PRODUCTION-DOWNLOAD-REVOCATION.md](PRODUCTION-DOWNLOAD-REVOCATION.md).
Den nyere variantkontrollen står over; øvrige medieruter og støttede serverbuilds gjenstår.
Denne nye evidensen supplerer den tidligere metadataavgrensningen nedenfor.

Direkte svar 2026-10-12: GetItem og GET/POST PlaybackInfo knyttes nå til
autentisert eier og samme kontrollerte skriver/sperre som listene. Påvist
metadata-race får 404 i 60 observasjoner; GET PlaybackInfo-race passerer 74.
Se [PRODUCTION-REFERENCE-RESPONSE-REVOCATION.md](PRODUCTION-REFERENCE-RESPONSE-REVOCATION.md).
Dette er ikke bevis for faktisk medie-/Download-utlevering eller øvrige ruter.

Pågående listerespons 2026-10-12: Eierens Save/Delete samordnes nå med hele
native GetItems-skrivetasken, slik at sletting venter når godkjent skriving
allerede har startet ved sperren. 44 native observasjoner og 186
komponentkontroller passerer. Se
[PRODUCTION-LIST-TRANSFER-LEASE.md](PRODUCTION-LIST-TRANSFER-LEASE.md).
Dette dekker ikke øvrige serverruter, native mutasjoner eller klientkjeden.

Skriverinngang 2026-10-12: Produksjonen kontrollerer nå også registrerte sperrer
ved faktisk native WriteToAsync. Samme påviste lekkasje etter resultatkontroll
gir 404 i 42 native observasjoner. Se
[PRODUCTION-LIST-WRITE-REVOCATION.md](PRODUCTION-LIST-WRITE-REVOCATION.md).
Revokering under senere byteutlevering og de øvrige kravene gjenstår.

Resultatkontroll 2026-10-12: Et ferdig native listeresultat kunne lekke etter
fullført profilsletting. Ny kontroll før HTTP-kjeden avviser samme resultat
med 404. Se [PRODUCTION-LIST-RESULT-REVOCATION.md](PRODUCTION-LIST-RESULT-REVOCATION.md).
178 komponentkontroller og 42 native resultat-race-observasjoner passerer;
kontroll under senere byteutlevering og øvrige beviskrav gjenstår.

`PRODUCTION-LIST-INVENTORY-REVOCATION.md` beskriver et påvist og korrigert
vindu mellom listeinventar og senere query ved profilsletting. Registrerte
private sperrer oppfriskes uten native DB-scan før query. 41 native
observasjoner og 169 komponentkontroller passerer; revokering senere i
query/utlevering og nye uregistrerte elementer er fortsatt åpne krav.

`PRODUCTION-ITEM-LIST-GATE.md` beskriver GetItems-familiens produksjonskrok
som ekskluderer private native ID-er før telling/paging. 37 isolerte
observasjoner passerer uten fixture-skjerming og med brede native rettigheter.
Samtidige endringer etter snapshot og øvrige listefamilier må fortsatt løses.

`PRODUCTION-SERVICE-REFERENCE-GATE.md` beskriver ti native DTO-er med en
oppstartsinstallert produksjonsprefix før serviceutføring. 53 observasjoner
passerer med fixture-håndheving avslått. Et runtime-inventar har 430 native
rute-DTO-er; de øvrige inngangene og asynkron revokering må fortsatt dekkes.

`PRODUCTION-NATIVE-ACCESS-RESOLUTION.md` beskriver produksjonens nye oppløsning
av faktisk bruker, native element, foreldre og kildestier samt varig avslag
på manglende kjente referanser. Den native verifiseringen er utvidet til
235 observasjoner og komponentene til 160 kontroller. Dette installerer
ennå ingen universell produksjonsgrense.

`PRODUCTION-NATIVE-CREATION-HOOK.md` beskriver produksjonens nye
oppstartsinstallerte pre-insert-krok med eksakt kontroll av native
metodekropper. 37 opprettingsobservasjoner og 16 observasjoner ved faktisk
prefixbortfall/omstart passerer. Det installerer ennå ingen universell
tilgangsgrense eller ferdig personlig publiserer.

`PRODUCTION-NATIVE-CREATION-CONTEXT.md` beskriver den nye interne
opprettingskonteksten fra faktisk profilsnapshot. GUID-reservasjon bruker
denne konteksten i den isolerte native kjøringen, uten navn som eierautoritet.
150 komponentkontroller og 35 native observasjoner passerer. Installasjon av
produksjonskroker, en ferdig publiserer og gjenoppretting gjenstår.

Seneste opprettingskontroll: `NATIVE-CREATION-PRE-SOURCE-WINDOW.md` dokumenterer
et faktisk metadatahull mellom native CreateItem og lagring av kildestier.
Produksjonsjournalen har nå en varig GUID-reservasjon som i en isolert
fixture-kobling nekter tilgang i dette vinduet. Den beskyttede kjøringen har
35 observasjoner og komponentene 130 beståtte kontroller. Betrodd
produksjonskontekst for oppretting og universell tilgangshåndheving gjenstår.

| Del | Kontrollert kilde/evidens | Konsekvens |
|---|---|---|
| Brukerinnstillinger | Personlig produksjonslager, autentiserte profilruter og en brukerside er implementert og isolert verifisert; se `PRODUCTION-PROFILE-STORE.md`, `PRODUCTION-PROFILE-SERVICE.md` og `PRODUCTION-PROFILE-UI.md` | Egne nøkler og kanalvalg kan lagres. Produksjonens eksisterende YouTube-kall og medier bruker fremdeles globalt oppsett; binding til personlig publisering gjenstår. |
| Cache og kvote | `YouTubeApi.cs`: statiske URL-baserte cache/in-flight-tabeller. `QuotaTracker.cs`: globale tellere | Eierens private tilstand og nøkkelrevisjon må føres gjennom kall og bakgrunnsarbeid. |
| Personlige profiler | `PersonalYouTubeStore.cs` og `PersonalYouTubeService.cs` er produksjonskode; `PersonalProfiles.cs` er en eldre testprototype | Produksjonsprofilens eier og generasjon er verifisert isolert, men ingen produksjonsbinding til bibliotekene er implementert. |
| Native servertilgang | `PrivacyGuard.cs` bruker interne Harmony-kroker og syntetiske navn for identifisering | Ingen produksjonsklar, dokumentert universell tilgangsgrense. Native bibliotekpolicy alene har målte moteksempler. |
| Varig medlemskap | `NativeReferenceLedger.cs` indekserer på native rot-GUID og slår referanser sammen på tvers av livsløp | Gjenbrukt foreldremappe-GUID ga legitime B-metadataavslag. |
| Avledede filer | Konverteringsracen fjernet native jobb/element, men utdatafilen bestod på disk | Varig filproveniens og egen opprydding trengs. Native sletting er ikke et slikt bevis. |
| YouTube-avspilling | `YouTubeChannel.Mapping.cs`: watch-URL, ikke opening/closing, ingen servertranskoding. Runtime-normalisering slo av alle annonserte spillemåter for prøvde native Theater-headere | Lokale MP4-/HLS-/Sync-tester kan ikke bevise faktisk YouTube-avspilling i alle klienttyper. |

## Arbeidspakke 1: Samling og livsløp

Innfør en uavhengig, varig `CollectionId`, stabil `OwnerUserGuid` og en eksplisitt `GenerationId`. Eier hentes fra faktisk autentisert konto ved oppretting; navn og innsendt UserId gir ingen autoritet. Gjenoppretting etter sletting oppretter en ny generasjon. Den gamle skal aldri gjenåpnes ved gjenbruk av konto- eller biblioteksnavn.

Hver generasjon får en ny intern mappe. Stien og den interne identiteten endres ikke når brukeren endrer visningsnavnet. Dette unngikk den konkrete mappe-GUID-kollisjonen i den utførte testen, men må også verifiseres sammen med produksjonens indeks-/mediemodell. En vanlig samling kan vise samme YouTube-kanal som en annen konto uten å dele privat Emby-identitet.

Native rot-, mappe- og video-ID/GUID bindes eksplisitt til samling/generasjon. Gamle bindinger bevares som avsluttede referanser. En kollisjon mellom gamle og nye native identiteter må behandles som en konflikt som må løses før publisering, ikke ved å gi den gamle identiteten til den nye eieren eller oppheve alle historiske sperrer.

Et varig register bør også holde nøkkelrevisjon og tilstand: opprettet, aktiv, sperret, under sletting eller slettet. En oppdatering må lagre samling, bindinger og livsløp konsistent før en ny samling blir tilgjengelig. Lagringsfeil skal ikke føre til at ukjent privat innhold blir behandlet som offentlig. Manglende bruker eller ødelagt samling skal sperre denne samlingen uten å ødelegge B sitt fungerende bibliotek. Dette siste er et eksplisitt positivt krav, ikke bare en 404-kontroll.

Beviskrav: navneendring, samme navn/kanal hos A/B, slettet og gjenopprettet konto med ny GUID, slettet og gjenopprettet samling, flytting, kolliderende native referanser, avbrutt lagring og omstart. Kontroller både korrekt eget innhold og nektet fremmed innhold.

## Arbeidspakke 2: Personlig nøkkel, kanalvalg og arbeid

En egen profilrute bruker autentiseringskonteksten som eier. Vanlig GET returnerer nøkkelstatus og egne kanalvalg, ikke lagret nøkkel. Lagret nøkkel beskyttes separat per eier, med eier/samling som del av autentiseringen av krypterte data. Serverhemmeligheten må håndteres separat fra den krypterte profilen.

Hvert API-kall og hver bakgrunnsjobb får et eksplisitt snapshot av eier, samling, generasjon og nøkkelrevisjon. Jobben må kontrollere at dette fremdeles gjelder før den publiserer resultater. Et sent svar fra en slettet generasjon får ikke havne i en ny generasjon eller hos en annen eier. API-nøkler skal ikke komme i klientrespons, logg eller rapport.

Cache/in-flight-arbeid for private valg må bruke samme identitet. Eventuell deling av offentlig YouTube-metadata må skje uten å dele privat kanalmedlemskap, jobber, nøkkelstatus eller brukerhistorikk. Nøkkelens Google-prosjekt og Emby-eieren er forskjellige begreper; to brukere med samme nøkkel skal ikke automatisk bli samme private eier.

Beviskrav: to markørnøkler, samme nøkkel hos to eiere, samtidig rotasjon, sletting og sent svar, API-feil, cachetreff/miss og omstart. Testene må følge den faktiske produksjonskallkjeden og produksjonens bakgrunnsjobber, ikke bare PreparedRequest-proben.

## Arbeidspakke 3: Tilgang før lesing, utlevering og mutasjon

Tilgangsavgjørelsen bruker faktisk autentisert konto, den varige referansebindingen og samlingens tilstand. Det må gjelde både direkte oppslag og lister, counts/paging, metadata, bilder, undertekster, kapitler, PlaybackInfo, strømming, HLS/segmenter, nedlasting, Sync, meldinger og endringer i tilstand.

Håndhev før åpning av kilde, oppretting av jobb eller endring av tilstand. Å returnere 404 etter en fremmed kilde allerede er åpnet er utilstrekkelig; tidligere test fant nettopp slik bieffekt. Autoriteten må føres eksplisitt gjennom asynkront arbeid og vurderes ved faktisk utlevering. DeviceId, TargetId, UserId fra forespørsel og en kjent tokenstreng gir ikke selv eierskap.

Strøm-/OpenToken-bindinger trenger kilde, samling/generasjon og faktisk eier, ikke bare token → bruker. MediaSourceId må høre til den etterspurte kilden. Bakgrunnsarbeid og avledede jobber trenger samme binding. En delt enhet skal ikke gi felles eierskap. Gamle konto-/samlingreferanser skal nektes etter omstart.

For den native delen kreves en oversikt over **alle** innganger som kan lese/endre privat data, og at hver inngang må passere avgjørelsen. Rutetester understøtter dette, men erstatter ikke gjennomgangen. [Den dokumenterte IHttpServer-kontrakten](https://dev.emby.media/reference/pluginapi/MediaBrowser.Controller.Net.IHttpServer.html) gir ikke i seg selv den sentrale tilgangskroken prototypen bruker. Hvis interne kroker videreføres, må faktisk serverbuild, metodeform og nødvendige kallstier verifiseres ved oppstart. En uverifisert serveroppdatering kan ikke uten videre regnes som støttet. Å slå av beskyttelsen på en allerede indeksert privat samling er ikke en akseptabel fallback.

Beviskrav: full inngangsoversikt, autentiseringsformer, direkte/gamle/ukjente referanser, query/body-forfalskning, metadataformater, sideeffekter og tilstandsavtrykk, delte enheter, samtidig tilgang og faktisk omstart. Finitte beståtte HTTP-kall alene er ikke bevis for den universelle avgjørelsen.

## Arbeidspakke 4: Avledede filer og gjenoppretting

Opprett en varig fil-/jobbbinding med eier, samling/generasjon, kilde og eksakt intern lagringsplass før en avledet fil kan utleveres. Filens binding må kunne gjenfinnes etter at native GetJob/GetJobItem eller kilden er borte. Sletting eller kansellering gjør generasjonen utilgjengelig først; senere ferdige arbeider må ikke kunne reaktivere den.

Fysisk opprydding bruker de registrerte filene, validerer deres mål og håndterer filer som er i bruk. Ved omstart må systemet kunne finne ufullførte slettinger og foreldreløse filer. Filbaner fra klienten er ikke oppryddingsautoritet. Feilet sletting skal ikke gi fremmed utlevering, og B sine filer skal bevares.

Beviskrav: faktisk Original og konverterte utdata, ffmpeg-kjøring og Ready-lagring, fullførings-/slettingsraces, fil i bruk, avbrutt prosess, omstart, manglende native jobb og fysisk opprydding. Mål filhash/bytes og faktisk native tilstand separat. De utførte konverterings-/Ready-racene er regresjonsgrunnlag, ikke ferdig produksjonsbevis.

## Arbeidspakke 5: Faktisk YouTube og klienter

Avspillingsmodellen må avklares og verifiseres før «alle klienttyper» kan godkjennes. [YouTube videos-ressursen](https://developers.google.com/youtube/v3/docs/videos) dokumenterer metadata og player/embedHtml. [YouTube-spillerens parametere](https://developers.google.com/youtube/player_parameters) gjelder den innebygde spilleren. Slutningen fra disse kontraktene er at en Data API-nøkkel alene ikke dokumenterer en rå mediestrøm som Emby-klienter kan spille eller servertranskode. Ingen slik kilde er verifisert i produksjonspluginen.

Det trengs en faktisk fungerende YouTube-mediekjede for de aktuelle native klientene. Den må beholde vanlige biblioteker og serverens eierkontroll. En egen webside, ekstern tilgangsport eller lokal prøvevideo oppfyller ikke dette kravet. Inntil kjeden finnes, kan kompatibilitet og full oppnåelse ikke erklæres bevist.

For hver klientfamilie som skal omfattes, registrer app/build/plattform og observer de faktiske forespørslene ved eget bibliotek, avspilling, brukerbytte, gamle lenker og servernedlasting der appen støtter det. Knytt klientens ruter til den gjennomgåtte servergrensen. Familier uten positiv faktisk kontroll skal stå som uverifisert, og ingen garanti kan gis for vilkårlige fremtidige apper/versjoner.

## Rekkefølge og leveranser

1. Avklar en fungerende native YouTube-mediekjede og den serverkontrakten håndhevingen kan bygge på. Begge må være konkrete før hele funksjonen kan loves.
2. Implementer varig samling/generasjon og personlige profiler, med trygg oppretting/sletting og isolerte API-jobber.
3. Knytt alle native og avledede referanser til modellen og håndhev tilgang gjennom de gjennomgåtte serverinngangene.
4. Implementer gjenoppretting/opprydding og verifiser de observerte identitetskollisjonene og avledede filene.
5. Lag brukermenyen mot egne profilruter og gjennomfør faktiske klientkontroller sammen med produksjonskallkjeden.
6. Gjennomfør en krav-for-krav-revisjon av produksjonsimplementasjon, serverbuild og klientresultater. Marker full skjerming oppnådd bare når alle krav har direkte, dekkende evidens.

Arbeidspakkene er nødvendige endringer og bevis. Dagens testprototyper gir nyttig regresjonsgrunnlag, men kan ikke erstatte en samlet produksjonsimplementasjon. Brukeren har nå autorisert produksjonskode etter planen. Den første implementerte byggesteinen er [PersonalYouTubeStore.cs](../../PersonalYouTubeStore.cs), isolert verifisert i [PRODUCTION-PROFILE-STORE.md](PRODUCTION-PROFILE-STORE.md); den publiserer eller autoriserer ennå ingen native medier.
