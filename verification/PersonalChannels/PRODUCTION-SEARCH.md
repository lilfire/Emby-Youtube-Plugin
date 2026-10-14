# Native søk i personlige biblioteker

Isolert Windows Emby 4.10.1.0, 2026-10-13. Produksjons-DLL og hovedserver
er ikke endret i denne oppfølgingen. Den eksisterende GetItems-kontrollen
er verifisert for konkrete søkevarianter. Full skjerming er ikke oppnådd.

## Faktiske resultater

Tre løp har Completed=true og null IsolationPass=false:

- `bin/production-discovery-search-protected-results.json`: 416 observasjoner.
- `bin/production-discovery-search-protected-search-write-revocation-results.json`: 420.
- `bin/production-discovery-search-protected-search-write-lease-results.json`: 421.

Hvert løp inneholder 405 søkekall og ni separate diagnostiske kall til den
eldre søkeruten. Resten gjelder oppsett, omstart og eventuelle skrivergrenser.
De diagnostiske kallene regnes ikke som et eget bestått tilgangsbevis.

Søkene bruker Items og Users/{UserId}/Items, vanlig SearchTerm og Fields
Path/ProviderIds. A, B og anonym konto bruker påstått A-/B-bruker-ID eller
utelatt ID der ruten tillater det. Søkeord matcher begge prøvevideoene,
bare A eller bare B. Hele resultatet, første side og siden etter siste
element kontrolleres i aktiv, profilslettet og omstartet fase.

Egen, komplett positiv kontroll krever nøyaktig ett korrekt eget element
og TotalRecordCount=1. Fremmed søkeord og slettet egen kilde gir tomt
resultat og nulltelling. Fremmede/deaktiverte navn og native referanser
skal ikke forekomme i svaret. Anonyme kall skal avvises uten private data.
Hvert innlogget søk må nå én faktisk produksjonsscope, minst én kontrollert
native query og én registrert skriver; alle åtte liste-DTO-er må være
installert. Anonyme kall forventes avvist før denne bruker-scopen.

På siden etter et eget siste element tillates native TotalRecordCount=0
eller 1, men ingen elementer. Dette er en bevisst begrensning: native
tomside-telling er ikke et løfte om en bevart total på alle sider. Ingen
fremmed telling tillates. Andre side-/filterkombinasjoner er ikke bevist.

## Sletting ved faktisk skrivergrense

Før kontrollen: søkeresultatets native skriver pauses, A-profilen slettes
og Deleted leses tilbake. Etter slipp må svaret være generisk 404 på
16 bytes uten private resultater eller ressursrelaterte svarhoder. Den
faktiske produksjonsskriveren må registrere én avvisning.

Etter kontrollen: A-overføringen må holde eierlåsen og slettingen må vente.
B kan samtidig lagre en profilendring og få ny revisjon. Det tillatte
A-resultatet fullfører med 200 før slettingen fullfører, og låsen må deretter
være frigitt uten ventere. Etterfølgende søk og omstart kontrolleres også.
Timingkroken bruker den eksisterende native StreamWriter; den lager ingen
søkeresultater og gir ingen tilgangsavgjørelse.

## Den eldre Search/Hints-ruten

Autentiserte kall svarte med `[]`; anonymt kall ga 401. Tomt svar alene
er ikke et bevis. Den faktisk innleste native SearchService.Get(GetSearchHints)
er derfor inspisert: kun to IL-instruksjoner, Array.Empty<string>() og ret.
Body-hash er FB1D68D001CCDB4DCB13D7D2D10A50D9191B9903DBEFD12524F5769F78543067.
Ingen bibliotekdata leses i denne metoden. Rapporten
`bin/native-search-hints-processing-inspection.json` er ikke trunkert.
Det siste skriverløpet krever eksplisitt akkurat denne native kontrakten.
Andre serverversjoner får ikke samme konklusjon uten ny inspeksjon.

## Verifierrettelse og opprydding

`bin/production-search-first-diagnostic-results.json` bevarer den første
diagnostikken: 80 feil skyldtes at PowerShell pakket et enkeltelement ut
av listen, slik at Size ble null. De aktuelle svarene hadde riktig eget
navn, TotalRecordCount=1 og ingen fremmede navn/referanser. Det er ikke
dokumentert som en produksjonslekkasje. Verifieren beholder nå en faktisk
array også for null eller ett element, og de komplette løpene er gjentatt.

`bin/production-search-cleanup.json` bevarer hash og antall for de tre
rapportene, native inspeksjon og brukt produksjons-/fixturebinær. Installert
produksjons-DLL er identisk med bygget DLL. Sluttilstand er lest tilbake:
testserver stoppet, testbrukere/biblioteker/prøvefiler og fixture fjernet,
personlige testprofiler og fixturejournal fraværende.

## Gjenstående krav

Dette dekker ikke RecentlySearched-mutasjoner, anbefalinger/Similar,
remote metadata-søk, andre itemtyper, ParentId/filtervarianter, andre
revokeringshendelser, alle serverbuilds eller faktisk TV-/mobilklient.
Personlig YouTube-kallkjede og publisering er også fortsatt uferdig.
PLAN-FULL-SKJERMING.md gjelder fortsatt i sin helhet.
