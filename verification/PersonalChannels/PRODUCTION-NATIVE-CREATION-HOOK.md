# Produksjonskrok for native oppretting

Implementert og kontrollert på isolert Emby 4.10.1.0 den 12. oktober 2026. Hovedserveren er urørt.

## Oppstart og kontrakt

PluginEntryPoint installerer nå PersonalYouTubeNativeCreationHook ved oppstart, før de eksisterende oppstartsarbeidene. Koden bruker pluginens innebygde Harmony via refleksjon. Den krever faktisk LibraryManager-type, eksakte argument-/returtyper og de målte SHA-256-fingeravtrykkene av begge AddVirtualFolder-overloadene og CreateItem. Fingeravtrykkene kommer fra IL i den faktisk lastede isolerte serveren og er lagret i `bin/native-creation-il.json`.

En annen metodekropp godkjennes ikke bare fordi versjonsnummer eller metodeform stemmer. Uverifisert kontrakt gir personlig oppretting utilgjengelig. Dette godkjenner ikke andre serverbuilds eller plattformbinarier; de må undersøkes separat. Det er ingen automatisk oppretting av personlige biblioteker ennå, og eksisterende globale YouTube-funksjoner får ingen ny personlig autoritet av denne kroken.

Kroken kjører før faktisk CreateItem og reserverer CollectionFolder-GUID gjennom den gjeldende produksjonskonteksten. Den bruker ingen fixture-navn, OwnerUserId fra klienten eller testfil for eieravgjørelsen. Ingen kontekst betyr ingen privat reservasjonsautoritet. En reservasjonsfeil i personlig kontekst får propagere og må avbryte native oppretting.

Install og RequireAvailable kontrollerer den faktiske Harmony-prefixen, både eier-ID og patchmetode. Snapshot undersøker også at prefixen fortsatt finnes; bortfall rapporteres som PatchLost, fremfor å gjenta en foreldet Installed=true. Den eksperimentelle CreateItem-prefixen i NativeCreationGate reserverer ikke lenger via produksjonskonteksten. Den kan fortsatt brukes til den særskilte tidligere navnebaserte regresjonskontrollen, men den grenen er av i konteksttesten. Produksjonskroken beholdes for prosessens levetid.

## Faktisk native kontroll

`Test-NewUnregisteredPrivateRoot.ps1 -InFlight -CreationContext` fullførte 37 observasjoner. De to nye observasjonene leser produksjonskrokens installasjon ved første oppstart og faktisk omstart. Den faktiske GUID-reservasjonen mens native CreateItem er pauset kommer nå fra produksjonspluginens prefix, ikke fixture-reservasjon. Alle seks tilgangskontroller i pre-source-pausen passerte. Etter registerbinding og aktivering fikk A den samme roten, mens B ble nektet. B sitt eksisterende innhold fungerte med korrekt filhash.

Rapport: `bin/native-production-creation-hook-results.json`, Completed=true og RestartVerified=true. Universell metadata-/filhåndheving kommer fremdeles fra den eksperimentelle testbroen; dette er ikke bevis for ferdig produksjonstilgang.

`Test-NativeCreationHookLoss.ps1` fjernet bare prefixen med produksjonens egen Harmony-ID på den isolerte serveren. Faktisk RequireAvailable feilet, Snapshot viste PatchLost, og den administrative testens personlige opprettingskall ble avvist før profilmappen/journalen eller en native rot ble opprettet. B sine egne metadata og videonedlasting virket før og etter prefixbortfall samt etter faktisk omstart, med identisk filhash. Omstart installerte produksjonsprefixen på nytt, og RequireAvailable besto igjen.

Denne kjøringen fullførte 16 observasjoner, rapport `bin/native-creation-hook-loss-results.json`. Det første forsøket hadde feil HTTP-verbliste på testproben og stoppet på 404 før prefixen ble fjernet. Den ufullførte rapporten er bevart som `bin/native-creation-hook-loss-route-incomplete.json`; den teller ikke som en bestått kontroll. Testproben er rettet til GET,POST.

Etter kjøringene er `bin/native-production-creation-hook-cleanup.json` lest tilbake med alle fem kontrollene true: server stoppet, klientjournal, profiler, fixture-DLL og modusfil fjernet. Komponentgrunnlaget er 150 beståtte kontroller fra forrige kontekstkjøring.

## Gjenstående krav

Dette er produksjonens opprettingskrok, ikke hele tilgangsgrensen. En personlig publiserer må kreve tilgjengelig krok før å åpne kontekst, validere de faktiske interne mediemappene, binde alle native elementer og aktivere først etter dette. Universell tilgangshåndheving, ufullført publisering/gjenoppretting, avledede filer/strømreferanser, egen API-jobbkjede og faktisk YouTube-avspilling/klientverifisering står fortsatt åpne i fullskjermingsplanen.
