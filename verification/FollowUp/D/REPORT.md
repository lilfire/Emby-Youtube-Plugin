# D – video, transport og tilbakekalling

Undersøkt 2026-10-14. Funksjonstesting av pluginen mot isolert, selvhostet **Windows Emby Server 4.10.1.0**. Undersøkelsen har påvist feil i audio-/HLS-ruter og innholdsbinding. De avgrensede statiske tilbakekallings- og avbruddsprøvene fungerer. **D kan ikke godkjennes som fullført produktstøtte**; konkrete rettelser og resterende beviskrav står i TODO. Produksjonskode og Lilflix er uendret.

## Versjon, filer og faktisk testinngang

Plugin **2.0.10-alpha.1**, commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`.
Produksjons-DLL SHA-256: `AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`.
Eksisterende fixture-DLL SHA-256: `F890627BFB0BD1438536C7C4EF2D79A75CDFB5B195228C30F19D143C22EFD0FD`.
D sin boundary-fixture SHA-256: `4472FD8CD9CDF85F572E1A03D1A23C314046574F7054FCC82FC55EA88EB007D6`.

[Run-D.ps1](Run-D.ps1) leser Test-ProductionVideoStreams.ps1 og setter inn D-prober i minnet ved en entydig seam. Boundary-løpene bruker D sitt eget [fixtureprosjekt](BoundaryFixture.csproj) og [native timinginstrumentering](NativeVideoBoundary.cs). Eksisterende fixtures gjenbrukes som kildefiler, uten endringer i andre kapitlers filer. Ingen ny kandidat installeres på hovedserveren.

Testene går gjennom faktiske Emby HTTP-ruter og produksjonens service-, source- og skriverkontroller. Eksperimentell PrivacyGuard er deaktivert og tilbakelest. To syntetiske native Video-biblioteker har blå/rød MP4 med lydspor og forskjellige filhasher; vanlige A/B-kontoer har brede native bibliotekrettigheter. Hovedprøvene har fungerende eierkontroll og fremmedkontroll. Public lar A være vanlig innhold, mens B er privat.

Profiler opprettes med produksjonens MyProfile. Fixture-adapterens ProductionBindingBridge.Register kaller Store.Prepare og NativeBindings.Register direkte. Dette er **ikke** NativePublisher eller komplett publiseringsjournal. Ingen Google, yt-dlp, ekte API-nøkler eller fysisk klient brukes. Nøkkelprøven lagrer bare en syntetisk streng, uten katalog-/nettverksjobb. Boundary-fixturen pauser original native fabrikk/leser og endrer native metadata med UpdateItem; den implementerer ingen alternativ tilgangsavgjørelse eller videoleser.

## Faktiske transportfunn

| Inngang/scenario | Observert resultat og status |
|---|---|
| Video stream.mp4, stream uten container, original | A får komplett riktig kilde; B får 404 uten entityheadere. Avgrenset statisk støtte. |
| Dynamisk video, Static=false med h264/aac | 404 også for eier. Ikke støttet i den prøvde private kjeden. |
| Audio stream.mp4, stream uten container, original | **B får A sin komplette 11 071-byte MP4 med identisk SHA-256**, samtidig som ordinær videorute avviser B. Påvist feil. |
| Audio/video master.m3u8 og main.m3u8 | Native #EXTM3U utleveres til begge kontoer. Påvist fremmed spilleliste-/referanseutlevering. |
| Faktiske HLS-segmentreferanser | Første segment gir 400 også til eier; ingen dekodet frame. Mediebytes/transkoding uverifisert. |
| Universal audio | 500 også til eier; uverifisert. |
| Live-spillelister | Timeout/500 på lokal syntetisk kilde; ingen fungerende live provider prøvd. |
| A-sti med utskiftede B-bytes før forespørsel | 200 med komplette B-bytes. Påvist manglende innholdsbinding. |
| A-fil erstattet ved native leserinngang, etter autorisering | **200 med komplette B-bytes**, med uendrede A-item/kilde-ID-er. Samme feil ved faktisk I/O-grense. |

[Transport-EVIDENCE.json](Transport-EVIDENCE.json) dokumenterer audio-feilen med tre vanlige GET-ruter og paret eier/fremmedkontroll. Audio-/HLS-DTO-ene finnes ikke i ServiceReferenceGate sine auditerte mål. Anonyme oppslag er også prøvd, men avslag uten fungerende eiertransport regnes ikke som støttebevis.

[Hls-EVIDENCE.json](Hls-EVIDENCE.json) følger faktiske master- og variantlenker med eksplisitt MediaSourceId. Masteren inneholder A sin kilde-ID; varianten har én segmentreferanse. Autentiseringsfelt fjernes fra lenken før neste oppslag, og hver aktør bruker sin egen header. Segmentet gir 400 til begge, dekoder exit 1 og ingen frame. Spillelistefunn er derfor ikke bevis for fungerende HLS-avspilling eller utleverte HLS-mediebytes.

[Content-EVIDENCE.json](Content-EVIDENCE.json) og [Boundary-Reader-File-EVIDENCE.json](Boundary-Reader-File-EVIDENCE.json) bruker kontrollert lokal filutskiftning, ikke en HTTP-skriveinngang. Sti og LastWriteTime beholdes, og byttet leses tilbake med hash. Originale bytes, tidspunkt og riktige A/B-responser gjenopprettes etterpå. StaticSourceGate kontrollerer kilde/eier, kanonisk sti, separate alternativer og delegatidentitet; den sammenligner ikke forventet kildeinnhold med åpnet innhold.

## HTTP-varianter og vanlig offentlig innhold

Eksisterende startkontroller prøver fullfil, HEAD, 0–127-range og matching ETag for begge eiere. Nye prøver legger til midtintervall, suffix, åpent intervall, flere intervaller, ugyldig/reversert/usatisfiable og If-Range. Alle ni fremmedforespørsler på privat statisk video får 404 uten entityheadere.

| Eierforespørsel | Faktisk native resultat |
|---|---|
| bytes=128-255 | 206, eksakte 128 kildebytes |
| åpent intervall fra siste 128 bytes | 206, eksakte 128 kildebytes |
| bytes=-128 | 206, **første 129 bytes**, Content-Range bytes 0-128/11071 |
| bytes=0-15,32-47 | 206, 16 bytes; første intervall, ikke multipart |
| start etter filslutt | 404, generisk svar |
| reversert/ugyldig intervall | 200, komplett riktig fil |
| matching If-Range | 206, 128 bytes |
| foreldet If-Range | 200, komplett riktig fil |

[Public-EVIDENCE.json](Public-EVIDENCE.json) gjentar suffix-resultatet på vanlig A-innhold uten personlig binding. Dette avviket er dermed også i native offentlig transport. Begge autentiserte kontoer får SHA-korrekt offentlig A; A sitt oppslag av privat B avvises, og B sitt eget innhold virker. Anonym offentlig avspilling eller generell RFC-kompatibilitet godkjennes ikke.

## Native endringer ved faktiske fabrikk-/lesergrenser

Alle boundary-prøver når en aktiv native pause, med ventende HTTP, før endringen utføres. Metadataendringer skrives med native UpdateItem og leses tilbake; filer gjenopprettes med hash, og A/B kontrolleres etterpå.

| Grense og endring | Ventende svar | Annen eier |
|---|---|---|
| Før filfabrikk: native A.Path settes til B.Path | 404, generisk, ingen entityheadere/mediebytes | B virker |
| Før native åpning: samme Path-endring | 404, samme avslag | B virker |
| Etter native leserdelegat: samme Path-endring | 404, samme avslag | B virker |
| Etter leserdelegat: persisted A.ParentId flyttes til B.ParentId | 404, samme avslag | B virker |
| Før åpning: bindingsfil gjøres korrupt | 404, samme avslag | **B blokkeres også** til filen er gjenopprettet |
| Før åpning: A sitt native sesjonstoken tilbakekalles | 200, komplett riktig A-fil | B virker; nye A-forespørsler får 401 |
| Før åpning: fysiske A-bytes erstattes med B | 200, komplett B-fil | B virker |
| Etter leserdelegat: samme fysiske overwrite forsøkes | Windows IOException/delingslås, deretter riktig A-fil | B virker |

«Journal» i scriptets modusnavn betyr korruptert **native-reference-bindings.json**. Det er ikke en aktiv PublicationJournal-generasjonsendring. Felles filkorrupsjon avviser begge eiere; dette er en drifts-/gjenopprettingsbegrensning som E må håndtere, ikke bekreftet isolering av bare berørt samling. Native metadata og fysiske filer er gjenopprettet. Linux rename/inode-bytte, faktisk biblioteklokasjonsflytting og senere native I/O-mutasjoner er fortsatt uprøvd.

## Revokeringsmatrise

| Hendelse | Verifisert virkning og begrensning |
|---|---|
| Kanalbytte med MyProfile POST | Ny revisjon/kanal tilbakelest; gammel registrert A-binding leverer fortsatt GET/HEAD/range/304/If-Range. |
| Syntetisk nøkkelendring med MyProfile POST | KeyRevision=1 og HasApiKey tilbakelest; samme gamle transport beholdes. |
| Profilsletting før skriverens kontroll | Sletting fullføres og leses tilbake mens HTTP er pauset. 404 uten entityheadere ved frigjøring. |
| Profilsletting etter skriverens kontroll | Sletting venter på eierlåsen; korrekt A-fil fullføres; deretter lagres Deleted og nye A-kall avvises. |
| Deaktivert konto | Fem nye statiske GET/HEAD/range/conditional/If-Range-kall får 401 uten entityheadere. |
| Tokenrevokering | Samme fem nye statiske kall får 401. Ny autentisering av samme konto gir fungerende eierkontroll. |
| Kontosletting | Kontoens fravær leses tilbake; samme fem gamle statiske forespørsler får 401. |
| Native reparenting | Faktisk persisted ParentId-bytte etter leserdelegaten gir 404 før skriving. |
| Hel bibliotekflytting/aktiv publiseringsjournal | Ikke prøvd; E/F-avhengighet. |

Audio-filbytes og HLS-spillelister til **B fra A** utleveres fortsatt etter kanal-/nøkkelbytte, deaktivering, tokenrevokering, kontosletting og profilsletting. Avslag på gamle A-sesjoner lukker derfor ikke de alternative rutene.

Kanal-/nøkkelprøvene bruker en Draft-profil med direkte registrerte bindings. Store.Save beholder generasjonen; SaveForRefresh behandler publiserte journaloppføringer separat. Disse resultatene er observasjoner av den prøvde inngangen, ikke bevis for komplett lagre-og-oppdater/NativePublisher-kjede. F/G må prøve samme endringer under virkelig produksjonspublisering.

## Allerede godkjent overføring og ventende låser

[BeforeWrite-EVIDENCE.json](BeforeWrite-EVIDENCE.json) og [Lease-EVIDENCE.json](Lease-EVIDENCE.json) beviser begge tidsrekkefølger på den faktiske native skriveren. Etter godkjenning holder skriveren A sin lås til native skrivetask er ferdig. B kan samtidig strømme eget innhold og lagre egen profil. Forsøkt overwrite av originalen etter skriverkontrollen blokkeres av Windows sitt åpne filhåndtak.

[Abort-EVIDENCE.json](Abort-EVIDENCE.json) bruker ekte TCP-mottrykk, **uten timingkrok**: en disponibel syntetisk MP4 utvides med nullbytes til 64 MiB. Klienten mottar 200 og riktig Content-Length, verifiserer de første 128 kildebytes og stopper deretter lesingen. Native eierlås forblir holdt og profilsletting venter. B leverer fullfil/HEAD/range/304 og lagrer profil. Når TCP-klienten lukker forbindelsen, frigjøres låsen og slettingen lagres; observasjonen er **64 ms** fra klientavbrudd til readback. Nye A-kall avvises, B fungerer fortsatt. Dette er en avbrutt 64 MiB-overføring under mottrykk, ikke 64 MiB fullført levering eller en timevis utholdenhetstest.

Semantikken i den prøvde kjeden er:

* Nye statiske forespørsler etter fullført profil-/konto-/tokenrevokering avvises.
* En allerede godkjent overføring kan fullføre. Native tokenrevokering etter serviceautorisering stopper ikke den prøvde ventende lesingen.
* Profilendring venter til skriveren fullfører eller avbruddet avslutter skrivetasken. Allerede sendte bytes kan ikke trekkes tilbake.

TransferLease er prosesslokal SemaphoreSlim per eier. Enter bruker Wait() uten timeout/CancellationToken; Complete frigjør i finally etter native task. Det finnes **ingen definert maksimal ventetid** dersom en skrivetask ikke avsluttes. Ett vellykket klientavbrudd beviser ikke alle heng-, timeout- eller kanselleringsforløp. En slik maksimal tid er et gjenstående produktvalg.

## Konkrete rettelsesforslag

1. Koordinator/A må føre audio-/HLS-innganger inn i faktisk eier-/generasjonskontroll. Ustøttede private transportveier må avvises før native kilde, spilleliste, transkoder eller segmentreferanse lages. HLS trenger egen kjede; en master-404 alene er ikke nok for gamle segmentreferanser.
2. D/E/G trenger forventet originalinnhold fra betrodd buffering/publisering, med kildehash, filidentitet og aktiv generasjon. D/C må kontrollere samme åpne innhold som leveres, inklusive senere I/O og Linux filbytte.
3. F/G må definere Save versus SaveForRefresh, nøkkelrotasjon og gamle generasjoner i komplett produksjonskjede. Konto/token før og etter autorisering må ha eksplisitt avtalt semantikk.
4. Koordinator/E må håndtere felles korrupt bindingsfil og definere begrenset låseventing/kansellering uten at B sine fungerende strømmer/profiler rammes.

Ingen av disse forslagene er integrert i produksjonen. Ingen kontraktallowlist eller støtteerklæring er utvidet. Påviste avvik og uprøvde forløp står åpne.

## Reproduksjon, evidens og opprydding

Kjør Run-D.ps1-modusene sekvensielt i avtalt tidsluke: Transport, Hls, Content, Channel, Key, Accounts, BeforeWrite, Lease, Public og Abort. Bygg BoundaryFixture.csproj i Release og kjør Boundary med Phase/Mutation: Factory/Path, Reader/Path, AfterReader/Path, AfterReader/Parent, Reader/Journal, Reader/Token, Reader/File og AfterReader/File. BoundaryPhase/BoundaryMutation er parameternavnene. Kjør til slutt `python verification/FollowUp/D/Collect-D.py`.

[SUMMARY.json](SUMMARY.json) og portable *-EVIDENCE.json inneholder **18 fullførte sluttløp med 815 observasjoner** og deres konkrete readback. To live-kall per Transport/Public har timeout og er uverifiserte selv om matrisen fullfører. Observasjonstall er ikke antall uavhengige avspillinger eller noen generell støttegaranti. [ROUTES.csv](ROUTES.csv) inneholder 38 deklarerte D-ruter fra A sitt inventar, med eksplisitt avgrenset runtime-/uverifisert status. Transitive factories, alle codecs, faktiske live providers og andre Emby-builds er ikke fullstendig inspisert eller prøvd. Ingen Linux/Docker-godkjenning følger av Windows-løpene.

Tidlige ufullstendige Transport-/Accounts-/Lease-forsøk er ikke passeringer. Accounts ble rettet til ny autentisering etter reaktivering; den gamle sesjonen blir ikke gyldig igjen. Lease sin overwrite-probe ble rettet til å beholde uendret filtid når Windows avviser skriving. Bare ferske fullførte sluttløp eksporteres som endelig evidens.

Alle sluttløps cleanup-readback krever slettede syntetiske kontoer, biblioteker, media, fixture/guard, profiler og fixture-journal, samt faktisk ServerStopped/PortFree=true. Tidlig NativeCleanup.ServerStopped=false er beholdt separat fra wrapperens senere sluttstatus. Midlertidige HLS-segmenter og RGB-filer slettes av proben. Rå logger, tokenfiler, videofiler og lokale data fra bin leveres ikke. Sluttkontroll dokumenteres i FINAL-CLEANUP.json.
