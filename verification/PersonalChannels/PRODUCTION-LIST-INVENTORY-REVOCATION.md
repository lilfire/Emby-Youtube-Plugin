# Profilsletting etter listeinventar før native query

Kontrollert på isolert Emby 4.10.1.0 den 12. oktober 2026. Hovedserveren er urørt.

## Faktisk moteksempel

NativeListInventoryGate pauser etter at produksjonens BeforeService har bygget listenes private inventar og tilgangskontekst, men før den native tjenesten/spørringen kjører. Den er begrenset til den syntetiske A-kontoen og en eksplisitt testheader, endrer ingen native verdier og har en maksimal pause på 25 sekunder.

`Test-ProductionItemLists.ps1 -InventoryRace` fullførte 41 observasjoner. Mens A sin faktiske HTTP-forespørsel var pauset, fungerte B sin liste. Deretter ble A sin profil slettet via produksjonsruten, Deleted lest tilbake og fortsatt aktiv pause/ufullført listekall kontrollert. Etter frigivelse returnerte A sin tidligere autoriserte liste 200, total=1, ett element og privat videonavn. IsolationPass=false i `bin/production-item-list-revocation-race-results.json` er et påvist brudd; Completed=true betyr at eksperimentet fullførte, ikke at skjermingen besto.

Dette viste at inventaret fra forespørselens begynnelse ikke alene kunne håndheve ferdig profilsletting før senere native query.

## Produksjonsendring

NativeBindings.ReadAccessSnapshot leser bindingene og den faktiske eierens aktuelle profilstatus/samling/generasjon uten native bibliotekoppslag. Foreign, anonym, manglende/ødelagt profil og gammel generasjon blir nektede registrerte ID-er. Profilen leses én gang for den aktuelle eieren; en fremmed eiers ødelagte profil trenger ikke leses for å nekte dens referanser.

PublicationJournal.DeniedRegisteredIds legger også registrerte Preparing-generasjoner og inkonsistent eier/samling i journalen til sperresettet. Manglende nødvendige registre eller ødelagt journal kan ikke bli en offentlig fallback.

Hver native query-prefix i produksjonens GetItems-kobling henter nå dette oppdaterte sperresettet og legger det sammen med inventarets opprinnelige sperrer før native spørring, telling og paging. Dette er en lagringsbasert kontroll uten ny native databaselesing; den åpner ikke en annen native inventarspørring inne i en eksisterende datakontekst.

## Verifisert effekt

`Test-ProductionItemLists.ps1 -InventoryRace -RequireRaceSafe` gjentar samme native pause/sletting/frigivelse og krever sikker respons. Alle 41 observasjoner fullførte. Den tidligere autoriserte listen returnerte 200, total=0 og null elementer uten privat navn. B sin egen liste hadde total=1 og ett element mens A var pauset, og B fungerer også etter sletting og omstart. Begge brukere har native EnableAllFolders=true og fixture-skjermingen er avslått i disse listemålingene.

Rapport: `bin/production-item-list-revocation-protected-results.json`, Completed=true og IsolationPass=true for den tidligere lekkende responsen.

Ni nye komponentkontroller dekker eier-/foreign-snapshot, Preparing/Active, anonymt avslag, faktisk profilsletting, B sin uendrede tilgang, gammel generasjon og ødelagt/manglende journal. Samlet komponentkjøring har 169 kontroller, Completed=true og TestDataGone=true. Et første assertion-forsøk antok feilaktig fire totale bindinger i en mappe som også inneholder tidligere komponentkontrollers bindinger; det er rettet til å sammenligne med faktisk register og de fire nye referansene. Ingen bestått garanti bygger på det forsøket.

Den eksisterende native livsløpsregresjonen `Test-ProductionNativeBindings.ps1 -PublicationJournal -ActualAccess` er kjørt med produksjonsendringen og fullførte 235 observasjoner. Den har fixture-skjermingen på og er regresjonsevidens, ikke ytterligere produksjonskrok-alene-bevis.

Opprydding er lest tilbake i `bin/production-item-list-revocation-cleanup.json`: server faktisk stoppet, native testbrukere/biblioteker/filer og alle profiler/fixturefiler/journal/modus fjernet. Den umiddelbare gamle stoppmarkøren er bevart separat fra den senere prosesskontrollen.

## Åpne tidsvinduer

Denne kontrollen lukker det påviste vinduet mellom et ferdig listeinventar og senere query for allerede registrerte referanser. Sletting etter siste kontroll mens query/resultat/byteutlevering pågår er ikke bevist sikkert. Samtidig native innsetting/reparenting av nye uregistrerte elementer etter inventaret, bruker-/tokenrevokering og andre serverinnganger krever også videre håndheving og verifisering. Det er fortsatt ingen universell garanti eller ferdig personlig YouTube-publisering/klientkjede.
