# Faktisk ny rot før ID-binding

Kontrollert 2026-10-12 på isolert Emby 4.10.1.0. `Test-NewUnregisteredPrivateRoot.ps1` bruker produksjonsjournal/register gjennom testpluginens eksperimentelle tilgangskroker. Hovedserveren er ikke endret; ingen faktisk YouTube-kilde ble brukt.

## Opprettingsrekkefølge og uavhengige kontroller

A sin profil fikk først en varig Preparing-reservasjon gjennom produksjonens Begin. Den nye, tomme mediemappen ble opprettet på den beregnede interne stien. Deretter opprettet native `Library/VirtualFolders` en faktisk ny rot som peker på denne mappen.

Navnet er `JournalPending_<generasjon>`, uten testprototypens `Private Native Fixture`-prefiks. En kontrollert administrasjonsprobe leser den faktiske roten og Locations fra ILibraryManager. Testen krevde eksakt samsvar med den journalførte stien. Registerfilen ble lest og bekreftet at ingen A-identiteter eller ny rot-ID var registrert. A sin native EnabledFolders-policy ble eksplisitt utvidet med den nye rot-GUID-en og lest tilbake.

Det gamle testkartet ble ikke utvidet med den nye roten. Klassifiseringen må derfor bruke den nye kildesteds-/journalavgjørelsen fremfor navn/registrert A-rot. B sin opprinnelige registrerte video gir en separat positiv kontroll.

## Resultat

Rapport: `bin/new-unregistered-private-root-results.json`, Completed=true og RestartVerified=true. **27 observasjoner:** 24 HTTP-kontroller og tre native opprettings-/registrerings-/aktiveringstilstandskontroller.

- Før ID-binding: begge rotaliaser ga 404 for A og B, og roten/kildestien var skjult i deres biblioteklister. B fikk sin videometadata og SHA-korrekte prøvefil.
- Etter faktisk serveromstart med ny BootId/Ready: de samme kontrollene passerte. Den nye roten var fortsatt ikke registrert.
- Deretter ble samme faktiske rot og fysiske mappe registrert under A sin profil, mens journalen fortsatt var Preparing. A fikk fortsatt 404 via begge rotaliasene.
- Etter separat Activate: samme rot ga 200 via begge aliaser for A og viste det forventede navnet. A sin bibliotekliste inneholdt roten. B fikk fortsatt 404 og så ikke roten i sin bibliotekliste.

Den positive kontrollen etter aktivering er nødvendig: de tidligere avslagene gjelder en faktisk tilgjengelig native rot, fremfor en rot som alltid ville gitt 404. Biblioteket er tomt; disse positive kontrollene er rotmetadata/lister, ikke avspilling eller videoutlevering fra den nye roten.

Første 17-observasjonskjøring uten aktivering er bevart i `bin/new-unregistered-private-root-first-17-results.json`. Et utvidet forsøk ble feilaktig startet mot forrige fixture-DLL etter en variabelnavnfeil i bygget; det avviste den nye probehandlingen med 400. Det ufullførte forsøket er bevart i `bin/new-unregistered-private-root-old-dll-incomplete.json` og teller ikke som bestått. Variabelnavnet ble rettet, bygget passerte og den ferdige 27-observasjonskjøringen fullførte.

## Opprydding og konkret gjenværende vindu

Det nye bibliotekets planlagte navn og kildesti journalføres før native oppretting, slik at testoppryddingen kan finne eksakt rot også hvis ID-avlesningen feiler. Opprydding fjernet nye/gamle prøvebiblioteker, kontoer, prøvefiler, journal/register/profiler, modus og testplugin. Den private mediemappen var tom. Bounded opprydding validerte den eksakte isolerte profilmappen, avviste ukjente filer/reparse points og fjernet bare testtreet. Uavhengig sluttkontroll har alle ni felt true i `bin/new-unregistered-private-root-cleanup.json`.

Kontrollene begynner **etter at AddVirtualFolder-API-kallet har returnert**, og etter at serveren kan lese Locations. De beviser ikke at en klient aldri kan finne native referanser mens selve opprettingskallet pågår, før konfigurasjonen er synlig. Det neste nødvendige timingforsøket må pause den faktiske native opprettingen ved et målt tidspunkt, kontrollere native/config-tilstand separat og forsøke ordinær tilgang mens pausen holdes.

Produksjonens universelle tilgangskroker, publiseringskjede, gjenoppretting/opprydding, avledede referanser og faktisk YouTube-/alle-klientkjede gjenstår. Full skjerming er ikke bevist.
