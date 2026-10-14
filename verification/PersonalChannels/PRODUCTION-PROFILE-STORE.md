# Første produksjonskomponent: personlig profillagring

2026-10-12. Brukeren autoriserte «Tillat implementering etter planen», med isolert verifisering først. [PersonalYouTubeStore.cs](../../PersonalYouTubeStore.cs) er nå en del av produksjonsprosjektet. Dette er en byggestein, ikke en ferdig personlig YouTube-funksjon eller et bevis for full skjerming.

## Implementert

- Separat dokument per stabil bruker-GUID, uavhengig av kontoens navn.
- Egen samlings-ID og generasjons-ID, begge uavhengig av YouTube-/native-ID-er.
- Tilstander Absent, Draft og Deleted. Komponenten publiserer ingen biblioteker eller medier.
- Persistente revisjoner som hindrer at konkurrerende gamle oppdateringer overskriver nye data.
- Sletting rydder kanalvalg/nøkkel og invalidiserer tidligere snapshot. Gjenoppretting bevarer samlings-ID, oppretter ny generasjon og bevarer gammel generasjon som slettet historikk.
- AES-GCM med eier, samling, generasjon og nøkkelrevisjon som autentiserte tilleggsdata. Vanlig View har nøkkelstatus og aldri lagret nøkkel.
- Krypteringsnøkkel mangler/er ugyldig: avslag fremfor automatisk ny nøkkel når profiler allerede finnes.
- Eksplisitt serverinternt requestsnapshot og kontroll av om revisjon/generasjon fremdeles gjelder. `IsCurrent` alene er ikke en atomisk publiseringsgaranti. `PublishIfCurrent` kontrollerer og utfører en kort, synkron serverintern publisering under samme prosesslås som Save/Delete, også mellom flere lagerinstanser for samme mappe.
- Filen skrives først til unik midlertidig fil, flushes og erstatter deretter profildokumentet. Ingen garanti om full holdbarhet ved vilkårlig strømbrudd eller samtidige separate serverprosesser er bevist.

Servernøkkelen ligger i den servereide lagringsmappen. Krypteringen beskytter ikke mot en administrator som kontrollerer både nøkkel og profildata; den avklarte skjermingen gjelder vanlige Emby-kontoers servertilgang. Ingen faktisk bruker- eller API-nøkkel ble brukt i testen.

## Verifisering

`dotnet run --project verification/PersonalYouTubeStore/PersonalYouTubeVerification.csproj -c Release --no-restore` bestod 36 lagerkontroller på den faktiske produksjonsklassen (først 26, deretter ti nye publiserings-/racekontroller). Den samme kjøringen inkluderer nå også 40 [native bindingskontroller](PRODUCTION-NATIVE-BINDINGS.md) og 42 [journal-/kildestedskontroller](PRODUCTION-PUBLICATION-JOURNAL.md), totalt 118. Rapport: `verification/PersonalYouTubeStore/bin/results.json`, Completed=true og TestDataGone=true.

Kontrollene omfatter separat eier/samling ved samme kanal, riktig nøkkeldekryptering, ingen klartekstnøkkel i profilfil eller View, gamle revisjoner, ugyldige kanal-/nøkkeloppdateringer, kopiert kryptert nøkkel mellom eiere og generasjoner, gjenåpning av lagringen, sletting/gjenoppretting og beholdt historikk. Tolv konkurrerende oppdateringer med samme revisjon ga nøyaktig én vinner. A-korrupsjon blokkerte ikke B; tap av krypteringsnøkkel endret ikke B sin profil og skapte ingen ny nøkkel.

Produksjonsprosjektet bygget uten advarsler eller feil. Den første testkjøringen hadde NU1900 fordi sandbox-nettverket ikke kunne hente NuGet-sårbarhetsdata. Etter godkjent nettverkstilgang fullførte `dotnet restore verification/PersonalYouTubeStore/PersonalYouTubeVerification.csproj --force-evaluate` uten advarselen. Syntetiske testdata ble slettet med readback.

## Neste integrasjon og grenser

Et requestsnapshot kan være gyldig under `IsCurrent`, men utdatert når et sent nettverkssvar skal publiseres. De nye testene utfører faktisk nøkkelrotasjon etter den foreløpige kontrollen og verifiserer at `PublishIfCurrent` ikke kaller publiseringsfunksjonen. Det samme gjelder slettet generasjon, ny generasjon og senere endring av kanalvalg. En ødelagt profil gir avslag før publiseringsfunksjonen; B beholder positiv kontroll.

I den samtidige testen pauses en gyldig publiseringsfunksjon inne i produksjonens kritiske seksjon. En annen oppgave signaliserer at den starter Save på en separat lagerinstans, og forblir uferdig mens publiseringen er pauset. Etter eksplisitt frigjøring fullfører publiseringen, deretter profilendringen. Det gamle snapshotet kan ikke publisere på nytt. Ventingen er begrenset; testdata ble fjernet.

Dette er en prosesslokal serialiseringsgaranti for den synkrone publiseringsfunksjonen. Funksjonen må ikke starte nettverksarbeid eller utsette publisering til senere. Den er ikke en transaksjon over native Emby-data og profilfiler, gir ingen automatisk tilbakeføring ved feil og er ikke en native tilgangsavgjørelse. Eksisterende YouTube-jobber er ikke koblet til denne grensen ennå. Varig publiseringsjournal, native referansebinding og gjenoppretting er fortsatt nødvendige før private biblioteker aktiveres.

Komponenten er koblet til autentiserte [produksjonsprofilruter](PRODUCTION-PROFILE-SERVICE.md), med 35 faktiske HTTP-kontroller i isolert Emby, og en [verifisert brukermeny](PRODUCTION-PROFILE-UI.md). Faktisk API-arbeid, native bibliotekbinding, strømmer, Sync og filopprydding gjenstår. Den eksisterende globale funksjonen bruker fortsatt sitt eksisterende oppsett. Ingen hovedserver er endret eller ny DLL deployert der.

Neste steg er isolert produksjonsarbeid mot den personlige profilen og varig publiseringsbinding. Native publisering må vente på en virksom tilgangsgrense og mediekjede. Planens avspillings-, identitets-/race- og alle-klientbevis er fortsatt åpne.
