# Ferdige native filer og slettet eier

Undersokt pa isolert Emby 4.10.1.0. Produksjonsplugin og hovedserver er uendret.
Dette gjelder den avklarte garantien mellom Emby-kontoer ved servertilgang.

`Test-NativeOwnerReadyFiles.ps1` fullforte med exit 0. Den endelige kjoringen
har 31 observasjoner: 29 HTTP-kontroller og to passive kontroller av den
faktiske native jobbens eksistens. Rapport:
`bin/native-owner-ready-files-results.json`.

Begge vanlige brukere hadde eget native bibliotek og en faktisk MP4. Hver
bruker autentiserte en syntetisk Sync-enhet. Native SyncPrepare produserte
Original-filer med ReadyToTransfer; funksjonssjekken `sync` var Allowed=true.
Ingen lisens- eller konverteringssjekk ble omgaatt.

| Kontroll | Resultat |
| --- | --- |
| A og B henter egne ferdige filer for sletting | 200, 11071 byte hver, SHA256 lik den respektive kildefilen. |
| B henter As ferdige fil for sletting | 404 uten private markornavn. |
| A slettes | Brukerlisten bekreftet at As bruker-GUID var borte. |
| B, As gamle token og anonym bruker provde As jobb, jobbelement og fil | Alle ni foresporsler gav 404, baade etter sletting og etter restart. |
| B henter egen ferdige fil etter sletting og etter restart | 200, 11071 byte og riktig SHA256 i begge kontroller. |
| Bs jobbliste og Ready-liste for eget target | 200 med eget markornavn, uten As markornavn, etter sletting og restart. |
| Bs Ready-liste for As target | 200 uten As markornavn, etter sletting og restart. |
| Ny serverprosess/guard | Enabled/Ready og annen BootId bekreftet. |
| Passiv native kontroll av As jobb | Exists=false etter sletting og etter restart. |

Den siste raden er viktig: Emby fjernet faktisk As jobb ved eierslettingen.
Resultatet beviser sperring av gamle referanser i dette forlopet og bevart
egen tilgang for B. Det er ikke bevis for handheving mot en privat jobb som
fortsatt finnes etter at alle private kildereferanser har forsvunnet.

Rapporten lagrer bare statuser, syntetiske stier/ID-er, markorindikatorer og
hash-match-resultater; ingen tilgangstokens eller reelle API-nokler.
Fixture-oppryddingen slettet bare journalforte brukere, biblioteker, mediefiler
og jobber. Native jobbfjerning ble lest tilbake i oppryddingen. Den umiddelbare
ServerStopped-kontrollen hadde samme korte prosessavslutningsrace som tidligere;
etterfolgende Get-Process bekreftet null EmbyServer-prosesser. Endelig kontroll
lagres separat slik at opprinnelig oppryddingsrapport ikke overskrives.

## Ny ruteinventering

`bin/native-route-inventory.json` ble hentet fra innlastede serverassemblier
med testpluginens passive refleksjonsendepunkt. Det har 582 deklarerte
RouteAttribute-oppforinger. Flere HTTP-metoder og aliaser gir egne oppforinger.
Dette er ikke 582 unike sikkerhetsruter eller bevis for faktisk registrering
av hver oppforing i HTTP-serveren. Inventeringen er et grunnlag for videre
rutevurdering, ikke en dekningsteller.

Konkrete kandidater utover de allerede provde MP4-/Sync-filene inkluderer
master/main/live.m3u8, bilde- og undertekstutlevering, samt LiveStreams.
Det grove mediefilteret traff ogsa brukerbilde-, administrator- og LiveTV-ruter;
disse er ikke automatisk relevante for privat YouTube-innhold.

LiveStreams/Open har ItemId; Close og MediaInfo bruker LiveStreamId uten
ItemId. PrivacyGuard utelater LiveStreamId fra generisk elementreferanse-
innsamling og har ingen egen LiveStreamId-eiertabell. Dette er en konkret
begrensning ved inspeksjonen, ikke et pavist runtime-angrep. Det trenger en
positiv privat stream og faktisk eier/fremmed-kontroll, eller et autoritativt
bevis for at disse rutene ikke kan na det private innholdet.

Full skjerming er fortsatt ikke bevist: nye format-/avledede ruter,
beholdte private referanser og faktisk TV-/mobilkompatibilitet gjenstar.
