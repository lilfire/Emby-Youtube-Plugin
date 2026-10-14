# Gammel gyldig OpenToken uten ItemId etter restart

Undersokt 2026-10-12 pa isolert Emby 4.10.1.0. Ingen produksjonsendring.

Test-NativeStaleOpenToken.ps1 fullforte med 15 observasjoner og exit 0.
Rapport: bin/native-stale-open-token-results.json, Completed=true,
RestartVerified=true, BTokenEqualsReissuedToken=true, NoForeignMutation=false,
MutationCases=1. Testen flytter ingen videobytes og bruker syntetisk lokal
leverandor, ikke dagens YouTube-kilde.

## Kontrollflyt og faktisk moteksempel

For restart fikk begge vanlige eiere native Open=200, MediaInfo=200 med
riktig privat videonavn og Close=204. Native tabell var deretter tom.
Gyldige innpakkede tokens ble beholdt bare i testprosessens minne.

Serveren ble faktisk stoppet/startet. Guard var Enabled/Ready=true med
ny BootId. Begge kontoers egne PlaybackInfo fungerte og gav nye ekte
PlaySessionId-er. Bare A sin dynamiske kilde ble klargjort, slik at native
leverandor var registrert uten at B sin token var bundet i den nye guarden.
Ingen B-provider-Open var utfort pa dette tidspunktet.

| Kall med B sin gamle token, for B sin gjenutstedelse | HTTP | B-provider-Open-delta | B-strommer i native tabell |
| --- | --- | --- | --- |
| A tokenkonto, A privat ItemId/UserId/PlaySessionId | 404 | 0 | 0 -> 0 |
| B tokenkonto, B privat ItemId/UserId/PlaySessionId | 404 | 0 | 0 -> 0 |
| A tokenkonto, A UserId/PlaySessionId, ItemId utelatt | 404 | 1 | 0 -> 1 |

Ingen av de avviste svarene inneholdt B sitt private videonavn. Det siste
kallet opprettet likevel en faktisk B-strom i native _openStreams; dette
er ikke bare en teller i testleverandoren.

Deretter ble B sin kilde klargjort igjen. Den gjenutstedte OpenToken var
eksakt lik den gamle tokenen. B kunne naa aapne med samme gamle token:
Open=200, riktig privat MediaInfo=200 og Close=204. A sin tilsvarende
positive kontroll passerte ogsa. Den gamle tokenen var dermed en gyldig
native kildehenvisning, ikke en oppdiktet ugyldig ID. Native tabell hadde
fortsatt den ekstra B-strommen etter begge eiernes normale Close.

## Hva dette viser og hva som ma endres

Den private ItemId-kontrollen av ukjent token virker for de to provde
private elementene. Den stanser ogsa midlertidig eieren selv inntil
kilden klargjores igjen; dette er ikke varig tokenkontinuitet.

Naar ItemId utelates, ser guarden ingen kjent privat elementeier og den
gamle tokenen mangler i det prosesslokale registeret. Native aapning skjer
for etterkontrollen identifiserer avviket. Etterkontrollens 404 hindrer
utlevering av responsen, men hindrer ikke sideeffekten.

Prekontrollen ma derfor identifisere privat kilde/eier uavhengig av at
kalleren leverer en gyldig privat ItemId eller at tokenen nylig er sett.
Det krever en verifiserbar token-/kildebinding som fungerer etter restart,
eller en privat tokenmodell som sikkert nekter gamle referanser for
native leverandor kan motta dem. En regel som bare nekter etter aapning
eller bare for kjent privat ItemId lukker ikke dette moteksemplet.

Dette er ikke et bevis for public-ItemId-kombinasjoner, samtidig bruk,
videooverforing, fysisk appavspilling eller produksjonens YouTube-flyt.
Full skjerming er fortsatt ikke bevist.

Testprosessens tokens ble ikke skrevet til rapport eller vist i output.
Journalfort opprydding fjernet brukere/biblioteker/filer og fixture/guard.
bin/native-stale-open-token-cleanup.json bekrefter ServerStopped,
JournalGone, FixtureGone og GuardGone. Ingen hovedserver ble endret.
