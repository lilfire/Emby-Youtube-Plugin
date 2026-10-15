# H – faktiske klienter

Undersøkt 2026-10-14. Faktisk Emby-web og stue-TV er prøvd mot en egen
Windows Emby 4.10.1.0-instans på port 18108. Undersøkelsen er levert;
**H er fortsatt åpent for rettelser og manglende klient-/Docker-bevis**.
En konkret web-lekkasje er reprodusert gjennom nye serverforespørsler.

## Versjon og testinngang

Utgangspunkt: commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`, plugin
2.0.10-alpha.1. Den testede produksjons-DLL-en har SHA-256
`AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
Fixture-DLL:
`F890627BFB0BD1438536C7C4EF2D79A75CDFB5B195228C30F19D143C22EFD0FD`.
[ENVIRONMENT.json](ENVIRONMENT.json) registrerer de kopierte binærene og
klient-fixturescriptet. Arbeidskatalogen hadde eksisterende endringer;
commit alene identifiserer derfor ikke alle fixturekilder. Andre endringer
og en ny DLL kom til i hovedarbeidskatalogen under undersøkelsen. H sin
kopierte DLL var fast gjennom prøven; resultatene godkjenner ikke senere bygg.

[Prepare-H.ps1](Prepare-H.ps1) kopierer den stoppede portable testserveren
til H sin egen ignorerte `bin/workspace`, med egen data, media og port.
Eksisterende klientfixture gjenbrukes som kopi med endret port/servernavn.
[Bind-H.ps1](Bind-H.ps1) oppretter produksjonsprofiler og registrerer native
referanser gjennom eksisterende ProductionBindingBridge. Dette er en
**testadapter for publisering**, ikke en komplett NativePublisher-/Google-jobb.
Metadata-, kilde- og skriverkontrollene som behandler klientforespørslene
er produksjonskode. Eksperimentell PrivacyGuard er deaktivert og tilbakelest.
Begge vanlige A/B-kontoer har brede native bibliotekrettigheter, tilbakelest
etter registrering. [PREFLIGHT.json](PREFLIGHT.json) viser fungerende egne
detaljsider og 404 på fremmede detaljsider for begge kontoer.

A bruker en historisk bufret, ekte YouTube-prøvevideo, SHA-256
`104BADBFDAE1F8F6089DB3F9BDDFFD3EA3192CD323E77F1D22CB6192B43B7AA0`.
B bruker en seks sekunders rød syntetisk MP4 med stille AAC-spor. Bilder og
SRT er syntetiske. H gjør ingen Google-katalogforespørsel, bruker ingen ekte
API-nøkkel og prøver ingen ny Docker-kjede. Ingen kandidat installeres på Lilflix.

## Klientmatrise og faktiske observasjoner

[CLIENTS.csv](CLIENTS.csv) angir versjon, plattform, backend og konkret
grunn for alle uverifiserte kombinasjoner. [UI.json](UI.json) registrerer
de observerte UI-/avspillerverdiene; skjermbilder og rå logger er lokale og
inngår ikke i publiserbare filer.

| Prøve | Faktisk resultat | Begrensning |
|---|---|---|
| Web: eget bibliotek/detaljer | A-detalj viser H264 640×360, AAC stereo og English SRT | Hjemmesiden har avviket nedenfor |
| Web: video | Prøvevideo synlig; currentTime 4,730635; readyState 4; error null | Kort, statisk MP4; ingen HLS-/transkodingsgodkjenning |
| Web: seek/pause/gjenoppta | Slider 30 % gir 2,981 s; videre avspilling 2,99752 s og paused=false | Varig resume etter app-/serverrestart er uverifisert |
| Web: undertekst | PrivateSubtitle_a_native_media faktisk synlig over video | Ett eksternt SRT-spor; øvrige spor uverifisert |
| Web: bilder | Egen B-thumbnail og fremmed A-thumbnail gir 404 i backendloggen | Egen bildevisning kan ikke godkjennes fra et negativt svar |
| Web: kontobytte/gammel lenke | B er bekreftet innlogget; direkte A-detalj viser Item not found | Hjemmesiden viser likevel fremmede metadata |
| Web: personlig oppsett | Preferences → YouTube åpner personlig skjema | Alfaaktivering er false; ingen native app-side godkjennes |
| TV 1.8.54g/Android 12: eget innhold | A-video og A-undertekst faktisk synlige; serveren rapporterer DirectStream | Historisk bufret video og Windows-backend |
| TV: pause/gjenoppta | A-posisjon øker fra 10 170 000 til 32 520 000 ticks | Ikke full seek-/varig resume-matrise |
| TV: A → B | Ferdig lastet B-hjem viser B og ikke A; B sin røde video synlig, DirectStream ved 11 220 000 ticks | Avgrenset hjemme-/avspillingsprøve, ingen generell lagringsgaranti |
| TV: lyd | Aktiv stereo-track ved 44,1 kHz; speaker-device ved 48 kHz | Samplet track-gain er -inf; fysisk lyd er ikke hørt, B-sporet er stille |
| TV: tilbakekalling | Etter lagret A-profilsletting viser ny A-hjem bare Playlists, ingen private A/B-biblioteker | Gammel TV-detaljlenke og aktive overføringer ikke prøvd |

Pi-inventaret viser Android 16/Emby Android TV 2.5.03g. Brukeren avtalte
stue-TV, og Pi ble bare lest, ikke styrt eller prøvd. Android mobil,
iPhone/iPad, Apple TV og native Samsung/LG-klienter mangler en tilkoblet,
avtalt testenhet. Ingen av dem markeres som støttet eller ikke støttet på
basis av fraværet. Den lokale Docker-inventarprøven viste ingen kjørende
containere; den sier ingenting om tilgjengeligheten til den historiske
eksterne Docker-verten. Eldre ekte Google/Docker- og Windows/TV-bevis
forblir separate. Ingen faktisk Sync-/download-klient er prøvd sammen med B.

## Påvist feil: web bruker andre hjemmeruter enn TV

Webs nye hjemmesideforespørsler gikk til ContentService sine HomeSections
og Sections-ruter. Android TV brukte Views og Items/Latest. Hjemmeavviket
bestod etter ordinært kontobytte og full reload. Det er **ny serverutlevering**,
ikke bare gammel lokal klienthistorikk: [Probe-H.ps1](Probe-H.ps1) gjentar
de konkrete rutene med hver aktørs eget token og lagrer [HTTP.json](HTTP.json).

| Rute, autentisert som A eller B | Positiv/negativ kontroll |
|---|---|
| Users/SELF/HomeSections?displayMode=mobile,desktop | Fremmed biblioteksnavn i 200-svaret |
| Users/SELF/Sections/smalllibrarytiles/Items?Limit=12 | Fremmed biblioteksnavn i 200-svaret |
| Users/SELF/Sections/latestmedia_OWN/Items?Limit=12 | Egen videotittel i begge kontoers svar |
| Users/SELF/Sections/latestmedia_FOREIGN/Items?Limit=12 | Fremmed videotittel i begge kontoers 200-svar |
| Users/SELF/Views, også AllowDynamicChildren=true/false | Fremmed bibliotek filtreres bort |
| Users/SELF/Items/FOREIGN og Videos/FOREIGN/stream.mp4?Static=true | 404 for begge kontoer, med fungerende egne 200-kontroller |

A ble merket uavspilt med den native PlayedItems-mutasjonen før siste
latest-matrise, slik at egen A-video igjen var en meningsfull positivkontroll.
[WEB-AUTH.json](WEB-AUTH.json) kontrollerer header-/query-autentisering og
format=json på Views; alle variantene filtrerer fremmed bibliotek. Det er
ikke grunnlag for å kalle dette en tokenplassering-/JSON-formatfeil.

**Endringsforslag til A/koordinator:** bind GetHomeSections og GetSectionItems,
og deres native ContentService-kilder og skrivere, til autentisert eier og
aktiv generasjon. Filtrer seksjonsnavn, referanser og bibliotektiles før
seksjoner dannes; filtrer latest/resultater før telling og paging. Kontroller
resume/resumeaudio/onnow og øvrige SectionId-varianter separat. A sitt rutekart
inventariserer disse DTO-ene, men inventar er ikke tilgangsbevis. H endrer
ingen produksjonsgate eller en annen fileiers kode.

## Tilbakekalling og resterende arbeid

[REVOCATION.json](REVOCATION.json) registrerer fullført produksjons-
MyProfile/Delete med Deleted tilbakelest. Nye statiske A-forespørsler fra
både A og B får 404; B sitt eget medieinnhold får fortsatt 200/11 071 bytes.
Webs gamle A-detaljlenke gir Item not found etter tilbakebytte til A, med
A-identitet bekreftet fra menyen. TV sin nye A-hjem skjuler den slettede
samlingen. Dette beviser ikke sletting av eksisterende klientcache,
tilbakekalling midt i overføring eller øvrige audio-/HLS-/Sync-ruter.

Videre arbeid: lukk hjemmerutelekkasjen og undersøk egen thumbnail-404;
gjenta UI-kontrollene på integrert DLL. Avtal mobil/Pi/Apple-/TV-klienter,
og prøv en samlet ekte Google → isolert Docker → fysisk klient-kjede.
Prøv gamle native TV-referanser, mer omfattende seek/varig resume, spor,
feilstatus og fysisk lyd separat. Avklar native app-inngang til personlige
innstillinger med faktisk meny/skjema. Sync krever fungerende klient-
filoverføring sammen med B; allerede frakoblede filer har annet omfang.

## Sluttopprydding

Stue-TV ble tilbakeført til Lilflix/thomas og opprinnelig launcher;
de to disponibel-filene på TV-en ble slettet og fraværet lest tilbake.
Testserverens fem nettverksfelter ble gjenopprettet og lest tilbake identisk,
med remote access=false. H sin separate server ble så ryddet med
[Cleanup-H.ps1](Cleanup-H.ps1). Native brukere, biblioteker, fixture og
mediefiler er borte; prosessen er stoppet og port 18108 er lukket.
[CLEANUP.json](CLEANUP.json) bekrefter endelig status, inklusive at hele
H-workspace med kopierte databaser/rå logger og lokale aktørtokens er slettet.
Lokalt beholdes bare kort screenshot-evidens under ignorert bin.

Reproduksjon på tilgjengelig lokalt fixturemateriale:
Prepare-H.ps1 → Bind-H.ps1 → faktisk klientprøve → Probe-H.ps1 →
Probe-H.ps1 -RevokeA → tilbakefør klient/nettverk → Cleanup-H.ps1.
Prepare krever at kildeserveren er stoppet og et nytt H-workspace.
Ingen ny binærstøtte må utledes uten å sammenligne ENVIRONMENT-hashene.
