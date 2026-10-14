# Personlig nokkel og kanaler: krav til bevis

Undersokt 2026-10-11. Dette beskriver nodvendig arbeid; det er ikke en levert
personlig konfigurasjonsfunksjon eller et ferdig sikkerhetsbevis.

## Faktisk kode i dag

- `PluginConfiguration.cs` har en global ApiKey, SavedItems og WatchLaterPlaylist.
- `YouTubeChannel.cs` leser Plugin.Instance.Options og bruker en global kanal-ID og DataVersion. En personlig API-nokkel kan derfor ikke bare legges til i skjemaet og antas a gi separate samlinger.
- `YouTubeConfigSaveService.cs` krever Admin for SaveConfiguration og Regions. SaveConfiguration oppdaterer det globale konfigurasjonsobjektet under en felles lock.
- `YouTubeApi.cs` cacher API-svar og paagaende foresporsler etter URL. URL inneholder API-nokkelen, og diskfilnavn bygger pa SHA256 av URL. Ulike nokler far ulike foresporselsnokler, men samme nokkel er ikke et bevis pa samme Emby-eier.
- `QuotaTracker.cs` har globale statiske tellere. Den skiller ikke per Emby-bruker eller API-prosjekt. Dette er kodeinspeksjon, ikke et pavist kryssbruker-kvoteangrep.

## Runtime-kontroll av eksisterende konfigurasjon

`Run-NativeLibraries.ps1 -RequireProtected -ProbeConfiguration` bestod med
67 observasjoner og exit 0. De ni nye radene er i
`bin/native-library-protected-configuration-results.json`.

| Aktor | GET plugin-konfigurasjon | POST SaveConfiguration med ugyldig JSON |
| --- | --- | --- |
| Admin | 200, konfigurasjonsfeltene finnes | 400 |
| Vanlig bruker A | 403 | 403 |
| Vanlig bruker B | 403 | 403 |
| Anonym | 401 | 401 |

Post-testen sender kun et aapningsklammetegn som JSON. Dermed stopper parsing
for konfigurasjonsmutasjon hvis tilgangskontrollen skulle slippe foresporselen
gjennom. Admin 400 er en positiv kontroll av denne ugyldige foresporselen,
ikke en test av gyldig lagring. API-nokkel, SavedItems og WatchLaterPlaylist
ble lest tilbake og sammenlignet i minnet; rapporten lagrer bare Unchanged=true.
Ingen hemmelige verdier er skrevet i rapporten. Opprydding bestod.

## Krav som personlig funksjon ma oppfylle

| Del | Nodvendig kontroll | Bevis som fortsatt mangler |
| --- | --- | --- |
| Eier av personlige innstillinger | Identiteten tas fra autentisert sesjon. En innsendt UserId er ikke autoritet. | A kan lese/endre egen profil; B og anonym kan ikke lese/endre den via sti, query eller body. |
| API-nokkel | Separat lagring per eier og eksplisitt bruker av nokkelen i alle aktuelle API-kall og bakgrunnsjobber. Vanlig profil-GET bor returnere nokkelstatus uten a returnere den lagrede hemmeligheten. | Syntetiske markornokler viser at A/B ikke blandes ved samtidige kall, omstart, nokkelbytte eller feilsvar. Ingen faktiske nokler trengs for tilgangstester. |
| Kanalvalg og bibliotek | Varig kobling mellom bruker, samling, biblioteksrot og alle medieelementer. Eier identifiseres ikke bare gjennom kanalnavn eller en cacheoppforing. | Nye/flyttede/slettede elementer, restart og identiske YouTube-kanaler hos to brukere beholder riktig eier. |
| Native tilgang | Eierskap handheves for direkte metadata, media, nedlasting, varsler og mutasjoner. | Full rutegjennomgang og ekte klient-/offlinebevis. IsVisible og biblioteksrettigheter alene har moteksempler. |
| Cache | Private valg, lister og eierkoblinger har eget scope. Deling av offentlig API-metadata er bare akseptabelt nar den ikke avslorer andres private valg eller nokkel. | A endrer bare egen profil uten observerbare endringer i Bs samling; begge kan bruke samme nokkel/kanal uten a bli samme eier. |
| Kvote og bakgrunnsarbeid | Bruk av riktig nokkel og rapportering knyttes til riktig profil/prosjekt. En global teller er ikke en personlig kvotemodell. | Samtidige jobbforlop og bytte/sletting av profil bruker ikke den andre profilens nokkel. |
| Klienter | Personlige samlinger forblir vanlige biblioteker med egne positive kontroller. | Faktiske apper og lokal cache ma provdes. Et fungerende webskjema erstatter ikke dette. |

Kravene bevarer brukerens onskede losning: personlige samlinger i vanlige
Emby-biblioteker, med handheving i pluginen. Ingen ekstern gateway eller
egen webside er brukt som erstatning for denne funksjonen.

Produksjonspluginen er uendret. Eksisterende Admin-grense passerer, men dette
beviser ikke en fremtidig personlig profilgrense. Full skjerming er fortsatt
ikke bevist.

## Personlig profilprototype: faktisk runtime-bevis

PersonalProfiles.cs er en separat testprototype, ikke produksjonsfunksjonen.
Den tar eierens GUID fra autentisert Emby-bruker og har ingen bruker-ID som
valgparameter. Normal GET returnerer eier, samlings-ID, kanaler og nokkelstatus,
uten API-nokkelen. AES-GCM bruker eier-GUID som authenticated associated data.
En serverintern PrepareRequest leser og dekrypterer samme eiers nokkel under
lagringslaasen, sammen med samme eiers kanal-/samlingssnapshot. Det syntetiske
PreparedRequest-testendepunktet returnerer bare SHA256 for kontrollen.

Run-PersonalProfiles.ps1 bestod med exit 0 og 71 kontroller inkludert opprydding.
Run-PersonalProfiles.ps1 -WithGuard bestod med exit 0 og 73 kontroller, inkludert
bekreftet aktiv sentral guard og gjenoppretting i en ny serverprosess.
Rapporter: bin/personal-profile-results.json og bin/personal-profile-guard-results.json.

Kontrollene omfatter egne profiler og korrekt nokkeldekryptering, forfalsket
UserId/OwnerUserId/CollectionId i query/body, fremmed profilsti, ugyldige
oppdateringer uten mutasjon, anonym GET/POST, samt avvisning av testendepunktet
for andre enn testbrukerne. Identisk nokkel og kanal hos A/B beholdt forskjellige
uforanderlige samlings-ID-er. Klartekstmarkornokler fantes ikke i profilfilen.

24 samtidige arbeidsoppgaver utforte tre ekte HTTP-kall hver (POST profil,
GET profil og GET prepared snapshot), 72 kall totalt. Hvert svar ble kontrollert
mot faktisk eier og uforandret samlings-ID; dekryptert nokkelfingerprint tilhorte
bare denne eierens sett av syntetiske rotasjonsnokler. Dette er HTTP-samtidighet,
ikke instrumentert bevis for overlapp inne i lagringslaasen.

Sletting av As nokkel endret ikke Bs profil. Profil, samlings-ID og brukbar
dekryptert nokkel overlevde en verifisert restart. Kopiering av Bs krypterte
nokkel til As post gav feil ved dekryptering og ingen nokkelutlevering; B var
uendret. En slettet bruker som ble opprettet med samme navn fikk ny GUID og
kunne ikke arve gammel profil. Alle testbrukere og profil-/nokkelfiler ble
fjernet med readback; testserveren var stoppet og testpluginen fjernet.

Dette beviser de provde profilrutene i testmodellen. Det beviser ikke et nytt
menypunkt, faktiske YouTube API-kall eller bakgrunnsjobber, kvotescope, varig
binding til et native bibliotek, alle feil-/crashforlop eller vertsfiltilgang.
Produksjonspluginen har fortsatt global konfigurasjon. Testprototypens
syntetiske brukernavnbegrensning er ikke en produksjonsimplementasjon.
