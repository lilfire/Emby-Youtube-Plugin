# Produksjonsbinding av bilde- og undertekstkilder

Ny oppdatering 13. oktober 2026:
[PRODUCTION-IMAGE-CACHE-RECIPE.md](PRODUCTION-IMAGE-CACHE-RECIPE.md) beskriver
en senere påvist produsentfeil og rettelsen med uavhengig lokal bilde-
cacheoppskrift. Beskrivelsen nedenfor er første asset-binding før denne
rettelsen. Komplett cacheinnhold/proveniens og full skjerming gjenstår.

13. oktober 2026. Isolert Windows Emby 4.10.1.0, syntetiske lokale A/B-filer,
vanlige kontoer med brede native bibliotekrettigheter og eksperimentell guard
deaktivert. **Full skjerming er fortsatt ikke bevist. Ingen utrulling til
hovedserveren inngår i denne runden.**

## Produksjonsendringen

`PersonalYouTubeAssetSourceGate` følger den private forespørselen gjennom
native bildeprosessor og undertekstjobb. Den kontrollerer aktuell eier og
profilgenerasjon, faktisk native valgt bilde/mediestrøm og kildefilsti.
ImageProcessingOptions og ItemImageInfo kopieres; MediaStream, arrays og
headerdictionary kopieres. Dette er ikke en generell dyp kopi av all native
metadata. Native bildeprosessor kan oppgi ItemId uten Item; kontrollen slår
da opp den faktiske native posten.

ProcessImage sitt tuple-resultat og undertekstjobbens OutputPath registreres
innenfor den aktive konstruksjonsscopens kildebevis. Originalsnarveier
kontrolleres mot aktuell native originalsti. AsyncLocal gjenopprettes
synkront ved tjenestens retur; scopen avsluttes ved taskens slutt. Avsluttede
scoper som er arvet av bakgrunnsarbeid binder ikke nye produsentkall.

Asset-rutene bruker nå `PersonalYouTubeStaticSourceGate`: separate kopier
for metadata og leser, bundet native leserdelegat og kontroll ved fabrikk,
leser og skriver. Godkjent skriver holder eierens sperre under skriving.
Kontrakten kontrollerer native entry- og async-worker-IL-hasher og de
installerte Harmony-prefix/postfix. Native ISubtitleConversionJob finnes
ikke i kompileringens eldre SDK; resultatet håndteres derfor gjennom den
kontrollerte runtime-typen.

Dette registrerer et resultat fra en avgrenset native produsent med validert
input. **En uavhengig komplett kontroll av cacherecept og cacheinnholdets
proveniens er ennå ikke implementert.** Registrert output er ikke alene et
bevis for at alle interne cachevalg eller filutskiftninger er korrekte.

## Resultater lest tilbake

Alle rapportene nedenfor har Completed=true og ingen feilede IsolationPass.
De tilhørende prosessene fullførte med exit 0. `bound-` skiller denne
produksjonsbindingen fra historiske rapporter uten binding.

| Rapport under `bin/` | Observasjoner | Konkret evidens |
| --- | ---: | --- |
| bound-production-media-assets-image-derived-source-trace-results.json | 51 | 197-byte PNG, dekodet 80x45 og blå A-farge; separat native leseralternativ |
| bound-production-media-assets-subtitle-derived-source-trace-results.json | 51 | 63-byte WEBVTT med A-markør uten B-markør; separat native leseralternativ |
| bound-production-media-assets-http-variants-results.json | 158 | Egne originale PNG/SRT med HEAD/ETag/range; fremmede/anonyme/slettede referanser avvist gjennom omstart |
| bound-production-media-assets-image-source-mismatch-results.json | 52 | Validert syntetisk A/B-filstibytte nås én gang og avvises |
| bound-production-media-assets-subtitle-source-mismatch-results.json | 52 | Samme kontrollerte feil for original SRT |
| bound-production-media-assets-image-write-lease-results.json | 58 | Godkjent bildeskriver holder eierens sperre; sletting venter, B-oppdatering fungerer |
| production-playback-info-write-results.json | 75 | Opprinnelige ti DTO-tilfeller med tretten-DTO-porten installert |
| derived-lifecycle-bound-production-media-assets-http-variants-results.json | 158 | Hele matrisen bruker dekodet 80x45 PNG og WEBVTT, inkludert begge eiere, fremmede/anonyme, blandede kilde-ID-er, sletting og omstart samt HEAD/ETag/range |
| derived-lifecycle-bound-production-media-assets-image-write-results.json | 56 | Faktisk ventende avledet PNG-skriver avvises etter fullført profilsletting |
| derived-lifecycle-bound-production-media-assets-subtitle-write-results.json | 56 | Faktisk ventende VTT-skriver avvises etter fullført profilsletting |
| derived-lifecycle-bound-production-media-assets-image-write-lease-results.json | 58 | Godkjent avledet PNG-skriver holder eierens sperre; sletting venter og lagres etter frigjøring |
| derived-lifecycle-bound-production-media-assets-subtitle-write-lease-results.json | 58 | Samme kontroll for VTT; B sin uavhengige tilgang/oppdatering bevares |

Begge originale feilinnsprøytinger har Injected=1, generisk HTTP 404 med
15-byte `Item not found.`, ingen entityheadere og IoCallsDelta=0. Telleren
måler kall til den bundne native leserdelegaten, **ikke all fil-I/O**. En
markør som aldri ble nådd ville ikke bestå testen. Dette er en avgrenset
intern feilsimulering med syntetiske filer, ikke et påvist vanlig klientangrep.

Den hele avledede matrisen kjøres med `-DerivedAssets -HttpVariants
-RequireIsolation`. Egne PNG-svar dekodes og kontrolleres for format,
dimensjoner og eierens forventede farge på tre punkter. Egne VTT-svar må
ha WEBVTT og riktig eiermarkør uten den andre eierens markør. Positive
HTTP-kontroller bruker de faktiske egne lengdene, validatorene og byteprefiks.
Egne B-svar er bevart etter A-sletting og omstart. Dette er lokale syntetiske
transformasjoner, ikke alle bilde-/undertekstformater eller faktiske apper.

De to før-kontroll-løpene når faktisk ventende native FileWriter og lagrer
profilsletting før skriveren frigis. Svaret blir generisk 404 uten
entityheadere, og produksjons-WritesDenied øker nøyaktig én gang. Her er
skriversvaret 16-byte `Items not found.`; tjenestens vanlige avslag er
15-byte `Item not found.`. De to etter-kontroll-løpene bekrefter at sletting
venter ved eierens sperre mens godkjent eget svar beholdes og B kan oppdatere
sin profil. Etter frigjøring er slettingen lagret og ingen sperre/venter står
igjen. Begge ressursene testes på begge sider av skriverkontrollen.

HTTP-matrisen ble kjørt på nytt etter at alle vanlige avslag også måtte ha
akkurat det generiske 15-byte svaret; siste rapport har 158 observasjoner.
Dette er ikke en race ved hver HTTP-variant eller ved en senere bytegrense.

Fersk sluttkontroll i `bin/production-asset-source-binding-cleanup.json` er
lest tilbake etter siste prosess: syntetiske kontoer, biblioteker, filer,
fixture og guard er fjernet; profiler og journaler er borte, og isolert Emby
er faktisk stoppet. Det tidligere cleanup-svaret hadde ServerStopped=false
mens stoppingen pågikk; separat FinalServerStopped=true er siste readback.
Filhashene i sluttkontrollen identifiserer lokale binærer og testscript på
kontrolltidspunktet; dette er ikke en runtime-attestering av alle rapporter.
Bygg av produksjon og fixture fullførte uten advarsler eller feil.

Tidlige feil ved runtime-interface/patchverifisering og native ItemId-only
ga ikke beståtte tester. Den historiske
`production-media-assets-image-derived-source-trace-results.json` ble
overskrevet av et mislykket installasjonsløp og har Completed=false.
Den skal ikke brukes som bestått rapport. Den nye `bound-`-rapporten
ovenfor er det bevarte beviset for den nåværende positive PNG-tracen.

## Gjenstående beviskrav

Ny lesing av den bevarte native IL-inspeksjonen bekrefter at bilderecepten
inkluderer kilde, bredde/høyde, maksimal bredde/høyde, kvalitet, UTC-ticks for
endringstid, format, blur, bakgrunn og foreground. Native GetCachePath bruker
GetMD5 og en underkatalog fra første tegn i cachefilnavnet. Relevante helper-
hashes er EF3395C3ABF7C27DA5A6784C4EB9E3E2FF83FEA25E0494F0FE5E8C8A07503DC1
og 2DD3EC7DE388F2020F897BC6C03E545D5DC48F292690C747AB02DFD88A48C84A.
Dette er inspeksjon, ikke en ny installert cachekontrakt eller et bevis for
innholdet bak cachefilnavnet.

- Cacherecept, treff/miss og faktisk cacheinnhold må knyttes til autorisert
  kilde, eier og transformasjon. Native produsentresultat må også testes med
  kontrollerte feilvalg, separat fra filfabrikkens options-bytte.
- Eksterne bildeleverandører/lokalisering, andre bildeformater og sammensatte
  bilder, embedded undertekster og øvrige konverteringer er ikke bevist.
- Filutskiftning, native metadata-/foreldreendringer, bruker-/tokenrevokering,
  lange overføringer og senere bytegrenser krever egne kontroller.
- Øvrige serverinnganger, faktisk YouTube-henting med brukerens nøkkel,
  komplette native biblioteker, dynamisk avspilling og alle klientfamilier
  gjenstår. Windows 4.10.1.0-testene beviser ikke Docker-/Linux-builds.

Dette dokumentet erstatter eldre påstander om at assets helt mangler separat
leserbinding. De eldre inspeksjonene er historisk evidens for utgangspunktet;
de åpne kravene over er fortsatt nødvendige for full skjerming.
