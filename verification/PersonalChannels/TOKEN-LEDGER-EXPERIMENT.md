# Varig eierbinding lukker det paaviste gamle-token-hullet

Isolert Emby 4.10.1.0, 2026-10-12. Bare fixture/testprototype endret.
Ingen produksjonskode eller hovedserverkonfigurasjon endret.

## Endret binding og readback

OpenTokenOwners bruker naa SHA256 av tokenen som nokkel. Et versjonert
fixture-register lagrer hash -> bruker-GUID, ikke tokenverdi, brukernavn
eller flyktig intern bruker-ID. Registeret skrives via tempfil og rename,
og hver lagring leses tilbake og sammenlignes med alle tilsiktede oppforinger.
Det er ikke en bevist garanti mot strombrudd eller alle filsystemfeil.

Ved guard-oppstart leses schema, hashformat og GUID-format. Bruker-GUID
opploses til faktisk bruker-ID for sammenligning med autentisert konto.
Manglende bruker eller sperret oppforing far eier -1. Kodeveien for slettet
bruker er ikke runtime-provd i denne kjoringen. Native kildepreparering
oppdaterer registeret for tokenen utleveres. Foresporslens OpenToken kan
dermed gjenkjennes og avvises ogsa uten ItemId, etter en serverrestart.

Dette registeret gjelder den isolerte leverandorens tokens. Det er ikke
en komplett produksjonsdatabase for samlinger, elementer, Sync eller
alle avledede referanser.

## Faktisk gammel-token-test

Test-NativeStaleOpenToken.ps1 -RequireIsolation fullforte med exit 0 og
17 observasjoner. Rapporten bin/native-stale-open-token-persisted-results.json
har Completed=true, RestartVerified=true, LedgerHashOwnerGuidBefore=true,
LedgerHashOwnerGuidAfter=true, NoForeignMutation=true og MutationCases=0.

Testen aapnet, leste egne metadata og lukket for begge eiere for restart.
Deretter ble faktisk serverrestart verifisert med ny BootId og Ready/Enabled.
Bare A sin kilde ble klargjort i den nye prosessen, og B sin gamle token
ble brukt for B sin kilde var gjenutstedt:

| Kall med B sin gamle gyldige token | HTTP | Resultat i native stromtabell |
| --- | --- | --- |
| A konto, A private ItemId | 404 | Ingen B-provider-Open, ingen ny B-strom |
| B konto, B private ItemId | 200 | Eierens legitime strom opprettet |
| A konto, ItemId utelatt | 404 | Ingen B-provider-Open, ingen ny B-strom |

B sin gamle-token-strom hadde riktige metadata med 200 og Close=204
for kildegjenutstedelse. Senere gjenutstedelse gav eksakt samme token,
og baade B og A sine etterfolgende Open/MediaInfo/Close passerte.
Native tabell var uten fixture-strommer ved testslutt.

Registerfilen ble eksplisitt lest for og etter restart. For begge eiere
ble korrekt SHA256-nokkel og korrekt bruker-GUID kontrollert, samt at
ingen av de raa tokenverdiene fantes i filen. Tokenverdier ble ikke
vist eller skrevet til rapport. Den tidligere sideeffekt-baselinen med
15 observasjoner er beholdt i native-stale-open-token-results.json.

## Regresjon og grenser

Mixed-token-testen passerte ytterligere 10 observasjoner, og den tidligere
stromisolasjonstesten passerte 18: egen tilgang bestod, fremmed metadata,
spoofet bruker og fremmed Close ble nektet. Totalt 45 observasjoner i de
tre fullforte kjoringene. Rapporter i bin/:
native-token-ledger-mixed-regression-results.json og
native-token-ledger-stream-regression-results.json.

Dette lukker det konkret paaviste hullet for allerede utstedte tokens
fra disse to syntetiske lokale kildene. Det beviser ikke aldri-utstedte
men konstruerbare kildehenvisninger, andre native innganger/leverandorer,
samtidige registeroppdateringer over prosesser, slettet eier, korrupt
register, kildeeierskifte eller produksjonens YouTube-avspilling. Binding
av nye tokens er fortsatt knyttet til kjent elementeier og lokal kildesti.
Native offentlige kilder og delte stier trenger egne positive kontroller.
Full skjerming og all-klient-kravet er fortsatt ikke bevist.

Journalfort opprydding er utvidet til de eksakte fixture-register-/temp-
filene, med kontroll av at begge ligger i den isolerte serverroten.
Readback bekreftet at brukere/biblioteker/filer var fjernet. Den separate
bin/native-token-ledger-cleanup.json bekrefter stoppet server og fravaer
av journal, fixture, guard, tokenregister og tempfil.
