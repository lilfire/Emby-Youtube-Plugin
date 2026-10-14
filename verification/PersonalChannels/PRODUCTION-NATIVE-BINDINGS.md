# Varige native identitetsbindinger

Implementert og isolert kontrollert 2026-10-12. `PersonalYouTubeNativeBindings.cs` er produksjonskode. Den er ennå ikke koblet til produksjonens native Emby-publisering eller HTTP-håndheving. En senere [faktisk native integrasjonstest](NATIVE-PRODUCTION-BINDING-INTEGRATION.md) bruker registeret gjennom testpluginens eksperimentelle kroker. Hovedserveren er ikke endret, og produksjonens private biblioteker er fortsatt ikke aktivert.

## Identitet og lagring

En registrert native identitet består av et positivt internt heltalls-ID og en separat native GUID. Begge bindes til faktisk profileier, CollectionId og GenerationId. Verken kanal-ID, kontonavn, biblioteknavn eller fysisk foreldremappe bestemmer eierskapet. Registeret lagrer ikke API-nøkkelen.

Registrering krever et gjeldende profil-snapshot og utføres gjennom produksjonslagerets `PublishIfCurrent`, deretter en egen registerlås. Oppslag slipper registerlåsen før profilen leses, slik at låsene ikke tas i motsatt rekkefølge. Flere instanser i samme prosess deler låsene for samme lagringsmappe.

Bindinger fjernes eller overføres ikke ved sletting. Hvis Emby gjenbruker enten heltalls-ID eller GUID for en ny generasjon eller annen eier, avvises registreringen. En batch med en kollisjon lagrer ingen av sine nye referanser. Nøyaktig samme registrering er idempotent.

Registeret skrives til unik midlertidig fil, flushes og erstattes. Før første registerlagring flushes en separat markør som angir at registeret er påkrevd. Manglende påkrevd register, manglende markør for eksisterende register og ugyldig register gir feil, ikke Unknown/offentlig fallback. Markøren er en tilstedeværelsesmarkør, ikke en sjekksum. Full strømbruddsgaranti og låsing mellom separate serverprosesser er ikke bevist.

## Tilgangsavgjørelse

`Decide` skiller mellom ukjent referanse, kjent men nektet referanse og kjent referanse som tilhører den autentiserte eierens nåværende generasjon. Kjente referanser avvises for andre kontoer og anonyme. Slettet, manglende eller ødelagt eierprofil gir avslag. A sin profilfeil krever ikke lesing av B sin profil og blokkerer ikke B sitt korrekte oppslag.

Dette er en beslutningskomponent. Et Allowed-resultat er ikke en varig tilgangsbillett og låser ikke etterfølgende native utlevering mot samtidig sletting. Den fremtidige servergrensen må vurdere autoritet ved faktisk bruk. Unknown betyr heller ikke automatisk offentlig: privat innhold under oppretting må identifiseres og sperres før indeksering/utlevering. Ingen eksisterende native rute er beskyttet av denne nye komponenten ennå.

## Faktiske kontroller

`dotnet run --project verification/PersonalYouTubeStore/PersonalYouTubeVerification.csproj -c Release --no-restore` passerte først 64 kontroller: 36 lager-/publiseringskontroller og 28 registerkontroller. Senere pair-/ancestrykontroller økte totalen til 76; se [NATIVE-UNBOUND-DESCENDANT.md](NATIVE-UNBOUND-DESCENDANT.md). Rapport: `verification/PersonalYouTubeStore/bin/results.json`, Completed=true og TestDataGone=true.

Registerkontrollene bruker syntetiske native ID/GUID-par mot den faktiske produksjonsklassen. De er ikke native Emby-rutetester eller en faktisk serveromstart; gjenåpning av nye lager-/registerinstanser brukes her som persistenskontroll.

- A/B med samme kanal får separate native bindinger. Begge aliaser tillater eieren og nekter annen konto/anonym.
- Idempotens, fremmed adopsjon, kollisjon i batch og duplikater kontrolleres med uendret registerfil/ingen delvis registrering.
- Gjenåpning beholder eier og generasjon. Sletting, ny generasjon og sene registreringer kan ikke gjenåpne gamle aliaser.
- Gjenbruk av gammelt heltalls-ID eller GUID avvises; et faktisk nytt par kan registreres.
- A-korrupsjon nekter A, mens B fortsatt tillates. To samtidige eiere som registrerer samme par får nøyaktig én varig vinner.
- Manglende register, manglende markør, ødelagt JSON og duplikate persistente identiteter avvises. Gjenopprettet register beholder gamle avslag og B sin positive kontroll.

Første kjøring avdekket manglende håndtering av `InvalidDataException` ved ødelagt profil. Dette ble rettet. Den feilende testprosessen ble kontrollert mot eksakt testprogrambane og stoppet; et mellomliggende bygg med låst DLL feilet. Bare den senere fullførte kjøringen regnes som bestått.

Samme feiltype ble lagt til profil-API-ets saniterte feilhåndtering. Faktisk isolert Emby-kjøring av `Test-ProductionPersonalProfiles.ps1` passerte nå 37 HTTP-kontroller med faktisk omstart, inkludert A-korrupsjon som gir generelt 503-svar og fortsatt fungerende B-profil. Dette kontrollerer profilruten, ikke native medietilgang.

## Neste nødvendige integrasjon

Den native publiseringskjeden må registrere identitetene før noen privat referanse kan bli tilgjengelig, med varig journal for avbrutt oppretting. Serverkrokene må bruke registeret fremfor syntetiske navn og må identifisere private referanser også før registreringen er fullført. Sync, filer, åpningstokens og live-strømmer trenger egne bindinger til kilde/samling/generasjon. Den eksisterende avspillings- og alle-klientavklaringen består; denne komponenten gir ingen positiv YouTube-avspillingskontroll.
