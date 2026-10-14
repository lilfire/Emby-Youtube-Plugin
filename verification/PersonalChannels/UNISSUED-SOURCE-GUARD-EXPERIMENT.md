# Aldri-utstedt henvisning: kontroll ved faktisk kilde

Isolert Emby 4.10.1.0, 2026-10-12. Bare testfixture/prototype endret.

## Moteksempel selv med varig tokenregister

Test-NativeUnissuedOpenToken.ps1 klargjorde bare A sin dynamiske kilde.
B sin kildehenvisning ble konstruert fra native leverandorprefiks og
B sin eksisterende video-ID. SHA256 av denne henvisningen var ikke i
registeret, og ingen B-provider-Open var utfort. Begge kontoer var vanlige
ikke-admin-kontoer med egne ekte native PlaySessionId-er.

A sin positive Open/MediaInfo/Close var 200/200/204. Med egen privat
ItemId og konstruert B-henvisning fikk A 404 uten sideeffekt. Med ItemId
utelatt fikk A ogsa 404, men B-provider-Open okte med 1 og native
_openStreams fikk en ekstra B-strom. Ingen privat videotittel ble utlevert
i det avviste svaret. Etterpa ble B sin kilde klargjort: tokenen var
eksakt lik den konstruerte henvisningen. B sin egen Open/MediaInfo/Close
med denne tokenen passerte, men den ekstra B-strommen stod igjen.

Baseline bin/native-unissued-open-token-results.json er beholdt:
Completed=true, 8 observasjoner, MutationCases=1, NoForeignMutation=false.
Dette er en gyldig aldri-utstedt henvisning, ikke en tilfeldig ugyldig ID.

## Kildekontroll i den avgrensede leverandoren

Service-prototypen beholder naa autentisert konto i en AsyncLocal-scope
og gjenoppretter tidligere scope etter tjenesteinvokasjonen. Den lokale
fixture-providerens OpenMediaSource opploser faktisk token -> bibliotek-
element og kontrollerer elementets eier mot denne kontoen for den teller
Open, oppretter ILiveStream eller returnerer kilde. Ukjent/sperret eier
eller manglende/mismatchet autentisert scope avvises.

Dette er en kontroll i fixture-leverandoren, ikke en ny generell Emby-
tilgangskontrakt. Den erstatter ikke de andre leverandorenes sikkerhet,
produksjonens YouTube-kilder eller varig eierskap for alle artefakter.

## Passerende native kontroller

To friske rettingskjoringer fullforte med exit 0 og 8 observasjoner hver.
Samme aldri-utstedte angrep med og uten ItemId fikk 404 uten B-provider-
Open eller endring i native stromtabell. Egne Open/MediaInfo/Close bestod
for begge kontoer. Native tabell var tom ved slutten.

Forste rapport er bin/native-unissued-open-token-source-guard-first-results.json.
Den andre, bin/native-unissued-open-token-source-guard-results.json, har
dessuten en konkret teller for avslag i selve kildekontrollen:
no-item-kallet gav SourceGateDenialDelta=1, BProviderOpenDelta=0 og
BNativeBefore=BNativeAfter=0. Dermed er kontrollens faktiske bruk observert,
ikke bare antatt fra kode eller HTTP-status. Etterfolgende kildeutstedelse
bekreftet fortsatt eksakt tokenlikhet og B sin positive tilgang.

Mixed-token-regresjonen passerte 10 observasjoner, stromisolasjon 18 og
gammel-token/restart 17, totalt 45 ytterligere observasjoner. Rapporter:
native-source-guard-mixed-regression-results.json,
native-source-guard-stream-regression-results.json og
native-source-guard-stale-regression-results.json i bin/.
Totalt 61 rettings-/regresjonsobservasjoner; ikke et komplett ruteinventar.

## Gjenstaende grenser

Den aldri-utstedte testen provde A -> B; omvendt aldri-utstedt angrep
er ikke provd i samme test. AsyncLocal-isolering er ikke provd med
samtidige overlappende kontoer her. Bakgrunnsjobber trenger legitimt
eiergrunnlag uten HTTP-request; dette er ikke implementert/provd av denne
fixture-kontrollen. Andre native kildeinnganger/leverandorer, delte kilder,
faktisk YouTube-avspilling og fysiske klientfamilier er fortsatt uavklart.
Ingen videobytes ble overfort av denne leverandoren. Full skjerming er
fortsatt ikke bevist.

Alle friske oppsett ble ryddet med journalfort bruker-/bibliotek-readback.
bin/native-unissued-source-guard-cleanup.json bekrefter stoppet server og
fravaer av journal, fixture, guard, register og tempfil. Hovedserveren og
produksjonskoden ble ikke endret.
