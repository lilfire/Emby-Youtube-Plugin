# Nytt native element uten egen binding

Kontrollert 2026-10-12 på isolert Emby 4.10.1.0. Dette utvider [testen av produksjonsbindinger](NATIVE-PRODUCTION-BINDING-INTEGRATION.md); håndhevingen er fortsatt testpluginens eksperimentelle kroker. Produksjonens native publisering/håndheving og faktisk YouTube-avspilling er ikke levert.

## Endringen

`PersonalYouTubeNativeBindings.DecideItem` tar et faktisk native heltalls-ID/GUID-par og faktiske forfedre fra serveren. Disse skal aldri komme som tilgangsgrunnlag fra klientens forespørsel.

- Et uregistrert element under en registrert privat forfader avvises også for eieren. Det kan ikke arve en tillatelse før egen binding er varig registrert.
- Et kjent element krever samsvar mellom begge sine faktiske native identiteter og bindingen. Gjenbruk av ett alias med et annet faktisk motstykke avvises.
- Registrerte forfedre må samsvare med eier, samling og generasjon. En gammel binding overføres ikke ved at serveren nå viser annen ancestry.
- Et uregistrert element uten noen kjent privat binding i ancestry returnerer fortsatt Unknown. Privat oppretting før første binding og tap/flytting av ancestry trenger derfor fortsatt publiseringsjournal/proveniens; dette er ikke løst av metoden alene.

Den isolerte broen får faktiske elementer fra `ILibraryManager`, samler native samlingsrøtter og fysisk foreldrekjede, og kaller den innlastede produksjonsmetoden. En nektet kjent privat etterkommer overstyrer testprototypens tidligere eierkart.

## Faktisk serverkontroll

`Test-ProductionNativeBindings.ps1 -UnboundDescendant` fullførte med **81 observasjoner**: 76 HTTP-kontroller og fem native registrerings-/tilstandskontroller. Dette inkluderer den tidligere 51-observasjonstesten og 30 nye observasjoner. Rapport: `bin/production-native-binding-unbound-descendant-results.json`, Completed=true, RestartVerified=true og UnboundDescendant=true.

Etter at A/B sine opprinnelige native identiteter var registrert, ble `PrivateNativeVideo_a_grown.mp4` opprettet som en journalført prøvefil og faktisk innskannet av Emby. En direkte administrasjonsprobe bekreftet nytt video-ID/GUID. Produksjonens registerfil ble lest og bekreftet at ingen av aliasene var registrert der.

Det nye elementets metadata via begge aliaser ga 404 for A og B. A/B/anonyme nedlastinger ga 404 og null bytes. A sin aktive videoliste viste den opprinnelige registrerte videoen, men skjulte det nye elementet. B beholdt sine opprinnelige positive kontroller.

De nye direkte kontrollene ble gjentatt etter profilsletting, faktisk serveromstart med ny BootId/Ready, og gjenoppretting av profilen med ny generasjon. Det nye elementet forble nektet i alle fasene. Listene viste ingen uregistrerte private navn. Tidligere registrerte A-referanser forble nektet etter sletting, mens B sin metadata, liste og SHA-korrekte filnedlasting fortsatt fungerte.

## Komponentkontroller og grenser

Produksjonskomponentenes verifisering fullførte nå med **76 kontroller**: tidligere 64 og tolv nye pair-/ancestrykontroller. Disse to kontrolltallene gjelder ulike kjøringer: komponenttesten er ikke en HTTP-test.

De tolv nye kontrollene dekker uregistrert privat etterkommer, ukjent offentlig kontekst, faktisk par, fremmed/gammel-generasjons ancestry, aliasgjenbruk og positiv kontroll etter registrering av både ny forfader og etterkommer fra samme generasjon. Rapporten `verification/PersonalYouTubeStore/bin/results.json` har Completed=true og TestDataGone=true.

Dette løser én konkret beslutningsvariant og verifiserer dens integrasjon gjennom testkrokene. Det beviser ikke at alle native innganger før første registrering går gjennom metoden, at ancestry alltid er tilgjengelig, eller at ingen annen API-kjede kan utlevere privat innhold. Varig opprettingsjournal, native produksjonskroker, avledede referanser og faktisk YouTube-/klientkontroll gjenstår.

Testkontoer, biblioteker, begge prøvevideoer, profiler/register, modusmarkør og testplugin ble ryddet. Uavhengig sluttkontroll i `bin/production-native-binding-unbound-descendant-cleanup.json` har alle ni felt true, inkludert stoppet server. Hovedserveren er ikke endret.
