# OpenToken ma kontrolleres for native aapning

Undersokt 2026-10-12 pa isolert Emby 4.10.1.0. Bare fixture/prototype endret.

## Nytt moteksempel mot bare etterkontroll

Test-NativeMixedOpenToken.ps1 kombinerte innlogget konto A sin ItemId,
UserId og PlaySessionId med B sin gyldige native OpenToken, deretter
omvendt. Aapningsreferansene ble klargjort av samme avgrensede lokale
leverandor som tidligere stromtester; begge eieres vanlige native Open
gav 200, og faktisk _openStreams-tabell hadde en strom for hver eier.

Begge blandede kall fikk 404 uten fremmed videonavn i svar, men:

- Fremmed leverandors OpenMediaSource ble kalt en ekstra gang.
- Native _openStreams fikk en ekstra strom for den fremmede videoen.
- Begge eiernes opprinnelige metadata forble tilgjengelige med 200.
- Etter at begge eiere lukket sine egne strommer med 204, stod den
  ekstra fremmede strommen igjen for hver eier i native tabell.

Dette er en konkret sideeffekt av fremmed aapning selv om svaret avvises.
Baseline er bevart i bin/native-mixed-open-token-results.json med exit 0,
Completed=true, 10 observasjoner, NoForeignMutation=false og MutationCases=2.
Det er ikke bevis for videobytes eller dagens YouTube-flyt.

Den adminbeskyttede read-only NativeFixtureStreamActivity-proben leste
native _openStreams som faktisk finnes pa serveren. Bare antall strommer
per syntetisk videonavn og leverandorens Open/Close-tellere ble returnert.
Ingen strom-ID-er, tokens, stier eller private brukerdata ble hentet av
denne aktivitetsproben. Leverandortellerne alene erstatter ikke tabell-
kontrollen; begge ble sammenlignet for/etter de konkrete kallene.

## Avgrenset forhåndskontroll i testprototypen

PrivacyGuard observerer naa den native GetDynamicMediaSources-overlasten
som klargjor kilde og innpakket OpenToken. Private elementers tokens
bindes til eieren for resultatet utleveres; en kilde med avvikende sti
eller eierkonflikt far sperret eier -1. OpenToken inngar deretter i
referansekontrollen mot autentisert konto, bade i query og DTO.

For native OpenMediaSource med kjent privat ItemId kreves dessuten en
allerede bundet token med samme eier. Ukjent/manglende token blir avvist
for tjenesten starter. Den tidligere LiveStreamId-bindingen beholdes
som egen kontroll for senere metadata/lukking.

Forste kjoring av det utvidede testskriptet hadde en PowerShell-parserfeil
i et flersidig if-uttrykk. Dette ble rettet for noen testkall ble utfort;
parserfeilen teller ikke som et native tilgangsresultat.

## Verifiserte resultater for/etter restart

- Mixed-token-testen fullforte med exit 0 to ganger, 10 observasjoner
  hver. Alle fire blandede kall fikk 404, ingen privat markor, ingen
  ekstra fremmed provider-Open og ingen endring i fremmede native strommer.
- Egne Open=200, egne metadata=200 etter begge angrepsforsok, egne Close=204.
  Etter egen Close var native tabell uten fixture-strommer begge ganger.
- Den tidligere stromisolasjonstesten passerte med 18 observasjoner
  hver gang: fremmed metadata, spoofet UserId og fremmed Close ble nektet,
  eierens tilgang bestod og anonym body-foresporsel gav 401.
- Restart var verifisert med ny BootId og Enabled/Ready=true. Det ble
  opprettet nye strommer og klargjort nye tokenbindinger etter restart.

Totalt 56 observasjoner i disse fire fullforte rettingskjoringene.
Rapporter: native-mixed-open-token-prechecked-before-restart-results.json,
native-mixed-open-token-prechecked-after-restart-results.json,
native-open-token-stream-regression-before-restart-results.json og
native-open-token-stream-regression-after-restart-results.json i bin/.

## Gjenstaende bevisgrenser

Denne testen brukte kjente, utstedte private tokens og to syntetiske
lokale kilder. Den beviser ikke alle alternative kildeleverandorer,
public-ItemId/ukjent-token-kombinasjoner, gamle tokens etter restart,
garantier for delte kildestier eller samtidig aapning/lukking. Kontrollen
av ukjent token for privat ItemId finnes i kode, men ble ikke runtime-
provd separat her. Bindingsregisteret er prosesslokalt, ikke en varig
produksjonsmodell. Ingen faktisk YouTube- eller TV-/mobilavspilling ble
provd. Full skjerming er fortsatt ikke bevist.

Baseline- og rettingsmiljoene ble ryddet med journalfort kontroll av
brukere/biblioteker/filer. Den separate etterkontrollen
bin/native-open-token-precheck-cleanup.json bekrefter ServerStopped,
JournalGone, FixtureGone og GuardGone. Ingen hovedserver ble endret.
