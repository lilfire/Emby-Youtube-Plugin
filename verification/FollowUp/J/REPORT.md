# J – serverversjoner, plattformer og distribusjon

Undersøkelse utført 2026-10-14. **37 komponentobservasjoner og åtte
pakkeobservasjoner fullførte. J sitt samlede ferdigkrav er fortsatt åpent.**
Produksjonskode, allowlists og Lilflix er uendret. Ingen ny kandidat er
installert, publisert eller sendt til GitHub.

## Miljø, versjon og faktisk testinngang

HEAD `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`, plugin `2.0.10-alpha.1`,
assembly `2.0.10.0`, .NET SDK `8.0.416`. Prøvd produksjons-DLL SHA256:
`ECCB1B92D991886551DD462B8E99FE1ED31F23C82861910BE234E792BD8E55B0`.
Dette er arbeidskopien med eksisterende endringer fra andre kapitler, ikke
et rent HEAD eller hash av installert Lilflix-plugin.

Windows x64 `10.0.19045` / .NET `8.0.22`: 18 observasjoner.
Linux x64 / .NET `8.0.22` i lokalt Emby-image: 19 observasjoner.
Image-ID, harnesshash, container-gjenskaping og faktisk opprydding finnes i
[PLATFORM-METADATA.json](PLATFORM-METADATA.json). Image-taggen ble ikke hentet
eller oppdatert. Containere hadde nettverk deaktivert, UID 0, egne navn og et
nytt midlertidig volume. Ingen eksisterende container, delt port eller fixture
ble startet/stoppet. **Ingen Emby-server ble startet i denne undersøkelsen.**

[Program.cs](Program.cs) kaller faktisk produksjons-Store, VideoBuffer,
NativeCreationHook og EmbeddedDependencyLoader via eksisterende
InternalsVisibleTo. Native bibliotekadapter er DispatchProxy uten native
metodekjøring. Windows-nedlaster er testprogrammet som ekstern prosess; Linux
bruker en eksplisitt shelladapter. Mediene er 1024 syntetiske bytes, ikke
avspillbare videoer. Ingen ekte Google, yt-dlp, Node eller FFmpeg ble kjørt.
Harmony-prøven bruker en syntetisk metode og samme Harmony 2.4.2 som pluginen.
Den demonstrerer mekanismen, ikke en Emby-rutelekkasje.

## J1 – native kontrakter og serverbuilds

[WINDOWS-NATIVE-INVENTORY.json](WINDOWS-NATIVE-INVENTORY.json) sammenligner
rå metode-IL i lokal portable Emby 4.10.1.0 mot SHA256-litteraler i alle
PersonalYouTube-kilder. 41 metodetreff fordeler seg på Emby.Api (5),
Emby.Drawing (4), Emby.Server.Implementations (26),
Emby.Server.MediaEncoding (4) og MediaBrowser.Controller (2).
[LINUX-NATIVE-INVENTORY.json](LINUX-NATIVE-INVENTORY.json) inspiserer kun
Emby.Server.Implementations fra containerimaget: versjon 4.10.1.0 og samme
26 treff. Det er ikke en full Linux-rutekontrakt eller runtime-test.

Inventaret bruker PEReader, laster ikke serverassemblyene og registrerer
assemblyhash. Treff gjelder bare IL-bytes; signaturer, transitiv oppførsel,
tokenoppløsning og runtime-patching må prøves separat. Native metoder med
ikke-IL-body er ekskludert. Det er ikke undersøkt en annen faktisk Emby-build,
og ingen allowlist er utvidet. SDK 4.9.1.90 er en byggavhengighet, ikke bevis
for kjøring på Emby Server 4.9.

Produksjons-Install avviser en ukjent konkret ILibraryManager-implementasjon
med UnsupportedNativeContract, ContractMatched=false og Installed=false.
RequireAvailable avviser den også. Kodeinspeksjon viser eksakte signatur-/
type-/IL-sperrer i CreationHook, NativeAccess og tilgangsgatene. Et isolert
IL-avvik i en ellers støttet ekte server er ikke injisert og prøvd her.
Avslag på ny publisering er heller ikke en garanti for gamle native private
biblioteker ved unsupported serveroppgradering; tilgangskroker kan mangle.

## J2 – Harmony-konflikt, patch-tap og oppgradering

Prøven har fungerende eierkontroll og fremmedavslag før konfliktene.
En prefix med prioritet 900 og false-retur kan hoppe over den testede
tilgangsprefixen med prioritet 800. GetPatchInfo inneholder fortsatt riktig
owner og MethodInfo. Etter fjerning av konflikt virker kontrollen igjen.
Unpatch av egen prefix fjerner metadata og den faktiske kontrollen; ny patch
gjenoppretter begge. Alle J-patcher er fjernet i finally og lest tilbake.

Dette er en påvist begrensning ved **metadata som runtime-bevis**, ikke
demonstrert utlevering av private Emby-bytes. Production CreationHook sjekker
egen prefix i Snapshot/RequireAvailable; ReferenceGate/StaticSourceGate/
AssetSourceGate og ItemListGate har tilsvarende verifikasjon. Metadata alene
beviser ikke faktisk rekkefølge eller at andre prefixer/postfixer/transpilere
lar kontrollen kjøre. Workerens gatestatus beviser heller ikke alle ruter.

Produksjonsloaderen gjenbruker allerede lastet 0Harmony. Prøven bekrefter
gjenbruk av 2.4.2; en annen plugins eldre/nyere versjon er ikke kjørt.
Forslag til koordinator: pin/valider faktisk Harmony-kontrakt, prøv konflikter
på alle faktiske native innganger, og definer vedvarende karantene ved tap
som også beskytter eksisterende private biblioteker. Ikke stol på en
statusprobe som eneste beskyttelse. Integrasjon krever A/C/D/E/K.

## J3 – avbrudd og miljøvariabler

Begge plattformer prøver produksjonsbufferens cancellation etter faktisk
startet ekstern prosess, med 10 sekunders observasjonsgrense. Oppgaven
avsluttes, stagingfiler fjernes, B-profil er fortsatt aktuell og B-buffer
fullfører etterpå. B med A sin Page avvises før prosessstart. Hash på
positiv A-fil samsvarer med produksjonsresultatet.

Dette er **Buffering-komponentbevis**, også på Windows. Det er ikke faktisk
server-KILL, native JobRuntime-status, orphan-readback av alle underprosesser
eller reell downloader. Linux Preparing-avbrudd gjennom siste ekte Emby-
arbeider er fortsatt uprøvd; historisk Docker-livssyklusbevis er ikke gjentatt.
G sitt påviste pipe-heng etter parent-exit er ikke rettet av denne prøven.

Linux-adapteren krever at både LD_LIBRARY_PATH og LD_PRELOAD er fraværende;
den fullfører og lagrer null for begge. Den aktuelle containeren trenger
derimot /system-biblioteker for et vanlig glibc .NET-apphost. Et første forsøk
med .NET-programmet som child feilet etter stripping med manglende
libpthread.so.0. Endelig test bruker en eksplisitt shelladapter og er merket
slik i rapporten. Dette viser hvorfor administratorens wrapper kan være
nødvendig; stripping er ikke universell kompatibilitet med eksterne verktøy.

## J4/J5 – plattformer, rettigheter, vedvarende lagring og verktøy

En container opprettet et faktisk BusyBox-verktøy (0755) og syntetiske data
(0644) i eget volume. Containeren ble fjernet og erstattet med ny ID.
Ny container kontrollerte begge hasher og kjørte verktøyet fra samme path;
ephemeral testapp var borte. Dette prøver **recreate**, separat fra restart,
men ikke Emby-state, yt-dlp/Node/FFmpeg, verktøyoppdatering eller full restore.

Testcontaineren kjørte UID 0. Den faktiske Emby-tjenestekontoen og en annen
OS-brukers leseadgang er ikke prøvd. F har allerede målt 0755/0644 på
produksjonslageret og brede Windows-ACL-er. J endrer ikke disse rettighetene.
ARM64, macOS, andre libc-varianter og alternative serverbuilds er uprøvd.
Det finnes ingen dokumentert generell arkitektursperre som avviser disse;
de må merkes uverifisert, ikke hevdes automatisk fail closed.

En eksisterende ikke-utførbar verktøyfil avvises først ved Process.Start på
begge OS; staging ryddes. Et vilkårlig kjørbart testverktøy med forventet
output aksepteres. Produksjonen sjekker filtilstedeværelse, ikke verktøyversjon,
arkitektur eller faktisk mediecontainer. J foreslår versjons-/hashmanifest,
begrensede probes i faktisk serverkonto og ffprobe-kontroll før oppgradering.
Media-/prosesslivssyklusrettelser tilhører G/E; konfigurasjonsvisning til I.

## J6/J7 – installasjon, rollback og publisering

Eksisterende Build-ClosedAlphaPackage ble kjørt på aktuelt bygg med status
candidate-not-approved. [PACKAGE-EVIDENCE.json](PACKAGE-EVIDENCE.json) har
ZIP-hash og åtte fullførte observasjoner. [verify_package.py](verify_package.py)
validerer fem tillatte payloadfiler, manifest, prerelease, hash og størrelse,
uten å trekke ut noe. [test_package.py](test_package.py) avviser endret DLL,
traversalsti, duplikat, manglende fil, stabil versjon, feil størrelse og feil
separat archivehash. Tempvarianter er slettet og lest tilbake. En hash fra
samme kanal er ikke autentisert utgiveridentitet, og DLL-versjon er ikke lest
av Python-verifikatoren; eksisterende pakkebygger leser assemblyversjonen.

Pakkebyggeren bygger ikke DLL, binder ikke status til tester og godtar en
Version-parameter uten matching mot InformationalVersion/commit. Forslag til
koordinator: ren commit, eksplisitt build, versjonsbinding, verktøylock og
automatisk verifisering før prerelease-utgivelse. .github/workflows er ignorert
i dagens repo; det må avklares før en versjonert utgivelsesjobb legges der.

[INSTALLATION-PLAN.md](INSTALLATION-PLAN.md) gir konkrete kommandoer og
readback-/stoppkriterier for ren installasjon, oppgradering og rollback.
Den komplette native kjeden er **ikke kjørt**. Sikker rollback må inkludere
slettede kontoer, native private objekter, staging, Sync/live/cache og beskyttet
backup; bare Deleted eller dagens brukeroversikt er ikke nok. F/E/B/C sine
påviste restdata/mismatch betyr at en generell trygg tilbakeføringsgaranti
fortsatt mangler. Ingen eldre tilgangskontroll ble installert i denne prøven.
Ingen ekstern release-status er undersøkt eller hevdet; J publiserte ingenting.

## Reproduksjon, opprydding og begrensninger

Kjør `powershell -NoProfile -File verification/FollowUp/J/Run-J.ps1` fra roten.
Runneren trenger lokal portable 4.10.1.0, lokalt image og SDK; den henter ingen
serverbuild/verktøy og bruker ikke nettverk i containeren. Pakkekommandoer står
i installasjonsplanen. Feil stopper kjøringen. Observed=true betyr reproduksjon;
RequirementMet=false markerer hull og teller ikke som støttegodkjenning.

Windows- og Linux-bevis har Completed=true og TestDataGone=true.
PLATFORM-METADATA bekrefter ContainerGone=true og VolumeGone=true etter faktisk
remove og readback. Ingen Emby-prosess ble startet. Runneren reserverer egne
ubrukte navn og rydder dem også ved feil. Lokale buildfiler, DLL-kopi og ZIP
ligger i ignorert bin; portable leveranse inneholder bare tester, rapporter,
syntetiske observasjoner og hasher, ikke tokens/nøkler/media/rå providerlogger.

Tidlige harnessforsøk feilet på native ikke-IL-metoder i offline inventaret,
et ekstra testmarker som ble beholdt av Release, .NET-childens Linux-loader
og PowerShell-overføring av shellsitater. Disse ble korrigert, egne ressurser
ryddet og hele runneren kjørt på nytt. Ingen ufullført kjøring er bestått bevis.

Åpne ferdigkrav: faktisk annen Emby-build/IL-avvik; native patch-konflikt og
versjonsoppgradering; ekte Linux Preparing/Windows server-KILL Buffering;
ARM64/serverkonto/backuprettigheter; faktisk verktøyoppdatering og native
container-recreate; komplett trygg installasjon/rollback og commitbundet
binær prerelease-prosess. Undersøkelsen er levert, støttegarantien er ikke.
