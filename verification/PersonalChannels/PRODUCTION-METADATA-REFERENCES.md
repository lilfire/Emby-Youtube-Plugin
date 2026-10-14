# Direkte metadatareferanser

Isolert Windows Emby 4.10.1.0, 2026-10-13. Hovedserveren er ikke endret.
Full skjerming og alle klient-/avspillingskrav er fortsatt ubevist.

## Funn

`bin/production-metadata-references-before-access-results.json` bevarer
Completed=true, 155 observasjoner og 40 IsolationPass=false. Oversiktene
var allerede filtrert, men vanlige kontoer kunne lese fremmede eller
slettede private metadata direkte. Både Genres/{Name}, Studios/{Name}
og Users/{UserId}/Items/{Id} returnerte HTTP 200 med privat navn og native ID.
Hver av de fem kombinasjonene (genre navn/ID, studio navn/ID, tag ID) hadde
åtte slike feil over aktiv, slettet og omstartet fase. Anonyme kall ble
avvist av native autentisering. Det finnes ingen deklarert tag-navnerute
i den innleste ruteinventarfilen; den er ikke testet som et fungerende API.

Dette var ordinære HTTP-kall, uten intern feilinnsprøyting. Private
indekselementer manglet bibliotekforeldre og ble derfor tidligere vurdert
som Unknown av den ordinære eierresolveren.

## Produksjonsendring

PersonalYouTubeNativeAccess klassifiserer nå de konkrete native Genre,
Studio og Tag-typene etter deres innholdslinker. En autentisert aktiv
bruker må ha en native synlig og personlig tillatt innholdskilde med
akkurat det aktuelle metadata-ID-et. Indekselementet selv får ikke fungere
som egen autorisasjonskilde; foreldreløse indeksobjekter avvises.

Native Source-query avgrenses med GenreIds, StudioIds eller TagIds.
Resultatets konkrete GetItemLinks kontrolleres også, sammen med ordinær
eier-/kildekontroll. Dette unngår full innholdsskanning per indeksobjekt
og lar offentlig synlig innhold etablere en legitim metadatakilde.
NativeScan undertrykker request-query-hooks for disse interne oppslagene;
de skal ikke feilaktig telle som filtrert responskildebevis.

De to navne-DTO-ene GetGenre og GetStudio er føyd til den eksisterende
referanse-/resultat-/skriverkontrollen, totalt 15 DTO-er. Navnet løses
read-only til ett konkret native ID av riktig type, før eiertilgang
kontrolleres. Ikke-entydig eller manglende navn avvises. Når UserId er
utelatt (Guid.Empty), settes den til faktisk autentisert konto; en annen
oppgitt konto godtas ikke. ID-rutene bruker den eksisterende GetItem-DTO-en
og den samme nye metadataresolveren.

Gjeldende kildetilgang kontrolleres også ved ferdig resultat og native
skriving gjennom eksisterende Allowed-predikat og skriverregistrering.
Dette er kilde-/tilgangskontroll for disse indeksobjektene, ikke komplett
felt-/byteproveniens for alle delte metadata eller avledede bilder.

## Verifisering

`bin/production-discovery-metadata-references-protected-results.json`
fullførte 191 observasjoner uten registrerte feil på siste produksjonsbygg.
Det inkluderer 65 metadataoversiktsobservasjoner og 126 direkte kall:
genre/studio med navn, navn uten UserId og ID, samt tag med ID, for begge
kontoer og anonymt, aktivt, etter lagret A-sletting og etter faktisk omstart.

Eget aktive metadata må returnere korrekt navn og ID; fremmede/slettede
svar må avvises uten disse verdiene. Kontrollene krever faktisk nådd
produksjonsreferanse-prefix med 15 installerte DTO-er. Positive direkte
kall krever én Checked, null Denied og én faktisk registrert native skriver.
Private avslag krever én Checked, én Denied og null slike skrivinger.
Anonym autentisering kan avvise før pluginens prefix og gir null skriving.

`bin/production-discovery-metadata-references-public-a-protected-results.json`
fullførte en separat 191-observasjonsmatrise på samme bygg. A sitt native
innhold var her offentlig (ingen privat binding); B var privat. Begge
kontoer kunne lese A sine metadata, også etter sletting av A sin separate
personlige profil. A kunne ikke lese B sin private metadata. Oversiktene
hadde korrekt blanding av offentlige, egne private og delte verdier.
Dette er en konkret positiv offentlig kontroll, ikke en antatt kompatibilitet.

Regresjon på samme endelige produksjonsbygg fullførte Views/Latest 26,
Suggestions før skriverkontroll 18, Counts 107 og opprinnelig GetItems 37
observasjoner. Bygg av produksjon og fixture hadde null advarsler/feil.
`bin/production-metadata-references-cleanup.json` er lest tilbake: testkontoer,
biblioteker, lokale prøvefiler og fixture er fjernet, testprofiler og
oppsettsjournal mangler, serveren er stoppet, og installert produksjons-DLL
har samme SHA-256 som det verifiserte bygget. Tidligere skriver-/assetrapporter
dekker sine respektive bygg, ikke en universell regresjon på dette bygget.

## Gjenstående krav

Navn med andre tegn/normalisering, GUID-aliaser for metadata, andre
indekstyper, navne-/ID-gjenbruk, fysisk bibliotekfjerning, per-elementantall
og andre felt i delte metadata må fortsatt kontrolleres. Metadataressurser
og navnebaserte bildealiaser, native link-/navnemutasjoner og timing ved
disse nye direkte skriverne er ikke bevist av denne matrisen. Bruker-/
tokenrevokering, ekte personlig YouTube-kjede, alle klienter og eksakte
Docker-/Linux-builds gjelder fortsatt som krav i hovedplanen.
