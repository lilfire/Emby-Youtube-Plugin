# G – jobber, Google, videobuffer og lagringsgrenser

Undersøkt 2026-10-14 med HEAD `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`,
plugin `2.0.10-alpha.1`. **44 observasjoner er reprodusert; G sitt samlede
ferdigkrav er fortsatt åpent.** Syv observasjoner har `RequirementMet=false`;
det er ikke syv separate feil eller HTTP-lekkasjer.

## Miljø og faktisk testinngang

[Program.cs](Program.cs) kaller produksjonsimplementasjonene Catalog,
VideoBuffer, StorageBudget, InitialRefresh og Jobs direkte via eksisterende
InternalsVisibleTo. Store brukes til virkelige profiler, kryptering,
generasjonsendringer og readback. JobRuntime, Service, Lifecycle, Publisher,
QuotaTracker og konfigurasjon er i tillegg lest som integrasjonskode.

Windows `10.0.19045`, .NET `8.0.22`; produksjonsprosjektet bygger for net6.0,
testassembly for net8.0. SDK-pakkene er `MediaBrowser.Common` og
`MediaBrowser.Server.Core` `4.9.1.90`. **Ingen Emby-server ble startet**; det er
derfor ingen ny målt serverversjon. Tidligere alfaens `4.10.1.0` er historisk
serverbevis, ikke miljøet for disse komponentprøvene.

[WINDOWS-EVIDENCE.json](WINDOWS-EVIDENCE.json) inneholder faktiske DLL-hasher,
kildehasher, observasjoner og sluttopprydding. DLL-hashen gjelder dette bygget
av arbeidskopien, ikke en ren HEAD eller installert Lilflix-DLL. Andre kapitler
har samtidige endringer i blant annet konfigurasjon/service/testfiler; G har
ikke endret dem. De seks undersøkte G-modulenes kildehasher er registrert.

Google-transport er en **syntetisk HttpMessageHandler**, ikke ekte Google.
Nedlastertransport er samme testprogram som ekstern executable med en ekte
syntetisk underprosess. Filene har MP4-navn og syntetiske bytes, og beviser
ikke avspilling. Jobs sin execute-delegate er en eksplisitt testadapter;
JobRuntime og native publisering kjøres ikke gjennom serveren. Duplicate-
og paginationprøvene stopper før native publisher, med null-adapter som aldri
skal nås i det dokumenterte feilforløpet. Ingen nye produksjonsrettelser,
installasjon, serverendringer, HA-kall eller bruk av andre aktive fixturer.

Kjør fra repository med `./verification/FollowUp/G/Run-G.ps1`. Runneren feiler
dersom en forventet observasjon ikke reproduseres eller opprydding ikke består.
`RequirementMet=false` er tilsiktet evidens om et hull, ikke bestått ferdigkrav.

## G1 – kvote per prosjekt, nøkkel og bruker

Googles [Data API-oversikt](https://developers.google.com/youtube/v3/getting-started)
beskriver kvote på **prosjektnivå**. Nøkler fra samme prosjekt gir dermed ikke
uavhengige dagsbudsjetter for pluginbrukere. Kvote og andre begrensninger
kontrolleres hos Google; personlig profil/eier er pluginens modell.
[playlistItems.list](https://developers.google.com/youtube/v3/docs/playlistItems/list)
koster én enhet og har opptil 50 elementer per side. Kildene ble kontrollert
2026-10-14; faktisk tildeling må leses i prosjektets Cloud Console.

Catalog bruker utelukkende nøkkelen i Prepared og kaller ikke QuotaTracker.
QuotaTracker registreres i den eldre YouTubeApi-transporten og har global
statisk tilstand uten eier-/prosjekt-ID. Administratorens globale kvotestatus
er derfor **ikke personlig kvoteregnskap**, og teller ikke disse katalogkallene.
Ingen fallback til global nøkkel, delt katalogcache eller in-flight sammenslåing
finnes i Catalog. A/B med samme syntetiske nøkkel ga fire separate forespørsler
og egne samlings-/generasjonsreferanser. En kopiert A-snapshot med B som eier
ble avvist før transport. Ekte delt Google-prosjekt og rate-limit er ikke prøvd.

Forslag til F/I: skill global diagnostikk fra personlig status og dokumenter
delt prosjektkvote. Eventuelt personlig bruksestimat må merkes som lokalt
estimat; API-nøkkelen alene beviser ikke hvilket prosjekt eller restbudsjett
Google har. Ikke lagre rå nøkler som kvotebøtte-ID.

## G2 – providerfeil, timeout og status

Syntetiske quotaExceeded/rateLimitExceeded gir YouTubeQuotaExceeded;
keyInvalid/API_KEY_INVALID gir YouTubeKeyRejected; ukjent reason gir
YouTubeRequestFailed. HTML, nettverksfeil, timeout, tom kanalliste og >4 MiB
respons avvises. Providerdetaljer og syntetiske hemmeligheter er utelatt fra
prøvd exception/status. Jobs lagrer forskjellige feilkoder for A og B og
readback gir riktig eier; statusfilene inneholder ikke nøkkel eller kanal-ID.
Dette er komponentbevis, ikke nettleser-/HTTP-statuskontroll (F/I).

**Påvist timeout-gap:** Catalog bruker ResponseHeadersRead. Et svar med mottatte
headere og body som aldri avsluttes lever videre etter HttpClient.Timeout
(100 ms i adapterprøven, observert fortsatt ventende etter 350 ms). Eksplisitt
kansellering avslutter lesingen. Standardklientens 30 sekunder gir derfor ikke
en samlet body-deadline. JobRuntime har heller ingen samlet katalogfrist og
holder global lagringslease under lesingen. En slik body kan blokkere alle
eiere til profilkansellering/serverstopp. Forslag: linked deadline som omfatter
headere og alle body-lesinger, samt avgrenset retry/backoff for aktuelle feil.

Nedlasterens exit != 0 og oversize avvises med generiske, saniterte feil og
staging fjernes. Det skilles ikke mellom slettet/privat video, login-krav,
formatfeil og providerfeil: de ender normalt som RefreshFailed i Jobs.
Disse faktiske yt-dlp-feiltypene og visningen i klienten gjenstår.

**Påvist valideringsgap:** buffer godtar 1024 nullbytes med `.mp4`-navn ved exit
0. Det finnes hash-/størrelseskontroll, men ingen container-/sporvalidering.
Formatvalget ønsker AVC MP4 + M4A, med `best[ext=mp4]` som fallback; dette alene
beviser ikke støttede spor. Se [yt-dlp-dokumentasjonen](https://github.com/yt-dlp/yt-dlp/blob/master/README.md).
Forslag: begrenset media-probe før publisering med eksplisitt spor-/kodekstøtte.

## G3 – kansellering og prosesslivssyklus

Mens syntetisk parent fortsatt kjører, dreper produksjonens Kill(true) parent
og child ved cancellation eller nøkkelbytte; staging fjernes, og PID-readback
bekrefter avsluttede prosesser. Positive A/B-bufferkontroller består; B nektes
A sin Page, A-release lar B sin fil ligge, og B kan fortsatt hente katalog
etter A sitt nøkkelbytte. SHA-256 stemmer med faktisk produsert fil.

**Påvist heng:** syntetisk downloader avslutter mens child beholder arvede
stdout/stderr-handles. Produksjonen venter da i `Task.WhenAll(drainOut,
drainError)` uten kansellering. Etter cancellation var parent borte, child
levende og DownloadAsync fortsatt ventende etter 500 ms. Fixturen måtte drepe
child eksplisitt for å avslutte. 15-minutters timeout kontrolleres i exit-loop,
ikke i denne dreneringsventingen. Forslag: avgrenset drenering, sikker håndtering
av process tree også etter parent-exit, og OS-livssyklusinnramming for crash.

Det er **ikke** nytt bevis for faktiske yt-dlp/Node/FFmpeg, den faktiske
15-minutters timeouten, Linux eller serverprosess-KILL. Dispose kansellerer,
men venter ikke selv på drain; ingen varig prosessledger binder verktøy til
omstart. Samordne faktisk restart-/kill-test med E/J i eget miljø.

## G4 – fysisk lagring og budsjett

DownloadAllowance teller `media` + `buffer`, avviser utilstrekkelig logisk
budsjett og deler ledig kvote på to for staging/native dobbeltkopi. Baseline
8192 bytes ga allowance 4096; ekstern vekst på 4096 **inne i media** ga 2048;
8192 brukt ga StorageBudgetExceeded. Ventende lease kan kanselleres.

**Begrensning reprodusert:** filvekst utenfor media/buffer teller ikke; forsvunnet
media-katalog tolkes som null brukt. Ingen fysisk free-space-reservasjon eller
volumidentitetskontroll finnes. Dette er ikke et utført ENOSPC-/volume-detach-
eksperiment; pluginbudsjett er en logisk grense og kan ikke garantere at andre
prosesser lar volumplassen være tilgjengelig. Allowance leses én gang før hele
refresh; senere ekstern vekst kan gjøre dette øyeblikksbildet foreldet.

Windows-fil med FileShare.None fikk release til å feile med IOException;
B-filen ble beholdt, og retry etter unlock fjernet A. InitialRefresh sin
finally har én foreach uten per-fil feilisolasjon: første release-feil kan
stanse opprydding av resten og overskygge opprinnelig feil (kodefunn, ikke
multifil-integrasjonsprøve). Forslag: varig cleanup-retry/journal sammen med E,
per-fil opprydding og sanitert StorageUnavailable. Ikke slett ukjente filer
eller annet Emby-innhold for å kompensere for plassmangel.

Fullt/forsvinnende faktisk volum, diskfeil under native kopi/flush, runtime-
opprydding og ekstern vekst mellom allowance/publisering gjenstår med E/J.

## G5/G6 – rettferdighet, samtidighet og cache

32 ventende leases fullførte i en avgrenset prøve. Dette beviser ikke FIFO,
produksjonsrettferdighet eller lasttoleranse. JobRuntime holder én global lease
gjennom cleanup, Google, samtlige downloads, publisering og policyendring.
Én eier kan derfor holde andre i Queued svært lenge; body-/pipe-hengene over
kan gjøre ventingen ubundet. SemaphoreSlim-kontrakten gir ingen egen maksimal
ventetid. Forslag: endelige jobbfaser/deadlines og eksplisitt eierkø før større
laststøtte; budsjettert reservasjon krever en samlet modell med E.

Jobs-prøven reproduserer at A sin nye jobb venter på forgjengeren, B sin
test-executor kan gå videre, og gammel fremdrift ikke overskriver ny
ProfileRevision/status. B sin uavhengige executor er ikke bevis for at B går
forbi A i faktisk JobRuntime: den globale budget-lease er utenfor denne adapteren.

Catalog har ingen cache å invalidere. InitialRefresh samler video-ID-er per
jobb; Snapshot/keyrevision revalideres før transport og etter respons.
Forsinket A-svar avvises etter nøkkelbytte, med fungerende B-positivkontroll.
Reell native cache/ReadActive og samtidige Google-prosjekter er ikke prøvd her.

Kildeinspeksjon viser permanente dictionary-oppføringer per eier i Jobs/
InitialRefresh, og ventekjeder ved gjentatt Notify. Status er én aktuell slot
per eier, ikke en hard grense på antall tidligere ventende tasks. Målt CPU- og
minnelast ved mange eiere/100 kanaler/10 000 videoer er fortsatt uverifisert.

## G7/G8 – oppdateringsmodell og utvalg

Service kaller SaveForRefresh og Notify ved manuell lagring. Recover starter
jobber når status ikke er gyldig Ready; ReadActive gjenbruker aktiv samling for
samme generasjon. PollTimer i PluginEntryPoint gjelder eldre Watch Later-
funksjon, ikke periodisk personlig katalogoppdatering. Periodisk personlig
oppdatering er et **produktvalg**. Ingen slik scheduler er innført.

Utvalgsmodellen er et nylig upload-vindu per konfigurert kanal: opptil 100
kanaler, maxVideos 1–10 000 (default 50), og minst én plass per kanal kreves.
Per-channel grense er floor(maxVideos / channels); restplasser omfordeles ikke.
API-sider har maxResults=50, og channels.list gjentas for hver side. En stor
kanal fyller dermed ikke normalt hele historikken. Én utilgjengelig valgt
video stopper hele jobben; ingen prøvd skip-/erstatningspolicy.

**Påvist duplikatfeil:** Catalog godtar to oppføringer med samme video-ID på én
side. Selection dedupliserer ID, men metadata hentes senere med `Single` fra
hele siden, som kaster «more than one». Prøven brukte maxVideos=1, lastet én
syntetisk fil og reproduserte feilen før native publisher. Staging ble ryddet.
Forslag: bind én entydig Video til valgt ID ved innlesing og definer policy ved
motstridende metadata. Deduplisering mellom kanaler kan dessuten gi færre
videoer enn kvoten uten refill.

**Påvist manglende request-grense:** 150 tomme sider med forskjellige tokens
ble hentet ved maxVideos=1 før eksplisitt cancellation. Repeated-token-
kontrollen beskytter ikke mot nye tokens/duplikatfylte sider uten framdrift.
Forslag: maksimalt antall sider/forespørsler og fremdriftsgrense per kanal,
valider returned nextPageToken og total deadline. Token-settet kan ellers
fortsette å vokse. Nye videoer blir valgt ved ny manuell generasjon, ikke ved
automatisk løpende oppdagelse. Større samlinger støttes ikke av denne evidensen.

## Opprydding, readback og leveranser

Alle 44 forventede observasjoner ble lest tilbake fra evidensfilen. Eget
tilfeldig fixture-root under OS temp er fysisk fjernet; alle sporede parent/
child-prosesser er bekreftet avsluttet. Ingen container, konto, bibliotek eller
server ble opprettet. Underprosess i hengprøven ble eksplisitt drept før
sluttkontroll. Testmiljøvariabler ryddes. Build-output ligger i ignorerte bin/obj;
ingen rå logger, tokens, API-nøkler eller mediafiler er lagt til leveransen.

Nye leveranser er G.csproj, Program.cs, Run-G.ps1, denne rapporten og sanitert
WINDOWS-EVIDENCE.json. TODO G er oppdatert med åpne tiltak og begrensninger;
ferdige komponentundersøkelser er flyttet hit. E/F/J-avhengighetene og faktisk
Google/native/OS-prosess-/volumbevis gjenstår. G er ikke en ny støtteerklæring.
