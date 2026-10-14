# Betrodd kontekst for native oppretting

Implementert og isolert kontrollert 12. oktober 2026. Hovedserveren er urørt.

## Produksjonskomponent

`PersonalYouTubeNativeCreation` åpner en intern, synkron opprettingskontekst fra et faktisk Prepared-profilsnapshot. Den interne mediestien kommer fra journalens eier/samling/generasjon. Native CreateItem-koblingen kan reservere rotens faktiske GUID før innsetting uten å utlede eier fra biblioteknavnet eller en innsendt UserId.

Konteksten gjelder én rot, én tråd og den oppgaven som åpnet den. Den flyter ikke med AsyncLocal eller ExecutionContext. En eksplisitt Task som kjøres på samme tråd har også en annen Task.CurrentId og avvises. Vanlig native oppretting uten en personlig kontekst får ingen privat autoritet. Feil innen en personlig kontekst må avbryte opprettingen, ikke ignoreres.

Open krever Preparing uten en eksisterende rotreservasjon. En delvis oppretting må derfor gjenopprettes fremfor å forsøke en ny rot med annen identitet. Complete krever positiv faktisk native ID og identisk reservert GUID. Den aktiverer ikke biblioteket. Dispose fjerner konteksten, men beholder en eventuell varig sperre. Senere binding/aktivering har sine egne kontroller mot gjeldende generasjon.

Dette er produksjonskode uten en produksjonsinstallerte native kroker eller en ferdig bibliotekpubliserer. Konteksten forutsetter den verifiserte synkrone AddVirtualFolder-kjeden. En fremtidig asynkron native oppretting må få en ny eksplisitt kontrakt; det er ikke autorisert ved å flytte denne konteksten til en annen tråd.

## Verifisering

Komponentkjøringen har nå 150 beståtte kontroller, Completed=true og TestDataGone=true. De 20 nye kontrollene undersøker blant annet manglende kontekst, nesting, separat/inlinet Task, feil eller manglende rotreservasjon, avslutning/replay, stale snapshot og to samtidige opprettere for samme generasjon. To faktiske dedikerte tråder åpner kontekstene før en felles frigivelse; kun vinneren av den varige GUID-reservasjonen når den simulerte native mutasjonen. Dette er komponentbevis, ikke to samtidige native Emby-opprettinger.

Det første forsøket med bare trådbinding feilet på en detached Task: .NET kunne kjøre den ventende oppgaven på den samme tråden. Oppgaveidentitet ble lagt til, og en deterministisk RunSynchronously-kontroll bekrefter avslag også ved dette tilfellet. Ingen bestått kontekstgaranti bygges på den feilende kjøringen.

Fixture-ruten NativeContextCreate er administrasjonsbeskyttet og begrenset til den syntetiske A-kontoen. Den åpner produksjonskonteksten og kaller faktisk ILibraryManager.AddVirtualFolder. En eksperimentell CreateItem-prefix reserverer GUID gjennom produksjonskonteksten for CollectionFolder, uten å se på navnet. Timing-postfix bruker bare den eksakte syntetiske roten for å holde opprettingen pauset. Den tidligere navnebaserte reservasjonsgrenen er slått av i denne kjøringen.

`Test-NewUnregisteredPrivateRoot.ps1 -InFlight -CreationContext` fullførte 35 observasjoner:

- Faktisk rot finnes i databasen mens opprettingen venter, Locations er tom og GUID-en finnes varig i Preparing-journalen.
- A og B har native EnabledFolders på roten, men begge metadataaliasene gir 404 uten privat navn og begge biblioteklister skjuler roten.
- Preparing-avslag består etter retur og faktisk serveromstart.
- Samme rot gir 200 til A og 404 til B etter eksplisitt registerbinding og aktivering. B sitt eksisterende videoinnhold fungerer med riktig filhash.

Rapport: `bin/native-creation-context-results.json`, Completed=true, RestartVerified=true og seks beståtte kontroller i pausen. `bin/native-creation-context-cleanup.json` er lest tilbake med alle fem kontrollene true: stoppet server og fjernet klientjournal, profiler, fixture-DLL og modusfil.

## Fortsatt åpent

Personlig produksjonspubliserer, source-directory-validering, native oppstartskontrakt og universell tilgangshåndheving er ikke installert. Krasj/recovery, avledede referanser og faktisk YouTube-kjede/klientkompatibilitet gjenstår i fullskjermingsplanen. Denne kontrollen erstatter ikke disse kravene.
