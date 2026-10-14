# Lukket alfa: godkjenningskontroll 2026-10-14

Leveranse: 2.0.10-alpha.1, lokal ZIP
bin/packages/2.0.10-alpha.1-20261014T102002670.zip.
Produksjons-DLL: SHA256
2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC.

| Krav | Konkret bevis | Resultat |
|---|---|---|
| Egen nøkkel og egne kanaler per faktisk innlogget bruker | Personlig tjeneste/store; 213 komponentkontroller; ekte Google med egen lagret profil i Docker, global nøkkel tom | Bestått i angitt omfang |
| Brukerens meny, lagring og produksjonsjobb | Chrome-meny og skjema; serveravlesning; vanlig bruker i Docker starter PluginEntryPoint-arbeider uten testadapter | Bestått |
| Vanlig native bibliotek og mediepublisering | Native Views/GetItems; én video fra hver av to kanaler; lesbare titler; server/klientbilder | Bestått |
| Avspilling i nettleser og tilgjengelig vanlig app | Chrome faktisk avspilling; stue-TV AndroidTv 1.8.54g faktisk videobilde, økende posisjon og aktiv stereo-utgang | Bestått; fysisk lyd ikke hørt med mikrofon |
| Skjerming av kontrollert innhold mellom testkontiene | Docker B med brede rettigheter ser ikke A-roten og får 404 på begge vanlige/original-strømmer; TV-kontobytte viser B sitt eget bibliotek | Bestått for disse prøvene; ingen universell garanti |
| Bytte, tilbakekalling, sletting, omstart og gjenoppretting | Windows-rapport med 13 observasjoner inkl. Preparing-kill; siste DLL i Docker: fersk erstatning, omstart, faktisk Buffering-kill/gjenoppretting og sletting av rot/referanser/filer | Bestått; Windows-Preparing-rapporten er fra tidligere DLL med samme livssykluskode |
| Administratoroppsett og brukerfeil | Alle åtte alfa-felt lagret fra Chrome og lest tilbake; DTO-mapping rettet; faktisk Google-nøkkel-/kvotefeil på server; kvotefeil og kanalvalidering synlig i Chrome | Bestått i angitt omfang; øvrige UI-feilkoder ikke prøvd individuelt |
| Installasjon, verktøy og tilbakeføring | INSTALL.md og KNOWN-LIMITS.md inkludert i ZIP; separat yt-dlp/Node/FFmpeg; alle pakkefilhashverdier kontrollert ved gjenåpning av ZIP | Bestått |
| Testopprydding | Windows: brukere/biblioteker/fixture-DLL/profildata/journal fjernet og prosess stoppet. Docker: profil Deleted, bibliotek/referanser/medie-/bufferkatalog fjernet og kun testcontainer stoppet | Bestått |
| TV og nettverk satt tilbake | Native app viste igjen Lilflix/thomas; HOME gav opprinnelig Projectivy-startskjerm; volum/mute uendret; tidligere nettverksfelt lest tilbake identisk | Bestått |

Primærbevis: ANDROIDTV-ALPHA-RESULT.md, BROWSER-ALPHA-RESULT.md,
DOCKER-ALPHA-RELEASE-RESULT.json, bin/android-original-route-results.json,
bin/personal-alpha-job-results.json og verification/PersonalYouTubeStore/bin/results.json.

Den siste produksjonsendringen normaliserer original.* slik den inspiserte
native ProcessRequest gjør etter ServiceController. Metodehash er kontrollert
på både Windows og Linux gjennom installerte kontroller og faktisk bruk.
Eier-, kilde- og filbeskyttelsen er beholdt. Sju egne/fremmede kilde-, HEAD-
og range-kontroller, faktisk TV-avspilling og ny Docker-publisering verifiserer
endringen. Livssyklus- og krypteringskoden er uendret av denne rettelsen.

Android mobil, andre TV-klienter, alle Emby-innganger, offline/Sync og lokale
klientlagre er ikke universelt verifisert. Dette endrer ikke alfaens avtalte
omfang og skal ikke beskrives som full skjerming eller generell produksjons-
godkjenning. Ingen hovedserver-plugin/konfigurasjon er endret, og ingen
offentlig utgivelse, Git-push eller tagg er laget.
