# Binding av lokal bilde-cache til autorisert kilde

13. oktober 2026. Isolert Windows Emby 4.10.1.0 med lokale syntetiske A/B-
biblioteker. Vanlige kontoer har brede native folder-rettigheter, produksjons-
profiler og native bindinger. Eksperimentell guard er deaktivert og lest
tilbake. **Full skjerming er fortsatt ikke bevist.**

## Påvist feil før rettelsen

Tidligere asset-binding kontrollerte input, men registrerte enhver filsti
returnert fra den pinned native bildeprodusenten som godkjent output.
Den nye fixture-proben fanger først B sin faktiske egne 80x45 PNG fra en
autentisert B-forespørsel. Deretter bytter den A sitt ProcessImage-resultat
til dette allerede observerte B-resultatet, før produksjons-postfixen.
Faktisk syntetisk native ID, Primary-type/index, input og aktør kontrolleres;
ingen vilkårlig filsti eller vanlig bruker kan armere admin-proben.

Diagnostikken i
`bin/derived-lifecycle-bound-production-media-assets-image-producer-output-diagnostic-results.json`
har Completed=true, 52 observasjoner og **én IsolationPass=false**:
Injected=1, HTTP 200, 197 byte med dekodet rød B-farge, to entityheadere og
IoCallsDelta=1. Dette beviser den kontrollerte interne resultatfeilen,
ikke at en vanlig klient kan injisere native produsentresultater.

De første probe-løpene byttet resultat etter at produksjonen hadde registrert
A sin fil, og ble derfor avvist. De var ikke bevis for den ønskede
produsentgrensen. Proben bruker nå eksplisitt Harmony-owner-rekkefølge
`before = emby.youtubeplugin.personal-asset-source` og priority 1000.
Native Task-type er ikke et sikkert bevis for wrapper-rekkefølge, spesielt
for synkront fullførte cachetreff; feltet i rapporten skal ikke tolkes slik.
Diagnostikken ovenfor er det bevarte løpet med faktisk fremmed resultat.

## Produksjonsrettelsen

`PersonalYouTubeAssetSourceGate` registrerer en fersk valideringsfunksjon for
den faktisk autoriserte native bildekilden. Den beregner den forventede
cachefilstien uavhengig ved GetCacheFilePath og sammenligner det native
resultatet med denne stien før det registreres som output-kandidat.
ProcessImage-resultatet må deretter være en godkjent originalsti eller en
slik registrert kandidat; det er ikke lenger nok at en native produsent
returnerte en hvilken som helst sti.

Oppskriften følger inspisert native IL: kilde, requestedWidth/Height,
requestedMaxWidth/Height, quality, UTC-endringsticks, format, nullable blur,
bakgrunn og foreground. Runtime-kryptoprovider bruker UTF-16LE, MD5 og Guid-
formatering. BCL-koden beregner samme navn; første tegn bestemmer
underkatalogen under native resized-image-cache. Dette gjenskaper native
oppslag, og endrer ikke navnekonvensjonen eller cachemappen.

Entry-/worker-kontrakten for ProcessImage er fortsatt pinned. Nå kontrolleres
også GetCacheFilePath og GetResizedImageCachePath sine IL-hasher, parametre
og returtyper, og tilstedeværelsen av begge nye produksjonskroker.
Snapshot har ImageRecipeVersion=1 bare når hele installasjonen er verifisert.
Cachekandidaten beholder fersk kilde-/tilgangsvalidering og kontroll av
cache-root; de eksisterende separate fil-leser- og skriverbevisene brukes
videre. Counteren ImageRecipes teller faktisk registrerte kandidater.
Den registrerte filstien beholder også kandidatens ferske oppskrifts-/root-
kontroll som callback ved fabrikk, leser og skriver; det er ikke bare en
engangskontroll før tjenesten returnerer.

## Konkret verifisering

`Test-ProductionMediaAssets.ps1 -DerivedAssets -ProbeProducerOutput
-RequireIsolation` fullfører 52 observasjoner i
`bin/derived-lifecycle-recipe-bound-production-media-assets-image-producer-output-protected-results.json`.
Den faktiske injeksjonen nås én gang og gir HTTP 404 med 15-byte
`Item not found.`, ingen entityheadere, IoCallsDelta=0 og ingen dekodet B-PNG.
B sin egen positive kontroll gir HTTP 200 og øker ImageRecipes med én;
ImageRecipeVersion=1 og fortsatt installert produksjonskontroll er påkrevd.
Dette unngår at en probe som aldri når den nye kontrollen regnes som bestått.

`-DerivedAssets -ProbeProducerOutput -ProbeCachePath -RequireIsolation`
fullfører 52 observasjoner i
`bin/derived-lifecycle-recipe-bound-production-media-assets-image-cache-output-protected-results.json`.
Her byttes resultatet fra GetCacheFilePath til B sin observerte cachefil,
før produksjons-postfixen. Samme faktiske positive B-kontroll kreves. Feilen
nås én gang og gir samme generiske avslag uten nye bundne leserkall.
ProducerDeniedDelta er to i dette løpet fordi både cachekontrollen og den
omsluttende produsentoppgaven avviser feilen; dette er ikke to injeksjoner.

`-DerivedAssets -HttpVariants -RequireIsolation` fullfører 158 observasjoner
i `bin/derived-lifecycle-recipe-bound-production-media-assets-http-variants-results.json`.
Hele matrisen bruker faktisk dekodet 80x45 PNG og WEBVTT, med begge eiere,
fremmede/anonyme, blandede kilde-ID-er, profilsletting og omstart. Egne
HEAD/ETag/range-kontroller bruker de faktiske filenes lengder, validatorer og
byteprefiks; avslag må ha generisk kropp uten entityheadere.

`-DerivedAssets -WriterRace Image -AfterWriteCheckRace -RequireIsolation`
fullfører 58 observasjoner i
`bin/derived-lifecycle-recipe-bound-production-media-assets-image-write-lease-results.json`.
Faktisk godkjent avledet FileWriter pauses etter produksjonskontrollen;
sletting når eierens sperre og venter, B sin profiloppdatering fungerer,
korrekt 197-byte A-PNG leveres og sletting lagres etter frigjøring. Løpet
verifiserer egen tillatt levering etter at tjenestens konstruksjonsscope er
avsluttet, med den nye output-callbacken fortsatt bundet til filen.

Rapportene er lest tilbake: Completed=true og ingen feilede IsolationPass.
Prosessene fullfører med exit 0. `recipe-` bevarer tidligere rapporter før
rettelsen. PlaybackInfo/skriver-regresjonen fullførte også 75 observasjoner
før den siste additive endringen som beholder kandidatens callback til
leser/skriver. Den regresjonen alene beviser derfor ikke siste asset-callback.

Native inspeksjon i `bin/native-asset-processing-inspection.json` leser nå
57 metodekropper, inkludert cache-root og kryptoprovider. Truncated=false
gjelder den avgrensede køen, ikke alle eksterne kall. Kryptoproviderens
GetMD5-IL har hash 759B80A39D4B1C41D6619F8C46DE356BEFE3971AA5A841E432A9FADF9CF7F233;
cache-root-getter har hash 7CD0EDE19C22395EF13DBA3A76A7F757A44EF8CD1E0FE21A8BC28BF5A0765F4D.
Inspeksjon og produksjonskontrakt skal ikke forveksles: uavhengig BCL-beregning
bruker den inspiserte UTF-16LE-oppskriften; native output sammenlignes mot den.

Siste sluttkontroll i `bin/production-image-cache-recipe-cleanup.json` er lest
tilbake: syntetiske kontoer, biblioteker, filer, fixture/guard, profiler og
journaler er fjernet; isolert Emby er faktisk stoppet. Tidligere
ServerStopped=false i cleanup-svaret er bevart, mens fersk FinalServerStopped
er true. Bygget har ingen advarsler eller feil. Filhash av installert test-DLL
matcher bygget produksjons-DLL; hashene identifiserer filene ved kontrolltid,
ikke en uavhengig runtime-attestering av alle historiske løp.

## Avgrensning

Denne endringen binder en lokal, validert bildekilde og en konkret cache-
oppskrift til en filsti. Den er **ikke et komplett bevis for innholdet i
cachefilen**, alle treff/miss, filutskiftning eller innsetting av fremmed
innhold på en ellers riktig sti.

Lokalisering via GetCachedImage, GetSupportedImage, enhancements, andre
providers/formater og endringer av native metadata krever egne reviderte
kildebevis. En mellomfil uten registrert original-/oppskriftsbevis godkjennes
ikke automatisk. Støtte for alle slike gyldige klientforløp gjenstår; dette
skal ikke regnes som ferdig klientstøtte. Undertekstjobber har ennå ikke en
tilsvarende uavhengig kontroll av konverteringens cacheoppskrift.

Øvrige serverinnganger, native mutasjoner, bruker-/tokenrevokering, faktisk
YouTube-henting/publisering og alle klientfamilier/serverbuilds gjenstår.
Ingen utrulling til hovedserveren er gjort i denne runden.
