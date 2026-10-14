# Lilflix: installert lukket alfa

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

Tidligere testdokumenters formulering om at hovedserveren er uendret gjelder
testfasen før denne utrullingen. Begrensningene i KNOWN-LIMITS.md gjelder fortsatt;
oppstartskontrollen er ikke en ny avspillingsprøve eller garanti for full skjerming.
