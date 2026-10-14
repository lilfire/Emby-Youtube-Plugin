# Native søkehistorikk: tilgang før mutasjon

Isolert Windows Emby 4.10.1.0, 2026-10-13. Produksjonskode er rettet og
isolert verifisert; hovedserveren er ikke endret. Full skjerming gjenstår.

## Faktisk mangel

`bin/production-search-history-dates-before-guard-results.json` bevarer
Completed=true, 32 observasjoner og fem mislykkede kontroller. Fire av
dem viser faktisk endret native historikk: A markerer B sin private video
i A-historikken, et blandet A/B-kall endrer begge elementene i A-historikken,
og A kan markere sin avsluttede private kilde etter sletting og omstart.
Kallene returnerte 204. Vanlige søkelister skjulte allerede disse kildene;
det hindret ikke mutasjonen.

Den femte kontrollen fikk 204 med påstått B-bruker, men ingen endring ble
observert i det avleste snapshotet. Datoer var lagret med sekundpresisjon;
det regnes derfor ikke som et bevist fravær av tidsstempelmutasjon.
Tidligere medlemskapsbaserte diagnostikker på 29 og 32 observasjoner er
bevart separat. Ingen av disse fremstilles som fem bekreftede lekkasjer.

Native ReportItemsSearched.Post er inspisert: den henter bruker og hvert
oppgitt element, setter DateLastSearched og kaller synkron SaveUserData
per element. Den bruker ikke WasSearched-flagget til å fjerne markeringen.
En avvisning etter at det første elementet er lagret ville være for sen.
Metodens body-hash er
DB1EC783D88823724C2D93D300DEFB0C40E76C107749F9CF1DC10E81478D4AF3.

## Produksjonsrettelse

Referansefamilien omfatter nå 17 DTO-kontrakter. ReportItemsSearched har
en egen strengarray-kontrakt for Ids; UserId er en skrivbar streng.
Native Post må ha forventet void-signatur og akkurat inspisert body-hash
før installasjonen kan godkjennes.

Faktisk autentisert, aktiv Emby-konto gir autoritet. En påstått annen
bruker avvises. Hele ID-arrayet kopieres og kontrolleres før native Post:
hver referanse må finnes og være personlig tillatt eller en ordinær,
ikke personlig bundet kilde. Fremmed eller slettet personlig kilde,
manglende/ugyldig ID eller null element avviser hele kallet før første
mutasjon. Rammen begrenses til 2048 ID-er. En tom ramme er tillatt som en
ufarlig native no-op; dupliserte egne ID-er fungerer også.

Etter første vurdering tas samme eierlås som profilsletting bruker, og
hele rammen vurderes på nytt under låsen. UserId settes til faktisk konto
og native Ids får kopien. Låsen beholdes gjennom den synkrone native
mutasjonen til ServiceController-tasken er ferdig. Private ID-er filtreres
ikke ut etter delvis lagring.

ClearRecentlySearched trenger ingen ny personlig referansekrok i dette
arbeidet. Den innleste native UserService.Any bruker AssertCanManageUser
før ClearRecentlySearched. Begge ruteformer er kontrollert mot fremmed
konto, og egen global historikk kan fortsatt tømmes, også etter sletting
av en personlig profil. Dette er kontoens historikkrydding.

## Verifisering

Den private matrisen bestod 37 observasjoner og den blandede offentlige/
private matrisen 40, begge med Completed=true og null feil. Native
historikk og DateLastSearched leses direkte gjennom en adminbegrenset
fixture som bare godtar de to syntetiske testkontoene. Den er ikke en
produksjonsrute. Runtime-kontrakter for WasSearched-query og DateLastSearched
kontrolleres; de finnes ikke i den eldre SDK-typen brukt ved kompilering.

Avviste rapportkall får minst 2,1 sekunders avstand fra seed, slik at
sekundpresisjon ikke kan skjule en tidsstempelendring. ID-er og datoer
for begge kontoer må være uendret. Hvert innlogget rapportkall må nå én
faktisk produksjonskontroll, med riktig antall avvisninger. Den nye
17-DTO-kontrakten må være installert. Anonyme rapport-/ryddekall avvises.

Egne, dupliserte og tomme rapporter har positive kontroller. Blandede
rammer med eget element fulgt av fremmed, manglende, feilformatert eller
null ID må avvises uten å endre det første eget elementet. Native
rydding hos B fungerer, mens A ikke kan rydde B-historikken gjennom
DELETE- eller POST-aliaset. Alle relevante kall gjentas etter profilsletting
og omstart. I den blandede kontrollen er A-kilden offentlig: B kan da
markere den i egen historikk, og den er fortsatt offentlig etter at
A-profilen slettes. B-kilden forblir privat.

På samme produksjonsbinær bestod regresjon på søk 416 observasjoner,
direkte private/offentlige metadatareferanser 191 hver, og originale/
nedskalerte metadatabilder 191 hver. Til sammen har de sju rapportene
1257 observasjoner. Diagnostikk/oppsett inngår i dette antallet; det er
ikke 1257 forskjellige tilgangsruter.

## Arkiv og opprydding

Den varige kopien av denne kjøringen er
`bin/evidence/20261013T152041426-search-history/`. Den inneholder de sju
rapportene, før-rettelse-diagnostikk, native IL-inspeksjon, manifest,
produksjons-/fixture-DLL og brukt skript. Rapportenes SHA256 ble verifisert
ved kopiering. Dette arkivet brukes når mutable bin-rapportfiler erstattes
av senere tester. Tidligere oppryddingsmanifester er historiske snapshots,
ikke automatisk bevis for en senere binær eller overskrevne rapportfiler.

`production-search-history-cleanup.json` i arkivet dokumenterer stoppet
testserver, fjernede testbrukere/biblioteker/prøvefiler og fixture,
fraværende testprofiler og fixturejournal. Installert produksjons-DLL var
identisk med bygget DLL. Hovedserveren er ikke endret.

## Gjenstående krav

Den faktiske inngangen før native mutasjon med samtidig profilsletting
er fulgt opp i [PRODUCTION-SEARCH-MUTATION-RACES.md](PRODUCTION-SEARCH-MUTATION-RACES.md).
Andre
historikk-/liste-/kontooperasjoner, grensen på 2048, flytting, token- og
kontorevokering, event-/socket-utlevering, alle serverbuilds og native
klienter er heller ikke et komplett bevist område. Personlig YouTube-
publisering og faktisk avspilling gjenstår. Hele PLAN-FULL-SKJERMING.md gjelder.
