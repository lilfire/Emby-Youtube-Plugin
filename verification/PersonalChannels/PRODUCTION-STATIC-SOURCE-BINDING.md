# Binding av faktisk statisk videokilde

12. oktober 2026. Verifisert mot isolert Windows Emby 4.10.1.0 med lokale
syntetiske A/B-videoer. Eksperimentell PrivacyGuard er avslått og lest tilbake.
Dette lukker den prøvde interne filstifeilen for statisk GetVideoStream;
full skjerming og støtte for alle klienttyper er fortsatt ikke bevist.

## Feilen og endringen

Den tidligere native leseren beholdt samme mutable StaticFileResultOptions
som metadatafabrikken. Kontrollert endring av Path fra A til B etter at
leserens closure var opprettet leverte HTTP 200 og B sin SHA-korrekte prøvefil,
selv med uendrede gyldige A-video-/kilde-ID-er. Dette er intern feilinnsprøyting,
ikke et påvist angrep som en vanlig klient kan utføre.

PersonalYouTubeStaticSourceGate binder nå fabrikken til faktisk IRequest og
den tillatte kanoniske filstien under eierens tjenestesperre. Den kopierer
metadataalternativene, kontrollerer den native leserens metode og closure,
og oppretter en separat closure med en separat kopi av leseralternativene.
Leserkopien beholder den godkjente stien og ingen ContentFactory. Wrapperen
kontrollerer aktuell native eier-/kildetilgang før og etter leserdelegaten.

Fabrikkresultatet må være en FileWriter med akkurat den bundne delegaten,
eller et native EmptyHttpResult med status 304. Inner- og ytterfabrikken må
registrere samme resultatbevis. Tjenestens og skriverens kontroller binder
resultatet til samme request og eier. Ved feil avbrytes kildebeviset, åpnet
kilde/resultat kasseres, private svarheadere fjernes og generisk 404 returneres.
Eierens eksisterende skrivesperre samordner dette med profilendringer.

## Evidens og reproduksjon

`Test-ProductionVideoStreams.ps1 -InjectFactoryMismatch -RequireIsolation`
med `-MismatchVariant Full`, `Head`, `Range` og `Conditional` fullfører ti
observasjoner per variant. Rapportene er henholdsvis
`bin/production-static-factory-mismatch-protected-results.json`,
`bin/production-static-factory-mismatch-head-results.json`,
`bin/production-static-factory-mismatch-range-results.json` og
`bin/production-static-factory-mismatch-conditional-results.json`.

Alle fire rapporter bekrefter faktisk Injected=1, HTTP 404, ingen entityheadere,
ingen B-fil i svaret og IoCallsDelta=0. Generisk kropp er 15 byte, eller null
byte for HEAD. B sine fem tillatte stream-varianter fungerer fortsatt.
IoCalls teller bare kall til den bundne native leserdelegaten; det er ikke
en måling av all filsystemaktivitet. Denied teller avslag i flere lag og
skal ikke tolkes som antall unike forespørsler.

`-TraceStaticFactory -RequireIsolation` fullfører 67 observasjoner i
`bin/production-static-factory-trace-results.json`. Tracen kontrollerer nå
separate metadata-/leseralternativer og riktig native lesermetode. Den gamle
tracen med delt mutabelt objekt er bevart separat i
`bin/native-static-factory-before-source-binding-results.json`.

Tidlige forsøk som feilet før mutasjonen, med Injected=0 og Completed=false,
er ikke regnet som passering. Fixture-instrumenteringens object[] __args
skrev tilbake gamle argumenter etter produksjonens kopiering. Instrumenteringen
leser nå det levende __1-argumentet uten å erstatte det.

De fire statiske stream-/profilslettingstestene fullfører 76 observasjoner
hver. Regresjonene for matching-ETag-nedlasting og GET PlaybackInfo fullfører
henholdsvis 83 og 75 observasjoner. Komponentkontrollene passerer 186 kontroller.
Rapportenes Completed og faktiske observasjoner er lest tilbake; testantall
erstatter ikke kontroll av hva hver test dekker. Listeskrivesperrens regresjon
fullfører også 44 observasjoner: sletting venter ved eierens sperre, B sin
profilendring virker, og slettet A er skjult etter sletting og faktisk omstart.

Opprydding er lest tilbake i
`bin/production-static-source-binding-cleanup.json`: syntetiske kontoer,
biblioteker, prøvefiler og fixture er fjernet; profiler/journaler er borte
og den isolerte serverprosessen er faktisk stoppet. Den tidligere umiddelbare
ServerStopped=false er beholdt separat fra den senere FinalServerStopped=true.

## Avgrenset native kontrakt

Produksjonen krever eksakte typer, felt, delegatidentiteter og metodekropper:

| Metode | SHA-256 av IL |
| --- | --- |
| GetStaticFileResult(IRequest, StaticFileResultOptions) | 2F31DF16E9D4669F8D95C3945A1D88A705DF182AF7635397030FD0D061C8A782 |
| GetStaticResult(IRequest, StaticResultOptions) | 4C716F3B7CB1817B7B1B25FD24854AF16614FA227E09B1DA38D5F22A545ACB11 |
| Native leserdelegat GetStaticFileResult b__0 | 6EF1D70DA9C84A39140CC50C0166C4A8A9670A07ED10ECB324632061E649FC1B |

Snapshot kontrollerer at begge fabrikkers prefix/postfix/finalizer fortsatt
er installert. Native closure skal ha akkurat options og fabrikkinstansen.
Dette er verifisert for den isolerte Windows-builden; Linux/Docker eller andre
builds er ikke dermed godkjent. Videre I/O-kall under leserdelegaten er ikke
uavhengig pinnet eller ferdig auditert.

## Åpne beviskrav

Dynamiske/live/transkodede private videokall avvises fortsatt og må få
fungerende sikker kildebinding for avtalt klientstøtte. Audio, HLS, bilder,
undertekster, sync/offline, øvrige ruter og faktiske YouTube-kilder gjenstår.
Native mutasjoner, bruker-/tokenrevokering, kildeendringer etter åpning,
lange overføringer, cachegrenser og alle faktiske klientfamilier er ikke
fullt verifisert. Fjerning av headere før feilsvar er ikke bevis for at allerede
sendte byte/headere kan trekkes tilbake. Ingen utrulling til hovedserveren
er utført i denne runden.
