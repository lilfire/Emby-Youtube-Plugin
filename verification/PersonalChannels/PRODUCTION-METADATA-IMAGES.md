# Bilder på native metadatareferanser

Isolert Windows Emby 4.10.1.0, 2026-10-13. Hovedserveren er ikke endret.
Dette er et avgrenset kilde- og tilgangsbevis; full skjerming er ikke oppnådd.

## Ordinær lekkasje før rettelsen

`bin/production-metadata-images-before-name-gate-results.json` bevarer
191 observasjoner, Completed=true og 56 mislykkede skjermingskontroller.
Genres/{Name}/Images/Primary og Studios/{Name}/Images/Primary, både med og
uten /0, returnerte faktiske private PNG-bytes til fremmed konto og anonymt.
Det skjedde i aktiv fase, etter profilsletting og etter serveromstart.
Hver av de fire navne-/indeksvariantene hadde 14 feil. Direkte numeriske
ID-ruter hadde allerede tilgangskontroll. Testen brukte ordinære HTTP-kall.

## Rettelse

PersonalYouTubeServiceReferenceGate inkluderer nå GetItemByNameImage:
Genres- og Studios-navn løses til native metadata-ID før tilgang vurderes.
Faktisk autentisert konto må ha en synlig og tillatt innholdskilde med
akkurat metadatareferansen. Forespørselen føres gjennom samme
asset-produsent, filleser, aktuelle tilgangskontroll, eierlås og native
skriver som ID-ruten. DTO-en mangler UserId og MediaSourceId; disse antas
ikke å finnes. Referansefamilien inneholder nå 16 konkrete DTO-kontrakter.

Dette implementerer ikke de andre navnebaserte bildefamiliene Artists,
Persons, MusicGenres eller GameGenres. De behandles ikke som verifisert
av at DTO-en deles med Genres/Studios. Det finnes ingen deklarert navnebasert
Tags-bilderute i brukt inventar; Tags kontrolleres gjennom native ID.

## Verifisert matrise

Fire rapporter har hver Completed=true, 191 observasjoner og null feil:

- `bin/production-discovery-metadata-images-protected-results.json`
- `bin/production-discovery-metadata-images-public-a-protected-results.json`
- `bin/production-discovery-metadata-images-protected-derived-results.json`
- `bin/production-discovery-metadata-images-public-a-protected-derived-results.json`

Hvert løp inneholder 65 metadataoversikt-/oppsettkontroller og 126 bilde-
kall. Bildekallene bruker A, B og anonym konto; private Genre/Studio/Tag-
referanser; navn, navn med /0 og numerisk ID der rutene finnes; aktiv,
slettet og omstartet fase. A og B har ulike blå/røde prøvebilder og brede
ordinære native bibliotekrettigheter. Ingen Google-nøkkel eller ekte
YouTube-video brukes i disse lokale bildetestene.

Originale tillatte svar må ha HTTP 200 og eksakt SHA256 for eierens PNG.
Avledede svar dekodes og må være PNG på 80x45, med eierens forventede
farge i tre ulike piksler. Alle tillatte svar i rapportene har én faktisk
servicekontroll, én asset-produsent, ett asset-output, én kontrollert
fillesning og én kontrollert skriving. Begge kontrollfamilier er installert.
Avviste svar har HTTP 404, generisk 15-byte tekst, ingen PNG-signatur,
ingen av de originale private bildehashene og ingen ETag, Last-Modified,
Content-Disposition, Content-Range eller Accept-Ranges.

De blandede løpene gjør A-kilden offentlig mens B-kilden forblir privat.
Begge innloggede kontoer får da A-bildene også etter sletting av A-profilen,
mens B-bildene forblir private. Anonyme bildeforespørsler avvises.
Dette hindrer at en kontroll som avviser alle bilder regnes som skjerming.

## Gjenstående bevis

Rapportene beviser ikke andre metadata-/bildefamilier, alle bildeparametre,
HEAD/range/conditional-kall på disse navnealiasene, andre revokeringshendelser,
cachefilenes komplette innholdsproveniens,
delte metadatafelter, alle serverbuilds eller TV-/mobilklientene.
Generell original/avledet videoressursregresjon er et separat bevis.
Hele planen i PLAN-FULL-SKJERMING.md gjelder fortsatt, inklusive personlig
YouTube-kallkjede, publisering, livsløp og resterende serverinnganger.

Profilsletting ved faktisk skrivegrense er fulgt opp separat i
[PRODUCTION-METADATA-IMAGE-WRITERS.md](PRODUCTION-METADATA-IMAGE-WRITERS.md).

## Regresjon og opprydding

På samme produksjonsbinær bestod direkte metadatareferanser 191 private og
191 blandede offentlige/private observasjoner. Kontrollen krever nå alle
16 installerte DTO-kontrakter. Originale PNG/SRT-videoressurser bestod 50
observasjoner; avledet PNG/WEBVTT bestod ytterligere 50. Disse fire løpene
er regresjon, ikke en utvidelse til alle native klienter eller innganger.

`bin/production-metadata-images-cleanup.json` inneholder SHA256 for åtte
beståtte rapporter og produksjons-/fixturebinærer. Den installerte
produksjonsbinæren er identisk med den bygde binæren. Avlest sluttilstand
har stoppet testserver, fjernede testbrukere/biblioteker/prøvefiler og
fixture, fraværende personlige testprofiler og fraværende fixturejournal.
Tidligere oppryddingsøyeblikk med ServerStopped=false bevares separat;
det regnes ikke alene som sluttbevis. Native generelle bildecachefiler
hevdes ikke fysisk purget av denne kontrollen.
