# Native biblioteksnavn kan endres med stabil rotidentitet

Isolert Emby 4.10.1.0, 2026-10-12. Bare journalforte testbiblioteker og
testprototype, ikke produksjon eller hovedserver.

## Faktisk native navnebytte

Den innlastede rutekontrakten i native-route-inventory.json har POST
Library/VirtualFolders/Name med Id og NewName. Test-NativeLibraryRename.ps1
kalte denne faktiske ruten; native RenameVirtualFolder gav 204.
Det ble ikke bare endret et felt i et kunstig bibliotekssvar.

De to kontoene var vanlige ikke-administratorer. Selve navnebyttet var
en kontrollert adminhandling: A sin testrot ble midlertidig tildelt
testadministratoren i guard-konfigurasjonen slik at den native adminruten
kunne kalles. Etter readback ble roten tildelt A sin opprinnelige GUID
igjen. Ingen eiertilgang eller kontinuerlig A-avspilling ble provd i det
midlertidige admin-vinduet. Dette er ikke en implementert selvbetjent
brukerfunksjon for biblioteksnavn.

Biblioteket Private Native Fixture a ble til Private Native Fixture a
renamed. Native VirtualFolders-readback verifiserte nøyaktig navn og
uendret fysisk medieplassering. Root ItemId og Guid var begge uendret.
Guard-konfigurasjonen brukte dermed samme rot-ID for A for/etter navnebytte.

## Eierkontroller og restart

Den forste kjoringen kontrollerte 19 HTTP-statusobservasjoner. Den ble
bevart i bin/native-library-rename-status-only-results.json. Testen ble
deretter styrket med kontroller av innhold og gjentatt i et friskt oppsett.

Den autoritative nye native-library-rename-results.json har Completed=true,
RootIdUnchanged=true, RootGuidUnchanged=true, DisplayNameSurvivedRestart=true
og RestartVerified=true. Kjoringen fullforte med exit 0, 19 observasjoner:

- Begge eieres gamle video-ID: 200 og korrekt ID/privat videonavn, seks ganger.
- Fremmed video-ID: 404 i begge retninger for navnendring, etter og etter restart.
- Egen PlaybackInfo: 200 med den korrekte eksisterende lokale filkilden,
  seks ganger. Dette er kilde-/avspillingsmetadata, ikke faktisk avspilling.
- Native navnebytte: 204.

Serverrestart var faktisk stopp/start med ny BootId og Enabled/Ready=true.
Eierens rotmetadata etter restart hadde det nye navnet. Ingen gamle video-
referanser trengte aa byttes ut i de provde foresporslene.

Dette gir et konkret identitetsgrunnlag for vanlige native biblioteker
ved navneendring i denne serverversjonen. Den tidligere IChannel.Name-
testen viste endret kanalidentitet; de to modellene skal ikke likestilles.

## Dokumentasjon og grenser

[ILibraryManager](https://dev.emby.media/reference/pluginapi/MediaBrowser.Controller.Library.ILibraryManager.html)
dokumenterer oppretting av virtuelle biblioteker med AddVirtualFolder.
Ruten og oppforselen for navnebytte ovenfor er bekreftet fra installert
server og faktisk HTTP-kall, ikke antatt fra en deklarert IChannel.Id.

Testen endret bare ett biblioteksnavn, beholdt medieplassering og beholdt
syntetisk privat navneprefiks. Rotflytting, slettet/gjenopprettet rot,
vilkarlige navneprefikser, samtidig navneendring, vedvarende Sync-referanser
og faktisk YouTube-/klientavspilling er ikke provd. All produksjonsbinding
til immutable samling/eier er fortsatt uimplementert. Full skjerming er
fortsatt ikke bevist.

## Opprydding

Planlagt navnebytte ble journalfort for native kall. Readback oppdaterte
journalen til faktisk navn/identitet; kontrollert cleanup kan ogsa finne
en planlagt omdopt rot ved eksakt navn og eksakt eksisterende medieplassering
hvis gammel ID er borte. Den fallbacken ble ikke brukt fordi ID var stabil.
Ingen computed recursive delete eller generell opprydding ble brukt.

Begge oppsett ble ryddet med bruker-/bibliotek-readback, mediefilfjerning
og stopp av isolert prosess. bin/native-library-rename-cleanup.json bekrefter
ServerStopped og fravaer av journal, fixture, guard, register og tempfil.
