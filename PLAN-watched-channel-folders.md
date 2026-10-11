# Plan: korrekt sett-status for YouTube-kanalmapper

## Problemstilling

Når brukeren velger «usett» i Emby, vises en YouTube-kanalmappe selv om alle videoene i den er sett. Mappen har egen UserData.Played-status som ikke følger videoene. En manuell markering av mappen løser visningen midlertidig, men kan skjule kanalen når nye, usette videoer kommer.

Målet er at kanalmapper vises med «usett»-filteret når de inneholder minst én tilgjengelig, usett video, og skjules når alle tilgjengelige videoer er sett. Statusen må beregnes separat for hver Emby-bruker og oppdateres etter endringer i innhold eller sett-status.

Dette er en integrasjonsmangel mellom pluginen og Emby. Google YouTube Data API leverer kanal- og videodata; Emby eier sett-statusen. Løsningen trenger ingen nye Google-rettigheter, OAuth-innlogging eller synkronisering av YouTube-kontoens seerhistorikk.

## Bekreftet reproduksjon

Observert på plugin 2.0.9.3 og Emby Server 4.10.1.0:

1. «3D Printing Nerd» inneholdt 50 videoer.
2. Alle 50 videoer var markert som sett for samme bruker.
3. Kanalens mappe hadde UserData.Played=false og ChildCount=50.
4. GET /Items med kanaloversiktens ParentId, UserId og IsPlayed=false returnerte fortsatt mappen.
5. GET /Items med kanalmappens ParentId og samme filter returnerte ingen usette videoer.
6. POST /Users/{UserId}/PlayedItems/{folderId} ga fortsatt Played=false for mappen i denne installasjonen.
7. POST /Users/{UserId}/Items/{folderId}/UserData med Played=true fungerte. Etter lesing tilbake hadde mappen Played=true og var borte fra «usett»-resultatet.

Punkt 7 beviser at Emby kan lagre den nødvendige mappestatusen. Det beviser ikke at Emby automatisk nullstiller den ved nye videoer. Den installerte pluginens kildekode har ingen tilsvarende synkronisering.

Ikke hardkod serverens item-ID-er eller bruker-ID-er i implementasjonen.

## Foreslått løsning

Legg til en avgrenset komponent, eksempelvis YouTubeFolderWatchStateSynchronizer.cs, som beregner og lagrer avledet sett-status for pluginens kanalmapper.

Bruk videoenes eksisterende Emby-status som sannhetskilde. Synkronisering av mappefeltet må aldri markere videoer som sett eller usett.

For en bruker og en ferdig innlest kanal:

- Minst én tilgjengelig video er usett: mappen skal ha Played=false.
- Minst én tilgjengelig video finnes, og alle er sett: mappen skal ha Played=true.
- Ingen tilgjengelige videoer finnes: Played=false som konservativ standard. Skjuling av tomme mapper er et eget problem.
- Innholdet er ufullstendig, skanning pågår eller lesing feiler: utsett beregningen. Ikke sett Played=true på grunnlag av en tom eller delvis liste.

«Alle videoer» betyr videoene som faktisk er materialisert og tilgjengelige i Emby med gjeldende innstillinger. Pluginen laster et begrenset antall videoer, blant annet gjennom MaxChannelVideos. Dette skal ikke fremstilles som sett-status for hele YouTube-kanalens historikk.

### Identitet og omfang

Identifiser kanalmapper med pluginens provider-/kanalidentitet og stabile ExternalId, ikke visningsnavn.

YouTubeChannel.IsSavedChannelRootExternalId gjenkjenner channel_x_-røtter. Koble dette med korrekt YouTube-provider slik at andre plugins eller mediebiblioteker ikke berøres.

Første leveranse omfatter lagrede kanalrøtter og deres pluginopprettede Videos/Shorts/Live-undermapper der disse finnes. Beregn rotstatus rekursivt fra tilgjengelige videoer, og undermappestatus fra dens egne etterkommere. Ukjente eller ikke-spillbare plassholdere skal ikke telle som videoer.

Trending, kategorier, søkemapper og spillelister holdes utenfor første leveranse. De har andre regler for innhold og kan vurderes senere. Delt video i flere mapper må kunne oppdatere alle berørte foreldre.

Beregn per bruker, og respekter Emby-tilgang, deling og relevante brukerfiltre. En utilgjengelig video skal ikke holde en mappe usett for en bruker som ikke kan se videoen.

### Emby-API og kompatibilitet

Bruk injiserte ILibraryManager, IUserDataManager og IUserManager, og Emby sine støttede SDK-metoder. Ikke skriv direkte i library.db eller user-data-databasen, og ikke bygg en loopback-HTTP-klient med en ny API-nøkkel.

Prosjektet bygger for net6.0 mot MediaBrowser.Common og MediaBrowser.Server.Core 4.9.1.90. Før implementasjon må de faktiske signaturene for følgende bekreftes mot pakkene:

- brukeravgrenset og rekursiv bibliotekspørring;
- lesing og lagring av UserData for en Folder;
- hendelser ved endret UserData og ved opprettet/fjernet innhold;
- riktig UserDataSaveReason og klientvarsling etter endringen.

Verifiser spesielt at SDK-lagring gir samme resultat som den fungerende UserData-ruten. Den vanlige PlayedItems-ruten fungerte ikke for denne mappeformen. Ikke anta at et kall til «mark played» på en mappe er riktig løsning.

Oppdater bare Played-feltet på mappens gjeldende UserData når ønsket verdi avviker. Bevar favorittstatus, vurdering, avspillingsposisjon, antall avspillinger og andre brukerdata.

### Når synkronisering skal kjøres

1. Etter vellykket, faktisk fullføring av en kanalskanning.
2. Etter at en videos Played-status endres, både gjennom avspilling og manuell «sett/usett».
3. Etter relevant oppretting, fjerning eller flytting av video-/mappeinnhold.
4. Etter oppstart, for å rette allerede inkonsistente mapper.
5. Etter relevante endringer i brukerens tilgang eller hvilke videoer kanaloppsettet inkluderer.

PluginEntryPoint.cs har allerede injiserte managere, livssyklushåndtering og en ItemUpdated-hendelse. Koble til bekreftede SDK-hendelser gjennom tilsvarende mønster, og koble dem fra ved Dispose.

ChannelRefreshInvoker har en continuation på den virkelige RefreshChannelContent-tasken. Kø synkronisering fra vellykket fullføring der. Timeouten etter 120 sekunder betyr bare at sporingsvinduet er utløpt; den betyr ikke at skanningen er ferdig.

Emby sine egne planlagte kanalskanninger må også dekkes. Bekreft om SDK-et har en pålitelig fullføringshendelse. Hvis ikke, kombiner relevante innholdshendelser med eksisterende skanne-/hvilemekanisme og ny kontroll før skriving.

### Kø, samtidighet og feil

Bruk en bakgrunnskø som slår sammen gjentatte oppdateringer for samme bruker/mappe. Hendelseshandlere skal bare kølegge arbeid.

Vent mens ChannelRefreshInvoker.IsRefreshInProgress er true. Følg prosjektets etablerte hensyn til samtidige databaseoperasjoner, eksempelvis i YouTubeSortNameRepairer.cs.

Les innhold og brukerstatus på nytt etter venting og før lagring. Dersom innhold eller brukerstatus endres under beregningen, kølegg ny beregning. Særlig må en ny usett video ikke bli overstyrt av et gammelt «alle sett»-resultat.

Ikke lagre uendret Played-status. Unngå hendelsesløkker fra egne mappeoppdateringer, men ikke undertrykk reelle videoendringer fra samme bruker.

Bruk avgrenset retry ved midlertidige databasefeil, kansellering ved nedstenging og logg uten API-nøkler eller tokens. Feil skal aldri tolkes som «ingen usette videoer».

Ikke hent nye data fra YouTube for å beregne sett-status. Arbeid på Emby sine eksisterende elementer og brukerdata. Foretrekk en avgrenset «finnes minst én usett video»-spørring fremfor å lese hele biblioteket per hendelse.

### Manuell mappehandling

Avklar og dokumenter semantikken for «marker kanal som sett/usett»:

- Når klienten/Emby faktisk oppdaterer etterkommerne, skal synkroniseringen følge videoenes nye status.
- Når bare mappens Played-felt endres, skal avledet status beregnes på nytt fra videoene.
- Synkroniseringen skal ikke tolke sin egen mappeoppdatering som en kommando om å endre alle videoer.

En egen funksjon for å markere alle videoer gjennom pluginen er utenfor første leveranse, med mindre reproduksjonen viser at den er nødvendig for vanlig klientbruk.

## Arbeidsrekkefølge

1. Lag en minimal reproduksjon med én kanal, to videoer og to brukere. Bekreft filteret og SDK-lagring av mappestatus.
2. Bekreft SDK-signaturer, identitetskontroller og brukeravgrensning før komponenten utformes.
3. Implementer beregning av ønsket status og en kø som lagrer bare endringer.
4. Koble køen til oppstart, faktisk skannefullføring, endringer i Played og relevante innholdsendringer.
5. Legg til kansellering, beskyttelse mot hendelsesløkker og avgrenset feilbehandling.
6. Test og dokumenter oppførselen. Ta sikkerhetskopi av brukerdata før utprøving på produksjonsserveren.
7. Lever en separat kodeendring med bygg- og testresultater. Denne planen innebærer ingen endring av serveren.

## Akseptansekriterier og tester

- To usette videoer: kanalen vises med IsPlayed=false.
- Én sett og én usett: kanalen vises fortsatt.
- Siste video markeres som sett: kanalen skjules, uten manuell mappemarkering.
- Ny usett video legges til: kanalen dukker opp igjen.
- En sett video markeres som usett: kanalen dukker opp igjen.
- Samme kanal har ulik status for to brukere; oppdatering for én endrer ikke den andre.
- En manuelt satt, feil mappestatus fra gammel versjon repareres ved oppstart.
- Tilgangsbegrensninger og Shorts-/Live-undermapper håndteres uten å bruke skjulte videoer i feil brukerberegning.
- Sletting av siste usette video beregner statusen på nytt etter at innholdsendringen er ferdig.
- Tom kanal, API-feil og ufullstendig skanning gir ikke falsk «sett».
- En skanning som varer mer enn 120 sekunder gir ikke for tidlig synkronisering.
- Samtidig ny video og sett-markering ender med status fra de nyeste dataene.
- Favoritter, videoenes Played-status, avspillingsposisjon og annen brukerdata bevares.
- Ingen hendelsesløkke, nye Google-kall eller fullbiblioteksskanning for hver avspillingsoppdatering.
- Oppførselen ved manuell mappehandling er eksplisitt testet og dokumentert.
- Verifiser med GET /Users/{UserId}/Items/{folderId} og GET /Items?ParentId=...&UserId=...&IsPlayed=false, samt Emby Web og minst én aktuell native klient.
- Bygg med dotnet build -c Release, og test på Emby 4.10.1.0. Bekreft også kompatibilitet med de serverversjonene forken velger å støtte.

Enhetstester skal dekke beregningsreglene og feil-/samtidighetstilfellene. Integrasjonstesten mot Emby må bevise faktisk filtrering og at en ny video gjør kanalen synlig igjen; en test av bare det lagrede boolske feltet er ikke tilstrekkelig.

## Avgrensning og åpne spørsmål

Dette synkroniserer ikke abonnementer eller seerhistorikk fra Google-kontoen. Det endrer ikke bibliotekets oppsett, klientenes filtervalg, startsiderader eller videoinnhenting.

Følgende må avgjøres gjennom SDK- og integrasjonstestene, ikke antas fra planen: støtte for mappebrukerdata på eldre Emby-versjoner, hendelse for Emby-initierte skanninger, tilgangsfiltrert rekursiv spørring og klientenes reaksjon på oppdatert mappebrukerdata.
