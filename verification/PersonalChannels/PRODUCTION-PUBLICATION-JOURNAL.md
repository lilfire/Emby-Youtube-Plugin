# Varig opprettingsjournal

Implementert 2026-10-12 i `PersonalYouTubePublicationJournal.cs`. Dette er en produksjonskomponent for forberedelse og aktivering, ikke en ferdig native publiseringskjede eller universell tilgangskrok. Hovedserveren er ikke endret.

## Forberedelse og aktivering

`Begin` bruker et gjeldende profil-snapshot og lagrer eier, samling, generasjon og opprettingsrevisjon med tilstand Preparing før noen mediemappe opprettes av komponenten. Den interne mediestien beregnes som `media/<eier>/<samling>/<generasjon>` under den servereide profilmappen. Andre eiere og nye generasjoner får forskjellige stier. Komponentens Begin oppretter ikke selve mediemappen eller noe native bibliotek.

Preparing-oppføringer består etter gjenåpning og kan hentes gjennom den serverinterne `Pending()` for senere gjenoppretting. `Activate` krever gjeldende snapshot og en allerede varig registrert native rot med riktig heltalls-ID/GUID, eier, samling og generasjon. En aktiv oppføring kan ikke bytte rot. Aktivering lagrer Active og rotparet; samme aktivering er idempotent.

Begge endringene går gjennom profillagerets synkrone publiseringsgrense. Journalen bruker egen prosesslås, påkrevd-markør, unik midlertidig fil, flush og erstatning. Manglende journal eller markør og ugyldig JSON/tilstand gir feil, ikke offentlig fallback. En eksisterende intern mediemappe uten journal behandles også som utilgjengelig journal. Full strømbruddsgaranti over Emby-database, journal og bindingsregister er ikke bevist.

## Samlet avgjørelse

`DecideItem` kombinerer bindingsregisteret, faktisk native ancestry, faktisk serversti og publiseringstilstanden. Et kjent native element som er registrert under en Preparing-generasjon avvises også når ingen filsti finnes. For en Active-generasjon kreves riktig registrert rot som elementet selv eller i faktisk ancestry. Et filobjekt kan ikke bruke en annen reservasjon sin sti. En uregistrert sti under den interne private medienamespace avvises.

Stikontrollen er en leksikalsk kontroll med `Path.GetFullPath` og plattformens bokstavsammenligning. Den beviser ikke fysisk containment ved symbolske lenker eller alternative filplasseringer. Serverens fremtidige publiserer må eie og kontrollere kildestedene og føre de faktiske stiene inn i avgjørelsen.

Bindinger til eksisterende native elementer uten journaloppføring beholder registerets tidligere beslutning. Dette tillater de allerede utførte integrasjonstestene, men den nye opprettingsflyten må bruke Begin og den samlede avgjørelsen. Å kalle bare bindingsregisterets avgjørelse gir ikke Preparing-beskyttelsen.

## Verifisering

Produksjonskomponentene passerte **112 kontroller**: tidligere 76 og 36 nye journalkontroller i `PublicationJournalChecks.cs`. Rapport: `verification/PersonalYouTubeStore/bin/results.json`, Completed=true og TestDataGone=true. Testene bruker den faktiske produksjonsklassen og syntetiske profiler/native par.

De nye kontrollene dekker varig forberedelse før mediemappen finnes, forskjellige stier, idempotens, henting av ufullført arbeid etter gjenåpning, avslag på private forberedte/uregistrerte stier, og ukjent offentlig kontekst. Registrert rot/video forblir nektet før aktivering. Feil/uregistrert/fremmed rot kan ikke aktivere. Riktig aktiv rot og barn får eierens positive kontroll; fremmede, anonyme, manglende rotancestry og uregistrerte barn nektes. Profilens sletting og ny generasjon kan ikke gjenåpne gamle aktive referanser. B beholder tilgang. Tap/korrupsjon av journalen og manglende markør avvises.

Den isolerte native broen bruker nå journalens samlede avgjørelse for eksisterende faktiske elementer. [Den tidligere native testen](NATIVE-UNBOUND-DESCENDANT.md) ble kjørt på nytt og passerte alle 81 observasjoner med faktisk serveromstart. Denne kjøringen oppretter **ingen Preparing/Active-journaloppføring**; den er en regresjon av eksisterende registertilgang, ikke en native test av opprettingsjournalen. Syntetiske serverdata ble ryddet; alle ni felt i den uavhengige native oppryddingsrapporten er true.

## Åpne krav

[NATIVE-ROOT-SOURCE-LOCATIONS.md](NATIVE-ROOT-SOURCE-LOCATIONS.md) har senere bekreftet de faktiske kildestedene via ILibraryManager.GetVirtualFolders og lagt til DecideSources med seks nye komponentkontroller (totalt 118). Kildestedene føres nå gjennom den isolerte broen; den eksisterende 86-observasjonstesten passerer. Første native oppretting før binding er fortsatt ikke testet.

[NATIVE-PUBLICATION-STATE.md](NATIVE-PUBLICATION-STATE.md) har senere verifisert Preparing-avslag og Active-positive kontroller på faktiske, eksisterende native elementer, med Preparing-omstart og 86 observasjoner. Første oppretting før native registrering er fortsatt ikke testet. En ny virtuell rot kan ha native sti utenfor den interne mediemappen før rot-ID-et er registrert; servergrensen må klassifisere den via kontrollerte kildesteder/publiseringsjournal før utlevering. Dette første rotvinduet er ikke bevist lukket.

Automatisk gjenoppretting, avbrudd/opprydding og håndtering av en Preparing-revisjon som blir foreldet er ikke implementert. Komponentens Pending gir inventar, ikke automatisk aktivering eller filopprydding. Native produksjonskroker, varige avledede referanser, personlig API-arbeid og faktisk YouTube-/alle-klientkontroll gjenstår. Full skjerming er fortsatt ikke bevist.
