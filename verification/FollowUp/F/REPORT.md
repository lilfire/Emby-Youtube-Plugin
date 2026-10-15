# F — profiler, nøkler og brukeridentitet

Undersøkt 2026-10-14. Produksjonskode og Lilflix er uendret. Undersøkelsen er
utført; full godkjenning av F er fortsatt åpen for punktene nedenfor.

## Miljø og faktisk testinngang

- Commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`, versjon `2.0.10-alpha.1`.
  Produksjons-DLL SHA256
  `AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
  Lokale endringer fra andre kapitler i testfixture var allerede til stede;
  dette er ikke en påstand om et rent checkout.
- Native integrasjon: Windows x64, isolert Emby **4.10.1.0**, to faktiske vanlige
  kontoer, faktisk HTTP-autentisering, produksjonens `PersonalYouTubeService`,
  `Store`, `Jobs`, `JobRuntime`, `Catalog`, buffer, native publisering og tilgangskroker.
  Fixture-DLL SHA256
  `F890627BFB0BD1438536C7C4EF2D79A75CDFB5B195228C30F19D143C22EFD0FD`.
- Testadapter: eksisterende `ProductionBufferedPublication` starter produksjons-
  arbeideren med syntetiske Google-katalogsvar og begrenser utvalget til én video.
  Faktisk yt-dlp/Node/FFmpeg-medieuthenting og native avspilling kjøres.
  Dette er **ikke ekte Google Data API**, en fysisk klienttest eller normal
  automatisk arbeideroppstart fra plugin-konfigurasjonen.
- Lager/katalog: eget kjørbart testprogram refererer samme produksjons-DLL,
  uten kopiert lagerimplementasjon. Windows .NET 8 og Linux x64 self-contained
  .NET 8 i lokal Emby-containerimage, nettverk deaktivert, UID 0, umask `0022`.
  Linux kjører **ikke Emby-serveren**. Testcontaineren får kun testprogrammets
  publiserte filer som skrivebeskyttet mount; ingen serverdata eller nøkler.
  Image-ID og hashes finnes i [STORE-METADATA.json](STORE-METADATA.json).
  Image har loader i `/lib`; testcontaineren får en `/lib64`-symlink for apphost.

## Resultater

| Område | Resultat | Bevis og begrensning |
|---|---|---|
| Identisk nøkkel og kanal, to eiere | Bestått i komplett prøvd kjede | Separate samlinger, generasjoner, jobber og native røtter. Begge eierstrømmer ga 200 og 565499 bytes; fremmedstrømmer 404. |
| Deaktivert konto | Bestått for nye forespørsler | Policy lest tilbake. Alle fem profil-/diagnostikkruter ga 401, også gyldige og ugyldige skrivebodyer. B-strømmen virket mens A var deaktivert. Reaktivert A fikk positiv avspilling. |
| Native tokenrevokering | Bestått for prøvd sesjon | Faktisk `Auth/Keys`-sletting. Alle rutene avviste gammel token med 401. Ny A-token ga fungerende eieravspilling. |
| Kontosletting, samme navn med ny GUID | Tilgangsprøver bestått; fysisk oppbevaring påvist | Gammel konto fraværende ved native readback. Gamle sesjoner ga 401. Ny konto fikk Absent/revisjon 0/ingen nøkkel; gammel video ga 404. B beholdt profilhash og avspilling. Gammel A-profil og mediemappe ble liggende. |
| Manipulert identitet | Bestått for fem deklarerte ruter | GET MyProfile/MyJob med B-identitet returnerte autentisert A. Fremmed eierfelt i begge POST-bodyer ga 400. Vanlig bruker fikk 403 på PersonalServerStatus; administrator fikk 200. Anonym fikk 401. B-profilhash uendret. |
| Profil-/nøkkelendring under native publisering | Bestått i prøvd interleaving | Testens timingkrok pauset faktisk native root-insert. Samtidig HTTP-save med nye kanaler og nøkkeloppdatering ventet på eierlease. B-avspilling fungerte. Etter frigjøring publiserte siste revisjon; mellomgenerasjonens rot og mediemappe ble fjernet. Nøkkeloppdateringen bruker samme syntetiske nøkkelverdi, men øker nøkkelrevisjonen. |
| Sent katalogsvar | Bestått på produksjonslager/katalog | Handleren pauser et faktisk katalogkall ved playlistItems. Separat lagerinstans roterer nøkkelverdi, endrer kanaler eller sletter profil. Det frigitte svaret avvises, og PublishIfCurrent kaller ikke publiseringscallback. B beholder nøkkel og fil. Dette er en komponentprøve, ikke forsinket transport gjennom native serverarbeider. |
| Korrupt kryptert data | Bestått på lageret | Endret GCM-ciphertext kan ikke dekrypteres; B virker. Tom eller tilfeldig 32-byte servernøkkel gir avslag. Ingen hemmeligheter i portable bevis. |
| Nøkkeltap og gjenoppretting | Avslag og restore-grense bekreftet | Manglende nøkkel gir avslag og regenereres ikke ved eksisterende profiler. Matchende nøkkelbackup gjenoppretter dekryptering. Tilbakelegging av gammel profil og riktig nøkkel gjør gammelt snapshot gyldig igjen i lageret. Ingen varig beskyttelse mot slik rollback er bevist. |
| Prosess-/instansgrenser | Flerprosessbegrensning reprodusert | En separat prosess lagrer A mens forelderen holder PublishIfCurrent-låsen inne i callback. Forelderens publisering returnerer true selv om snapshot deretter er foreldet. B-filen er uendret. Låsen beskytter bare instanser i samme prosess; unik tempfil/rename er ikke en flerprosesstransaksjon. |
| Filrettigheter | Ingen eksplisitt hardening; brede lokale rettigheter målt | Linux-lageret opprettet mappe 0755 og nøkkel/profiler 0644 ved umask 0022. Windows-produksjonsnøkkelen arvet BuiltinUsers ReadAndExecute og AuthenticatedUsers Modify fra testmiljøet. Ingen faktisk annen OS-kontos leseforsøk ble kjørt. |

[INTEGRATION-EVIDENCE.json](INTEGRATION-EVIDENCE.json) har 58 observasjoner,
Completed=true. Alle observasjoner med eksplisitt Passed er true; tallet
inkluderer baselineobservasjoner og målinger av oppbevaring, ikke 58 bevis for
universell skjerming. [WINDOWS-STORE-EVIDENCE.json](WINDOWS-STORE-EVIDENCE.json)
har 21 beståtte lager/katalogkontroller. [LINUX-STORE-EVIDENCE.json](LINUX-STORE-EVIDENCE.json)
har de samme 21 beståtte kontrollene og én filmodusmåling. Begge har
Completed=true og TestDataGone=true. [WINDOWS-PERMISSIONS.json](WINDOWS-PERMISSIONS.json)
inneholder sanitert ACL-måling uten lokale kontonavn eller SID-er.

Eksisterende `PersonalYouTubeVerification`-regresjon fullførte 213 kontroller
på aktuell produksjonskode. Bygg av plugin og eksisterende fixture fullførte
uten feil eller advarsler. Summene er ikke et samlet sikkerhetssertifikat.

## Påviste grenser og konkrete integrasjonsforslag

1. **E/G: fysisk opprydding etter kontosletting.** Profilen beholder kryptert
   nøkkel, og mediefiler blir liggende etter native kontosletting. Nye HTTP-kall
   avvises i prøven. Legg til varig kontolivssyklusbehandling som trekker tilbake
   generasjoner og rydder bare den slettede eierens journal, jobber, staging og
   native data. Prøv omstart/recovery og B-kontroll. Testopprydding er ikke
   produktets opprydding.
2. **F/J: lagringsrettigheter og backup.** Store bruker vanlige CreateDirectory/
   FileStream og arvede rettigheter. Linux 0644 betyr ikke OS-eierisolering når
   foreldrestien er traverserbar. Windows-funn gjelder testmaskinens arvede ACL,
   ikke alle installasjoner. Bestem støttet serverkonto og håndhev/valider
   privat profilmappe og nøkkel (typisk 0700/0600 på Unix og eksplisitt begrenset
   ACL på Windows), også for eksisterende installasjoner og backup. Gjør det
   sammen med J før en driftsgaranti gis. Ikke bytt global nøkkel i eksisterende
   profiler uten versjonert migrering og kontrollert rollback.
3. **E/F: samlet restore-kontrakt.** Lagerets revisjon er inne i den gjenopprettede
   JSON-filen, uten ekstern anti-rollback-epoke. Et gammelt profil-/nøkkelpar kan
   derfor ikke avvises ut fra lageret alene. Prøv profil, nøkkel, journal,
   bindingsdata og native bibliotek samlet; definer mismatch og samme GUID
   gjenopprettet. Dagens test av ny GUID beviser ikke dette.
4. **F/G/J: én skriver per datamappe.** To serverprosesser over samme lagring er
   ikke støttet av dokumenterte låser. Enten håndhev én prosess, eller innfør
   plattformprøvd eksklusiv prosesslås/transaksjonslager for alle berørte lagre.
   Bare å låse profilfilen vil ikke gjøre journal/native-publisering atomisk.
5. **F/G: videre timingbevis.** Kombiner forsinket katalogtransport og native
   arbeider i én test, prøv kontosletting/deaktivering mens arbeidet kjører,
   tilbakekalling av A mens B har pågående arbeid og gamle svar etter omstart.
   En 300 ms uferdig HTTP-oppgave ved faktisk oppnådd native pause dokumenterer
   dette interleavinget; den er ikke full race-dekning.
6. **F/I: autentiseringens tidsgrense.** Revokert og slettet konto er prøvd.
   Tidsutløpt native sesjon er ikke konstruert eller bevist. Utvid gyldig/ugyldig
   bodymatrise med rå malformed/oversized JSON under alle relevante
   autentiseringstilstander. Tidligere profileruteprøver er historisk støtte,
   ikke en ny full matrise for siste integrasjon.

Ingen produksjonsrettelse ble integrert på grunnlag av undersøkelsen. F sine
eierfiler `PersonalYouTubeStore.cs` og `PersonalYouTubeService.cs` er lest;
avhengige produksjonsmoduler er undersøkt for kontrakter. Forslag til andre
fileiere står ovenfor. Det er fortsatt ingen generell godkjenning av restore,
flerprosess, OS-brukerisolering eller ekte Google gjennom hele kjeden.

## Reproduksjon og opprydding

Fra repositoriets rot, når delt fixture/server/port er ledig:

```powershell
dotnet build verification/PersonalChannels/PersonalChannels.csproj -c Release --no-restore
powershell -NoProfile -File verification/FollowUp/F/Run-F.ps1
powershell -NoProfile -File verification/FollowUp/F/Run-Store-F.ps1
dotnet run --project verification/PersonalYouTubeStore/PersonalYouTubeVerification.csproj -c Release --no-restore
```

Native skript bruker den eksisterende fixture med guarded tekstsøm; ingen annen
agents kildefiler er endret. Det krever eksisterende isolert Emby-oppsett og
medieverktøy. Run-Store-F trenger lokalt Dockerimage og .NET SDK; bare native
medieuthentingen i Run-F bruker faktisk nettverk.

To tidlige harnessfeil ble korrigert: deaktivert fremmed sesjon gir 401, ikke
404; testens biblioteksjournal brukte feil oppslagsnavn for `a-pending/a-latest`.
Journalens eksakte syntetiske eiersti ble reparert før kontrollert opprydding.
Etterpå fullførte ny native kjøring med readback. Første Linux-apphost brukte
feil libc/loader; endelig test bruker glibc og dokumentert symlink i egen
container. Ingen av de ufullførte forsøkene regnes som bestått evidens.

[FINAL-CLEANUP.json](FINAL-CLEANUP.json) bekrefter UsersGone, LibrariesGone,
MediaGone, FixtureGone og GuardGone. Det tidlige fixture-resultatet hadde
ServerStopped=false; en senere kontroll bekrefter **ServerStopped=true**,
JournalGone=true og ProfilesGone=true. Lagerets midlertidige data ble slettet
med readback på begge plattformer. Docker-testcontaineren er fjernet, bekreftet
i STORE-METADATA. Ingen hovedserver eller eksisterende Dockercontainer ble
endret. Nye portable filer inneholder bare syntetiske resultatdata og hashes;
tokens, nøkkelmateriale, rå server-/providerlogger og mediefiler ligger ikke i
leveransen.
