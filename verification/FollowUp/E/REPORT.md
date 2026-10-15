# E – native eierskap, journal og gjenoppretting

Undersøkt 2026-10-14 på commit
`e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`, plugin `2.0.10-alpha.1`
(assembly `2.0.10.0`). Produksjons-DLL SHA-256:
`AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
Test-DLL SHA-256:
`AF863F8F6C509C39CE31BA9262036B14543441771F7C74F023E8943BC7CB76CA`.
Kildehasher finnes i [SUMMARY.json](SUMMARY.json).

**Konklusjon:** komponentprøvene reproduserer hull i journal-/restorekontroll,
isolasjon av oppstartsfeil og fysisk opprydding. E sitt samlede ferdigkrav er
ikke oppfylt. Ingen ny HTTP-utlevering av fremmed innhold er demonstrert her.
Produksjonskode, Lilflix og andre kapitlers filer/aktive fixturer er uendret.

## Faktisk testinngang og miljø

[Program.cs](Program.cs) kaller dagens produksjonsimplementasjoner av Store,
NativeBindings, PublicationJournal, NativeCreationHook, NativePublisher og
Lifecycle direkte, gjennom en separat testassembly med eksisterende
InternalsVisibleTo-navn. NativeCreation, NativeAccess, Jobs, JobRuntime,
InitialRefresh og PluginEntryPoint er også lest for kontrollflyt og integrasjon.
Ingen produksjonsfil eller felles testprosjekt er endret.

`LibraryProxy` er en eksplisitt **SDK-bibliotekadapter** for ILibraryManager.
Den leverer ID/GUID, foreldre, virtuelle kilder og syntetiske Video-objekter.
Filsystem, kryptering, journal-/profilskriving, autoriseringsavgjørelser,
gjenoppretting og opprydding bruker produksjonskode. Videofilene er små
syntetiske tekstfiler med tillatte navn; de beviser filopprydding og eksisterende
filer, ikke gyldig MP4, native innskanning eller fungerende avspilling.

Windows bruker .NET `8.0.22`. Linux bruker .NET `8.0.32` i en egen, lokalt
kjørt container, nettverk deaktivert, med bare testbygget montert read-only.
Containerens testdata ligger i eget `/tmp`, ikke i Windows-monteringen.
Runtime-image ble hentet som `mcr.microsoft.com/dotnet/runtime:8.0`;
runneren er låst til observert image-digest
`sha256:60d11c2be381e7f90b8bd984472dd2432933858aba55087d5936980cf2071d5a`.

**Ingen Emby-server ble startet i disse prøvene.** Det finnes derfor ikke et
nytt målt Emby-versjonsnummer eller produksjonsruntimebevis for native hendelser
eller Harmony i denne leveransen. Emby `4.10.1.0` er grunnlaget for tidligere
native kontrakter, ikke en ny serverprøve her. Ekte Google, yt-dlp, Node,
FFmpeg, hovedserver, HA og fysiske klienter er ikke brukt.

Begge endelige løp fullførte: **87 Windows-observasjoner** og **89
Linux-observasjoner**. `Reproduced=true` betyr at den beskrevne forventede
observasjonen ble reprodusert, også når den er et hull. `RequirementMet=false`
er henholdsvis **9 og 10 observasjoner**, ikke antall HTTP-lekkasjer eller
uavhengige feil. Windows manglet tillatelse til å opprette symlinker; begge
lenkeprøvene er eksplisitt skipped der. Linux fullførte dem.

## E1/E2 – identitet, registrering og historiske referanser

Paret baseline og gjentatte kontroller gir A tillatt egen video, B avslag på A
og B tillatt egen video. Ukjent barn under privat rot avvises for begge eiere
før registrering. Etter produksjonens Register tillates eieren og fremmed
avvises. Reparenting av et **bundet** A-barn til B avviser begge; bindingen
overføres ikke med foreldrene. Frakoblet bundet barn avvises uten aktiv rot.
Ny konto-GUID får ikke gammel autoritet. Testen bruker ingen navn som identitet.

Etter profilsletting, nye komponentinstanser og ingen nye snapshots blir gamle
registrerte numeric-/GUID-aliaser fortsatt avvist. Forsøk på gjenbruk av numeric
ID eller GUID for B feiler hver for seg. B fortsetter å virke.

Et aldri registrert og allerede fraværende barn har derimot `Unknown` i
DecideAbsentReference. Dette er en **manglende proveniensmodell**, ikke påvist
native hendelsestap eller utlevering av et slettet objekt. Kodelesing finner
produksjonsregistrering ved root-oppretting og avsluttende publisering, men ingen
eierskapsledger knyttet til ItemAdded/ItemUpdated/ItemRemoved. PluginEntryPoint
sin ItemUpdated-handler reparerer metadata/bilder, ikke dette eierskapsregisteret.

De historiske NATIVE-MEMBER-EVENT-PERSISTENCE og
NATIVE-GROWTH-WHOLE-ROOT-DELETION bruker eksperimentell NativeReferenceLedger.
Deres hendelsesbevis gjelder ikke automatisk dagens produksjon. Faktisk timing
for native vekst, flytting, hel rotsletting, kontosletting og ID-gjenbruk må
instrumenteres separat. B sine tidligere GUID-kollisjoner er også prototype;
de nye komponentprøvene bekrefter konfliktavslag, ikke fungerende produksjons-
innskanning ved gjenbruk. Journalens mediebane er avledet av eier/samling/generasjon.

## E3/E4 – journalfeil, mismatch og feilisolasjon

| Tilstand | Reproduksjon og betydning |
|---|---|
| Gyldig journal der bare A-entry er fjernet | Bundet A-barn tillates for A når resolveren ikke oppgir privat fysisk kilde. A-ID mangler også i DeniedRegisteredIds(A). Med privat mediebane oppgis avslag; fremmed B avvises fortsatt av bindingen. B sitt eget innhold virker. Dette er manglende journalkrav ved mismatch, ikke påvist fremmed byteutlevering. |
| Feil CreationRevision i A-entry | ReadActive avviser resume, men DecideItem tillater fortsatt A og avviser B. Kontrollene bruker forskjellige mismatchregler. |
| Feil eier-GUID i A-entry | A avvises, B sitt eget innhold fungerer. Avgrenset karantene virker her. |
| Korrupt global journal | Avslag gjennom InvalidDataException gjelder også uskyldig B. Trygt mot offentlig fallback, men oppfyller ikke «kun berørt samling sperres». |
| Korrupt A-profil | A-tilgang avvises og B-tilgang fungerer. RepairInterrupted kaster likevel; JobRuntime.Start sin catch disponerer den felles jobbruntime før oppstart kan fullføres. Sistnevnte integrasjonskonsekvens er kodelesing, ikke en kjørt serveroppstart. |
| Manglende journal eller marker | Fail closed, uten rekonstruksjon fra navn eller mapper. |
| Katalog på journalens rename-mål | Begin feiler med faktisk OS-skrivefeil. Ingen tmp-fil blir igjen. Required-marker blir igjen og hindrer usikker ny journal. Dette simulerer en rename-feil, ikke full disk eller tapt volum. |
| Manglende A-rot i adapteren | ReadActive gir null; RepairInterrupted roterer bare A sin generasjon. B beholder snapshot, filer og fungerende resume. |

Manglende journal-entry er konkret knyttet til PublicationJournal:
DeniedRegisteredIds behandler bare `entry != null` som journalavvik, og
DecideSources returnerer bindingsavgjørelsen hvis både entry og pathEntry er null.
En restore som etterlater gyldige bindinger uten samsvarende publikasjon må
ikke behandles som bekreftet aktiv bare fordi eieren fremdeles matcher.

Forslag til felles fileier: krev samsvarende aktiv journal for hver privat
binding ved både query-denials og direkte tilgang. Revalidér rotparet og
publikasjonsrevisjonen med samme kontrakt. Test migrasjon av eventuelle gamle
bindinger uten journal før regelen integreres; ikke gjør dem offentlige.
Bevar historiske konfliktavslag. Ingen slik rettelse er implementert her.

Forslag til E/F/G: isoler gyldige, berørte profil-/samlingstilstander under
oppstartsreparasjon. Strukturell korrupsjon i en delt fil kan ikke trygt knyttes
til én eier uten en sterkere lagringsmodell. En mulig modell er en validert,
varig indeks og per-samlingjournal med egne required-markers; indiscriminert
ignorering av feil i den globale journalen er ikke en løsning.

## E3 – faktiske prosessavbrudd på to plattformer

Hver plattform startet og tvangsavsluttet syv egne .NET-underprosesser.
Underprosessen kalte produksjonsmetodene, skrev en readiness-fil først etter
den angitte grensen, og ble drept før normal avvikling. Ny prosess/forelder
leser de vedvarende filene med nye komponentinstanser. Native adapterobjekter
rekonstrueres fra egne testidentiteter; dette er **ikke** native database-restart.

| Grense | Hva som faktisk var vedvarende | Readback/recovery |
|---|---|---|
| Waiting | Profil, ingen A-journal eller fil | Gjeldende generasjon beholdes; jobb må starte arbeid. |
| Buffering | Profil og syntetisk staging-fil, ingen A-journal | Gjeldende generasjon beholdes; test kjører ikke selve downloaderen. |
| Preparing | Journal.Begin | Eier og fremmed avvises; repair roterer generasjon; cleanup kan gjentas. |
| Reserved | Begin og ReserveRootIdentity | Reservasjonen sperrer før fullføring; repair roterer; cleanup fungerer med adapterkilden. |
| Publishing | Mediekopi og bindinger, før Activate | Begge avvises; repair roterer; kopier ryddes. |
| Active | Activate fullført | Resume fungerer med matchende adapterrot/video/fil; fremmed avvises. |
| Cleaning | Deleted-profil og første mediefil fjernet | Ny cleanup fullfører og B virker. Native rotfjerning midt i prosessavbruddet er ikke modellert. |

B sin faktiske journal-/bindingspositive kontroll virker etter alle syv
avbrudd. Prøvene viser persistens og retry ved disse **komponentgrensene**.
De beviser ikke avbrudd midt i filflush/rename, native callback, aktivering før
jobben blir Ready, riktig brukerpolicy etter restart eller terminering av
yt-dlp/FFmpeg. Windows Preparing og Docker Buffering fra tidligere alfa er
separate historiske serverbevis. Native fase/plattform-matrisen i TODO må
derfor fortsatt fullføres, også med reelle jobber og disk-/volumfeil.

## E5 – fysisk opprydding og stier

Journalført, tilbakekalt A-generasjon får native rot fjernet i adapteren, egne
mediefiler slettet og egne staging-filer slettet. Andre cleanup-kall er
idempotent og historiske aliaser forblir denied. B sitt innhold/resume virker.

Tre konkrete forhold krever oppfølging:

- **Staging før Begin blir foreldreløst ved tilbakekalling.** CleanupAsync
  itererer bare journal-entryer. Prøven skriver en staging-fil for en ekte
  Prepared-generasjon, sletter profilen gjennom produksjonskode før Begin,
  og finner filen igjen etter CleanupAsync. Normal buffer.Release eller
  sletting av nåværende staging er ikke bevis for denne gamle generasjonen.
- **Uventet media stopper diskopprydding etter native rotfjerning.** Prøven
  beholder en ukjent fil og mediemappen; B virker. Dette er sikker avvisning,
  men ikke atomisk native-/diskopprydding. Det trengs en dokumentert manuell
  eller automatisert retry-/karantenemodell for uventet innhold.
- **Symlink på selve lagringsroten følges på Linux.** En lenke på generasjons-
  mappen avvises, med intakt ekstern sentinel. En lenke på `_directory` blir
  derimot ikke kontrollert av ValidateDirectory sin parent-løkke. En gyldig
  staging-struktur i et separat disponibelt mål slettes gjennom lenken.
  Dette krever at selve konfigurert lagringsrot er en lenke; ingen vilkårlig
  klientstyrt path eller HTTP-utnyttelse er demonstrert. Windows-lenkeprøvene
  er skipped, ikke bestått.

Forslag til E/G: journalfør staging-hensikt før første fil og oppdag gamle
generasjoner fra betrodd profil-/bufferproveniens, også uten publikasjon.
Valider selve lagringsroten og alle relevante foreldre før native mutasjon og
filfjerning. Path.GetFullPath gir leksikalsk kanonisering, ikke stabil filidentitet.
Check-then-delete-racer og symlink-/inodebytte under opprydding gjenstår.
Ikke rydd fremmede eller ukjente filer ut fra navn alene.

## E6 – kontrollkroker

Den uverifiserte bibliotekadapteren avvises av production Install, og
CreatePreparingLibrary stopper før journal, mediemappe eller AddVirtualFolder.
Dette bekrefter avslag ved **utilgjengelig opprettingskrok**, ikke runtime-tap av
en tidligere installert Harmony-prefix eller delvis installasjon på Emby.

NativeCreationHook sin Snapshot/RequireAvailable leser faktisk Harmony-patch-
metadata. En tidligere native hook-loss-test finnes i
PRODUCTION-NATIVE-CREATION-HOOK, men bruker eldre testbro for tilgang.
Kodelesing av JobRuntime viser kontroll av creation/service/list ved jobbstart;
publisering og aktivering må også prøves etter senere tap av hver kontroll,
med B positivt og fremmed negativt gjennom faktisk native HTTP.

## E7 – backup, nøkkelmismatch og migrasjon

En sammenhengende kopi av profiler, krypteringsnøkkel, bindinger, markers,
journal og mediefiler dekrypterer riktig syntetisk nøkkel og gjenopptar med
matchende adapteridentiteter. Native DB, brukerpolicy og kontoer er ikke
backupet i denne prøven. Full samlet Emby-restore er fortsatt uverifisert.

Restore av en eldre, sammenhengende kopi etter en senere profilsletting
reaktiverer den gamle generasjonen. Modellen har ingen ekstern monoton
revokeringsforankring. Dette er en **restore-policy/begrensning**, ikke bevist
uautorisert restore: avklar om eldre backup skal gjeninnføre gammel autoritet,
eller om restore må lage nye generasjoner og sperre gamle referanser.

Feil krypteringsnøkkel får Prepare til å kaste CryptographicException.
Aktivt innhold tillates fortsatt i journalens tilgangsavgjørelse fordi
profilens offentlige View ikke dekrypterer nøkkelen. Dette er en **uavklart
mismatch-policy**, ikke en fremmedtilgangstest som feilet. Avklar sammen med F
om avspillbar lokal buffer skal overleve nøkkeltap, og skill nøkkeltap fra
utilsiktet blanding av backupgenerasjoner.

Feil native rot-GUID gir null fra ReadActive. Ukjent journalversjon (2)
avvises; ingen migrasjon er implementert. Manglende A-journal-entry og avvikende
CreationRevision er de konkrete delvise restoretilstandene i E4.

## Reproduksjon, opprydding og leveranse

Kjør fra repository-roten:

```powershell
powershell -NoProfile -File verification/FollowUp/E/Run-E.ps1
# Alternativ uten Linux: samme script med -WindowsOnly
```

Scriptet bygger eget prosjekt, kjører Windows, bruker egen Linux-container,
eksporterer bare validerte portable bevis og leser tilbake fjernet container.
[WINDOWS-EVIDENCE.json](WINDOWS-EVIDENCE.json) og
[LINUX-EVIDENCE.json](LINUX-EVIDENCE.json) har Completed=true, alle forventede
observasjoner reprodusert og TestDataGone=true. Samme produksjons-/testhash
gjelder på begge plattformer. Ingen underprosess blir stående; forelderen
venter på prosessavslutning etter kill, også i finally ved feil.

To innledende utviklingsløp fullførte ikke: Windows gav
UnauthorizedAccessException ved journalens rename-mål, der testen først bare
forventet IOException; den portable feilkontrollen er rettet. En senere
wrapper feilet ved PowerShell-quoting av Docker-label-readback etter at begge
testene hadde fullført. Den egne stoppede containeren ble identitetsverifisert
og fjernet, og hele wrapperen kjørt på nytt. Bare de endelige komplette
rapportene eksporteres. Rå rapporter og syntetiske filer ligger under ignorert
bin eller fjernet container; ingen tokens, nøkler, mediefiler eller rå logger
inngår i portable JSON.

Sluttstatus: 0 byggefeil/advarsler, testdata borte på begge plattformer, egen
container borte, ingen Emby-server eller port brukt. Nye filer ligger bare i
FollowUp/E, med koordinatoroppdatering av TODO. Ingen commit eller utrulling.
Alle resterende integrasjons-/plattformkrav og påviste hull står i TODO;
denne rapporten godkjenner ikke E eller full personlig skjerming.
