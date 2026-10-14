# Primary-bilder og eksterne SRT-undertekster

Oppdatering 13. oktober 2026: Historisk første rutetest før asset-leserbinding.
[PRODUCTION-ASSET-SOURCE-BINDING.md](PRODUCTION-ASSET-SOURCE-BINDING.md)
beskriver den nye bindingen, kontrollerte filstibytter og videre originale
og avledede tester. De åpne kravene må vurderes mot denne nyere evidensen;
full skjerming er fortsatt ikke bevist.

12. oktober 2026. Isolert Windows Emby 4.10.1.0 med lokale syntetiske A/B-filer,
vanlige kontoer, produksjonsprofiler/native bindinger og eksperimentell guard
avslått. Dette er en avgrenset produksjonsrettelse, ikke full skjerming eller
bevis for alle klienter, bildetyper, undertekstformater eller kildefabrikker.

## Faktisk hull

`Test-ProductionMediaAssets.ps1` fullførte 38 diagnostiske observasjoner før
rettelsen. 28 avslag som skulle vært håndhevet leverte HTTP 200 med faktisk
privat innhold: PNG-bildet var SHA-identisk med den opplastede prøvefilen
(363 byte), og SRT-svaret hadde den private undertekstmarkøren (71 byte).
Dette gjaldt andre kontoer og anonyme forespørsler. Etter faktisk profilsletting
og omstart fungerte også gamle A-referanser fortsatt for A selv.

Evidensen er bevart i `bin/production-media-assets-diagnostic-results.json`.
Alle passeringer av egne filer hadde positive kontroller. Testkontoene var
ikke administratorer, men hadde EnableAllFolders=true, kontrollert ved native
readback etter eierskapsregistreringen. Avslagene kan derfor ikke tilskrives
Emby sine vanlige bibliotekbegrensninger eller fixture-guard.

## Produksjonsendring

PersonalYouTubeServiceReferenceGate dekker nå også de konkrete DTO-ene
Emby.Api.Images.GetItemImage og Emby.Api.Subtitles.GetSubtitle. Den har dermed
13 eksplisitt registrerte DTO-er. Faktisk autentisert bruker og privat
referanse kontrolleres før tjenesten, ved tjenestens ferdige resultat og igjen
ved native skriverinngang under eierens eksisterende overføringssperre.
Profilendringer samordnes med samme sperre. Avslag kasserer resultatet og
private headere gjennom den eksisterende felles oppryddingen.

En oppgitt MediaSourceId kopieres som streng før tjenesten utføres og må
matche en aktuell, tillatt native statisk kandidat for samme private element.
Fremmed eller manglende kilde-ID gir et generisk avslag. Bildets normale kall
uten MediaSourceId bruker elementets aktuelle eierkontroll. Dynamiske/live
asset-kilder er ikke ferdig implementert gjennom denne kandidatkontrollen.

## Etter rettelsen

`Test-ProductionMediaAssets.ps1 -RequireIsolation` fullfører 50 observasjoner
i `bin/production-media-assets-protected-results.json`, uten feilede
IsolationPass-kontroller. Den prøver:

- Egne SHA-korrekte Primary-PNG-bilder og egne eksterne SRT-markører.
- Begge retninger mellom A/B og anonyme forespørsler.
- Faktisk lagret A-profilsletting og faktisk serveromstart med ny BootId.
- Gamle A-referanser, mens B sine egne ressurser fortsatt fungerer.
- Egen element-ID kombinert med fremmed kilde-ID for bilde og undertekst,
  sammenlignet med manglende kilde-ID i hver fase: identisk generisk 404,
  15 byte og ingen entityheadere.

De første forsøkene stoppet før testene og er ikke passeringer. Testhjelperen
krever begrensede rettigheter ved registrering, så registrering skjer nå før
rettighetene utvides. Native inspeksjon viste dessuten at prøvebildet indekseres
som Photo. Fixture-hjelperen godtar og registrerer nå akkurat det forventede
Photo-elementet, med eksakt syntetisk navn og filsti. Andre uventede medlemmer
godtas fortsatt ikke. Dette er testoppsett, ikke en utvidelse av hvem som kan
registrere produksjonseierskap.

Bygget fullfører uten advarsler/feil. Den eksisterende PlaybackInfo-skriver-
regresjonen fullfører 75 observasjoner med tretten-DTO-kontrollen installert.
Sluttkontrollen i `bin/production-media-assets-cleanup.json` er lest tilbake:
syntetiske brukere, biblioteker, filer og fixture er fjernet, profiler og
journaler er borte, og den isolerte Emby-prosessen er faktisk stoppet.

## Neste beviskrav

Faktisk skriverpause før produksjonskontrollen med samtidig fullført
profilsletting er nå verifisert for begge ruter, med 56 observasjoner hver:
[PRODUCTION-ASSET-WRITE-REVOCATION.md](PRODUCTION-ASSET-WRITE-REVOCATION.md).
Sletting som venter etter tatt skrivesperre er også kontrollert med 58
observasjoner per rute i [PRODUCTION-ASSET-TRANSFER-LEASE.md](PRODUCTION-ASSET-TRANSFER-LEASE.md).
Senere I/O-/bytegrenser gjenstår. Normal HEAD/304/én range gjennom sletting
og omstart er nå kontrollert i
[PRODUCTION-ASSET-HTTP-VARIANTS.md](PRODUCTION-ASSET-HTTP-VARIANTS.md).
Variantspesifikke skriver-racer, andre formater,
transformerte/cached bilder, image-info-ruten, undertekst-playlister/HLS og
andre ressursruter gjenstår. Faktisk bilde-/undertekstleser og avledet kilde
er heller ikke uavhengig bundet på samme måte som den nylig auditerte statiske
videoleseren. Privat kilde-/cacheproveniens og native mutasjoner gjenstår.
Faktiske YouTube-kilder, alle klientfamilier og andre serverbuilds er ikke
verifisert. Ingen utrulling til hovedserveren er utført i denne runden.
