# Lilflix: installert lukket alfa

## Gjeldende: 2.0.11-alpha.1, 2026-10-15

Etter uttrykkelig brukerbestilling er kildecommit `6759f86` bygget og installert
i `emby_backup`, Emby 4.10.1.0. API-et viser YouTube assembly `2.0.11.0`.
Installert DLL SHA256 er
`2DE94E0F869D303F6E6C2870285B44FCA81852A125EFAE8B3B974C65609C1F66`.
Den gamle DLL-en (`4FC47099…`), serverkonfigurasjon og plugininnstillinger er
sikkerhetskopiert mens Emby var stoppet, under
`/config/youtube-alpha-backups/20261015T051314Z-2.0.11-alpha.1`.
Ingen `youtube-personal`-mappe fantes før byttet. Innstillingsfilen er uendret,
lest tilbake byte for byte mot sikkerhetskopien. Containeren kjører.

Arbeider, verktøystatus og Creation/References/Lists er aktive uten rapportert
feil. HA `embymedia` for Lilflix er `loaded`. Servernøkkelkall til Counts,
VirtualFolders og BoxSet-listen ga HTTP 200 på 1,26–1,78 s. En eksisterende
ordinær brukers Items, Views og Latest ga HTTP 200 på henholdsvis 1,78, 1,53
og 1,53 s. Dette er enkeltmålinger etter utrulling, ikke en belastningstest.

**Linux-begrensning:** `SourceBarrierInstalled=false`, med 0 inventory builds/hits.
Den nye kildebufferen er derfor ikke aktiv her; full skanning brukes som reserve.
Årsaken er ikke diagnostisert i denne utrullingen. Privat eier/fremmed-tilgang,
Google og avspilling er ikke prøvd på hovedserveren som del av oppdateringen.
Tidligere kjente alfa-begrensninger gjelder fortsatt. Maskinlesbart avlest
resultat: [LILFLIX-2.0.11-alpha.1.json](LILFLIX-2.0.11-alpha.1.json).

## Tidligere installasjoner

2026-10-14: Etter uttrykkelig brukerbestilling er 2.0.10-alpha.1 installert
og aktivert på Lilflix, Emby 4.10.1.0, container emby_backup.

DLL SHA256: 2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC.
Eksisterende plugin, serverkonfigurasjon og plugininnstillinger ble sikkerhetskopiert
mens Emby var stoppet. Sikkerhetskopien ligger under vedvarende /config:
youtube-alpha-backups/20261014T111039Z. deployment.json inneholder avlest status.

Verifiserte verktøy er kopiert til /config/personal-tools og kjørt i hovedcontaineren:
yt-dlp 2026.08.19, Node v24.21.0 og FFmpeg/ffprobe N-127511-g01cf1a5396.
Personlig alfa er aktivert med to videoer per kanalutvalg, 256 MiB per video,
512 MiB per samling og 2 GiB samlet lagringsbudsjett. Eksisterende øvrige
plugininnstillinger, inkludert global API-nøkkel og kanalvalg, er beholdt.

Etter omstart svarte riktig Lilflix-server. DLL-hash stemmer, innstillingene
er lest tilbake via autentisert API, og PersonalServerStatus bekreftet
AlphaEnabled, WorkerRunning, MediaToolsAvailable og installerte Creation,
References og Lists uten feil. Containeren kjører. Ingen personlige API-nøkler
eller kanaler er lagt inn på vegne av brukere under utrullingen.

## 2026-10-14 19:56: item-list-gate-fiks for server-API-nøkler
Ny DLL SHA256 `4FC47099FCB9833CEC2BFA1522A73051EBDB32F1B3EE0EDE9EFF35F2575E7983`.
Forrige DLL (`2E68B8DE…`) er sikkerhetskopiert til
`youtube-alpha-backups/20261014T175643Z-gatefix`. Etter `docker restart emby_backup`
er alle tre gatene installert, det har vært 0 404-er i `embyserver.txt`, og HA
`embymedia` gikk fra `setup_retry` til `loaded`. API-nøkkelkallene tar 6–10 s per kall
(`slow-prefix`, 104 178 elementer skannet, 2 829 nektet), så full skanning er fortsatt åpent.

Tidligere testdokumenters formulering om at hovedserveren er uendret gjelder
testfasen før denne utrullingen. Begrensningene i KNOWN-LIMITS.md gjelder fortsatt;
oppstartskontrollen er ikke en ny avspillingsprøve eller garanti for full skjerming.
