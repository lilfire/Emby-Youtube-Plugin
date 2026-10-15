# Evidens og godkjenningsnivåer

Avlest 2026-10-14. Dette er en evidensindeks, ikke en ny støtteerklæring.
Utgangspunktet er commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7` med
lokale fixture- og I-endringer. En versjonsstreng identifiserer ikke en DLL.

## Versjoner og faktisk testinngang

| Leveranse | Plattform / inngang | Transport | Identitet og begrensning |
|---|---|---|---|
| [Lilflix](../../PersonalChannels/LILFLIX-ALPHA-DEPLOYMENT.md) | Linux/container, Emby 4.10.1.0; installasjon og oppstart | Autentisert serverreadback, verktøykjøring | DLL `2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC`; ingen ny klientavspilling under utrullingen |
| [Historisk alfa](../../PersonalChannels/CLOSED-ALPHA-ACCEPTANCE.md) | Windows/Chrome/AndroidTv 1.8.54g; separat Docker | Simulert Google-katalog på Windows, ekte Google i Docker | Samme `2E68…` slutt-DLL; Preparing-prøven gjelder eldre DLL. Google → Docker → fysisk klient samlet er ikke prøvd |
| [A](../A/REPORT.md), [B](../B/REPORT.md), [C](../C/REPORT.md), [D](../D/REPORT.md) | Windows, isolert Emby 4.10.1.0, faktiske native HTTP-/skriverkjeder | Syntetiske native kilder og kontrollert timing; ingen Google-katalog | DLL `AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`; direkte fixture-binding er ikke full publisering. Fixturehash varierer per løp og finnes i kapitlenes bevis |
| [E](../E/REPORT.md) | Windows/Linux .NET-prosesser | Produksjonskomponenter med native SDK-bibliotekadapter | Kildehash i E/SUMMARY; ingen kjørende Emby-server, native database eller downloader |
| [F](../F/REPORT.md) | Windows native Emby 4.10.1.0; separat Windows/Linux lagerprøve | Native HTTP + syntetisk Google-katalog, faktisk medienedlasting; lagerprøve uten server | Native DLL `AD5D…`; separate lager-DLL-hasher i STORE-METADATA. Ikke en ekte Google Data API-kjøring |
| [G](../G/REPORT.md) | Windows .NET-komponenter, ingen Emby-server | Syntetisk HTTP-handler og ekte syntetiske parent/child-prosesser | Historisk DLL `93A510245B9176DA16B6615A0E04D0038530FB7ACED1752D60E78E01753AD671`; kildehash i WINDOWS-EVIDENCE |
| [H](../H/REPORT.md) | Windows Emby 4.10.1.0 på port 18108, faktisk web og AndroidTv 1.8.54g/Android 12 | Ingen Google-katalog; historisk ekte bufret video og syntetiske B-medier; fixture-publisering | DLL `AD5D…`; ny web HomeSections/SectionItems-lekkasje, fungerende avgrenset egen statisk avspilling og TV-kontobytte. Ingen samlet Google/Docker/klientgodkjenning |
| [I](../I/REPORT.md) | Windows, Edge DOM og C#-validering | Produksjonskontrollere med simulert Emby-/API-transport | DLL `ECCB1B92D991886551DD462B8E99FE1ED31F23C82861910BE234E792BD8E55B0`; ikke ekte native lagring/restart |
| [J](../J/REPORT.md) | Windows/Linux x64 .NET-komponenter, offline native IL-inventar og pakkekontroll; ingen Emby-server | Windows ekstern testprosess, Linux shelladapter og syntetisk Harmony-metode; nettverk deaktivert | DLL `ECCB…`; 37 komponent- og åtte pakkeobservasjoner. Ingen ekte Google/downloader/annen serverbuild/ARM64 eller full native rollback |
| [K](REPORT.md) | Lokal fil-/Git-/database-/prosess-/containeravlesning og ny G-kjøring | Ingen ny Google, native HTTP eller fysisk klient | Ny G-DLL `ECCB…`, 44 reproduksjoner, sju uoppfylte krav; kildeattestasjon i VERIFICATION |

Alle eldre PersonalChannels-rapporter er listet i [REPORT-INDEX.csv](REPORT-INDEX.csv).
Kolonnene inneholder rapporthash og commit-/hashverdiene faktisk registrert i
rapportteksten. «Not recorded» er manglende proveniens, og skal ikke fylles med
dagens buildhash. [ARTIFACTS.json](ARTIFACTS.json) har egne filhashverdier og
registrerte metadata fra JSON-artefaktene. A–J sine sluttrapporter er indeksert;
at undersøkelsen er levert betyr ikke at kapitlenes produktkrav er oppfylt.
Bevis for SDK-adapter, simulert transport og native server kan ikke erstatte hverandre.

## Tilgjengelighet og publisering

`tracked` betyr at filen finnes i Git-indeksen. `untracked-publishable` betyr
lokal, ikke ignorert fil som ennå ikke er committet; det er ikke en publisering.
`local-ignored` og `missing` er utilgjengelige i et vanlig checkout.
[LINK-AVAILABILITY.json](LINK-AVAILABILITY.json) avleser eksplisitte lokale
Markdown-lenker. Henvisninger bare som fritekst/backticks må leses i rapporten;
de er ikke et komplett lenkegrafbevis. Gamle `bin/evidence`-arkiver, mediefiler,
rå logger og ZIP/DLL-er ligger lokalt og skal ikke loves som Git-leveranse.

K har oppdatert pakkens kildedokumenter, uten å pakke om den historiske ZIP-en
eller endre dens manifest/hash. En ny binærutgivelse krever egen bygg-/pakke-
verifisering fra J. README lenker til de oppdaterte dokumentene.
[PUBLICATION-AUDIT.json](PUBLICATION-AUDIT.json) kontrollerer alle ikke-ignorerte
FollowUp-tekstfiler og kilder for nøkkel-/token-/webhook-/hjemmesti-mønstre,
uten å skrive ut funnverdier. Syntetiske fixture-nøkler og ett uttrykk for
runtime-tokenoppslag er eksplisitt gjennomgått. Dette er en mønsterkontroll;
rå providerrespons/logg eller binære filer skal ikke publiseres på grunnlag av den.

## Avgrenset regresjon

[REGRESSION.json](REGRESSION.json) velger åtte sekvensielle innganger: A privat,
A offentlig, A query/resultat/skriver-racer, C innhold og offentlig kontroll,
D transport og offentlig kontroll, samt G-komponenter. Pakken bevarer faktiske
eier-/fremmed-/offentligkontroller. Negative statuskoder uten fungerende positivt
innhold, tomme svar og HTTP 200 uten forventede bytes godkjennes ikke.

Sammenlign navngitte observasjoner, innhold, headere og opprydding med samme
kilde/DLL; registrer endringer og revurder kjente feil etter rettelse. Et exit 0
betyr at reproduksjonen fullførte, ikke at alle personvernkrav bestod. Den nye
K-kjøringen dekker G; de syv native inngangene er valgt fra eksisterende evidens
og er ikke kjørt på nytt av K. Sync/live, klienter, Linux/native crash og full
publisering krever fortsatt egne B/E/F/H/J-prøver.

## Separate godkjenningsnivåer

| Nivå | Minstekrav før ny godkjenning | Gjeldende status |
|---|---|---|
| Lukket alfa | Eksakt DLL/pakke, kontrollert innhold/kontoer, prøvd jobb/bibliotek/avspilling og begrensninger, parete tilgangskontroller for prøvde innganger, tilbakekalling/restart/opprydding og trygg rollback | Historisk avgrenset godkjenning og Lilflix-installasjon finnes. Senere P0-funn står åpne; ingen generell personverngaranti |
| Bredere klientstøtte | Egen klient/versjon/backend-matrise: visning, detaljer/bilder, video, seek/resume/spor, feil, kontobytte, gamle lenker og tilbakekalling; Sync-filoverføring der klienten tilbyr det; faktisk Google → backend → klient | Ikke godkjent samlet. Historiske Chrome/AndroidTv-prøver har konkret scope; øvrige kombinasjoner er uverifisert |
| Full skjerming | Lukket rutekart og alle kjente P0-hull, meningsfull positiv/negativ/offentlig kontroll, avledet proveniens og faktisk skriver/I/O, revokering/racer, kontosletting, journal/recovery/cache/backup og relevante plattformer/innganger; eksplisitt modell for betrodd host og offline kopier | Ikke godkjent. A–G påviser konkrete hull; manglende bevis er også sperre for påstanden |

Pass-count er aldri et godkjenningsnivå. Administrator og host er betrodd;
allerede nedlastede frakoblede kopier kan ikke tilbakekalles gjennom en ny
serveravgjørelse. Dette avklarer omfanget uten å godkjenne ny serverutlevering.

## Sluttopprydding

[CLEANUP-READBACK.json](CLEANUP-READBACK.json) viser null lokale fixtureprosesser,
ingen lyttere på 18096/18108/18217, ingen native-client-mediefiler, fixture-DLL,
aktiv klientjournal, personlig fixture-datamappe eller H-workspace.
[DATABASE-READBACK.json](DATABASE-READBACK.json) leser stoppet SQLite med
`mode=ro`: to beholdte baselinebrukere, null kjente syntetiske brukernavn,
null PrivateNative-/JournalPending-elementer og null Sync-jobber/jobitems.
Native bibliotekskatalogen er tom. Dette supplerer kapitlenes native ID-readback;
navnesøk alene beviser ikke fravær av alle historiske testidentiteter.

A/C/F sine tidlige `ServerStopped=false` er før stopp fullførte; senere
kapittelreadback og K sin prosesskontroll viser stopp. G sin nye kjøring
bekrefter fysisk fjernet temp-root og avsluttede sporede underprosesser.
I sin nettleserprofil `bin/followup-i-edge` ligger fortsatt igjen etter tidligere
automatisk avvist sletting. Ingen ny sletting er forsøkt av K. Den historiske
lokale containeren `embytube-test` er beholdt som `exited`; stoppet er ikke
fjernet. J sin endelige PLATFORM-METADATA bekrefter fjernet container og volume;
K sin nye Docker-avlesning følger opp tidligere `emby-youtube-j-platform`.
Lilflix/TV og historiske eksterne Docker-data er ikke lest tilbake på nytt av K.

H bekrefter tilbakeført TV/nettverk og slettet workspace med native data/tokens.
J bekrefter fjernet eget testvolume/container. Nettleserprofilen og den historiske
stoppede containeren er eksplisitt beholdte lokale rester, ikke aktiv testdrift
eller påstått fysisk sletting. Kapitlenes åpne produktkrav står fortsatt i TODO.
