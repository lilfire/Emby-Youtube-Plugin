# Produksjonssperre før native item-service

Implementert og isolert kontrollert 12. oktober 2026 på Emby 4.10.1.0. Hovedserveren er urørt.

## Faktisk inngangsoversikt

`Inspect-NativeBoundary.ps1` leser runtime-metodeform/IL fra faktisk HTTP-host og ServiceController og rute-/egenskapsmetadata fra lastede native DTO-er. Rapporten `bin/native-boundary-inventory.json` omfatter 430 native rute-DTO-er. Første søk utelot Emby.Api og ble avvist som mangelfullt; namespace-filteret er rettet før bruk av inventaret. Dette er et inventar, ikke en full klassifisering eller et bevis for at alle rutene er håndhevet. Ruter som registreres uten RouteAttribute eller kommer fra andre plugins trenger separat gjennomgang.

Faktisk ServiceController.Execute er en instansmetode med argumentene HttpListenerHost, object requestDto, IRequest, Type, og returnerer Task<object>. Produksjonskoden krever denne formen og det målte metodekroppsfingeravtrykket `8BA7FF537CD85A04E017952B69ED59468D65F557CCC3D62ACB14CBE24EF4F2CA` før patching.

## Produksjonskode

PluginEntryPoint installerer PersonalYouTubeServiceReferenceGate ved oppstart med faktisk IHttpServer, ILibraryManager og IAuthorizationContext. Ti eksplisitte native DTO-typer og deres string Id-egenskap kontrolleres:

- UserLibrary.GetItem og Library.GetDownload.
- MediaEncoding.GetPlaybackInfo og GetPostedPlaybackInfo.
- MediaEncoding.MarkPlayedItem og MarkUnplayedItem.
- UserLibrary.MarkFavoriteItem og UnmarkFavoriteItem.
- UserLibrary.UpdateUserItemRating og DeleteUserItemRating.

Prefixen kjører før original ServiceController.Execute. Den bruker faktisk autentisert User og produksjonens NativeAccess mot målreferansen. Denied eller feil avbryter serviceutføring med generisk 404 uten privat navn. Unknown overlates til den vanlige native tjenesten. Ved Allowed privat referanse må en eventuell DTO UserId også stemme med faktisk bruker, siden enkelte native tjenester bruker den for brukerstatsmutasjoner. Dermed kan en tillatt eier ikke rette sin private kilde mot en annen kontos historie gjennom dette feltet.

Produksjonskroken identifiserer verken eier gjennom fixture-navn eller fixture-modus. Oppstartsinstallasjonen verifiserer egen Harmony-prefix/eier og patchmetode. Snapshot sjekker faktisk prefix og rapporterer PatchLost hvis den er borte. Dette alene er ikke ferdig håndheving ved bortfall for allerede indekserte private biblioteker; full oppstart-/bortfallsgaranti står fortsatt åpen.

## Produksjonskoblingen alene

`Test-ProductionServiceGate.ps1` oppretter syntetiske ordinære A/B-kontoer, faktiske native videoer, personlige produksjonsprofiler og varige native bindinger. Native elementer er beholdte eksisterende fixture-elementer, uten personlig produksjonspubliserer/journalaktivering. Deretter slås PrivacyGuard sin eksperimentelle håndheving av, og deaktivert tilstand leses tilbake. Den er også avslått igjen etter faktisk omstart. Ingen fixture-skjerming kan gi de observerte avslagene i disse fasene.

Den fullførte kjøringen har 53 observasjoner i `bin/production-service-gate-results.json`:

- Alle ti B-forespørsler mot A sin metadata, fil, PlaybackInfo og sett-/favoritt-/ratingstatus returnerer 404 i Active, etter profilsletting og etter omstart.
- For hver runde øker produksjonens Checked og Denied nøyaktig med ti. Det bekrefter at produksjonsprefixen sto for avslagene.
- A sin faktiske native UserData er identisk før og etter de første ti fremmede forespørslene.
- A sine egne favoritt- og settstatusendringer lykkes, og de faktiske native statusfeltene leses tilbake som endret.
- En tillatt A-eier får 404 hvis han retter favorittendringen på A-innhold mot B-UserId.
- B sine metadata, videobytes med samme filhash og PlaybackInfo gir 200 i alle tre faser.

Det første forsøket sendte utilsiktet JSON-body med GET; PowerShell sin HttpClient avviste dette før den første fremmede forespørselen. Den ufullførte rapporten er bevart som `bin/production-service-gate-get-body-incomplete.json`, og testskriptet er rettet. Den teller ikke som bestått evidens.

Etter siste statusstramming av faktisk prefixkontroll ble den eksisterende native livsløpsregresjonen kjørt igjen med den nye produksjonskoblingen installert: `Test-ProductionNativeBindings.ps1 -PublicationJournal -ActualAccess` fullførte alle 235 observasjoner. Den regresjonen har fixture-håndhevingen på og teller derfor ikke som ytterligere produksjonskobling-alene-bevis.

Sluttopprydding er lest tilbake i `bin/production-service-gate-cleanup.json` og `bin/native-client-cleanup.json`: stoppet server, testbrukere/biblioteker/filer fjernet, samt fravær av profiler, fixture-DLL, journal og modusfil.
Native cleanup sin umiddelbare ServerStopped-markør var false. Den er bevart;
en senere uavhengig Get-Process-kontroll bekreftet at EmbyServer var borte.
Sluttrapporten skiller derfor EarlierCleanupServerStopped=false fra den
senere ServerStopped=true, fremfor å overskrive den første observasjonen.

## Avgrensning og videre arbeid

Dette er ti kontrollerte DTO-er, ikke 430 ferdig håndhevede innganger. Lists/counts/paging, bilder/undertekster/kapitler, batch-/rå-body-innganger, egne streaming/HLS-handlere, Sync/jobber/tokens, socket/DLNA og andre plugins må gjennomgås og kobles til den samme modellen. En prefixavgjørelse alene løser heller ikke revokering mellom sjekk og senere asynkron utlevering/mutasjon.

Det fullstendige målet gjelder fortsatt vanlig bibliotek i alle klientfamilier, egen nøkkel/kanaljobbkjede, varig publisering/recovery og faktisk YouTube-avspilling. Lokale MP4/PlaybackInfo-positive kontroller bekrefter ikke en fungerende YouTube-mediekjede. Full skjerming er ikke bevist.
