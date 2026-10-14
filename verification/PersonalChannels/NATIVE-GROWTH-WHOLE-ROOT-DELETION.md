# Ny video fulgt av sletting av hele biblioteket

12. oktober 2026. Isolert Emby 4.10.1.0, to vanlige kontoer,
native HomeVideos-biblioteker og syntetiske lokale MP4-filer.
Hovedserveren og produksjonspluginen er ikke endret.

`Test-NativeMemberGrowthDeletion.ps1 -RequireDurability -DeleteWholeRoot`
bestod med 13 observasjoner og eksplisitte native/register-readbacks.
Det var ikke noe nytt Guard Enable-kall eller bytte av eier mellom
innskanning av den nye videoen og sletting av roten.

## Native handling og uendret eierskap

Etter innskanning fikk A riktig ny video med 200, B fikk 404 på denne
videoen og riktig eget innhold med 200. Den nye referansen var lagret
av den eksisterende ItemAdded/Updated-håndteringen.

For å unngå et nytt snapshot ved midlertidig admin-tilordning fikk
testprototypen en avgrenset, betrodd adminregel for faktisk native
`POST Library/VirtualFolders/Delete`: kun POST, faktisk autentisert
admin, én konkret forhåndsgodkjent synthetic A-rot og én matchende
DTO-referanse. Ingen metadata-/mediaforespørsel unntas av regelen,
og native adminautentisering for selve sletteruten forblir aktiv.
Godkjenningen er bare i minnet og overlever ikke prosessomstart.

Dette er en bevisst testpolicy for betrodd admin, ikke et forslag om
at vanlige brukere skal få administratortilgang. A/B var fortsatt
vanlige kontoer. B sitt forsøk på godkjenning fikk 403. Etter admin-
godkjenning fikk B sitt native sletteforsøk også 403, og en SDK-probe
bekreftet at roten fortsatt fantes. A fikk fortsatt sin nye video
med 200 før adminhandlingen.

Adminhandlingen fikk 204. Uavhengig readback via faktisk
ILibraryManager.GetItemById bekreftet at både roten og det nye
videoelementet var borte fra den native katalogen. Readback brukte
ikke den filtrerte VirtualFolders/Query-listen som eneste bevis.

SHA-256 av eierskapskonfigurasjonen var uendret før innskanning og
etter sletting. Godkjenningshandlingen endret heller ikke hash av
det native referanseregisteret. Hendelseslagring ved faktisk scan/
sletting kan endre registeret; testen unngår manuell Reconcile/
Enable som ellers kunne skjult manglende hendelseslagring.

## Etter sletting og faktisk omstart

A og B fikk 404 på den gamle nye video-ID-en etter sletting og
etter omstart. De fem negative metadataforespørslene inneholdt ikke
det private nye videonavnet. B fikk riktig egen video (ID/navn) med
200 etter sletting og etter omstart.

Guard var Enabled/Ready med ny BootId. Den nye video-ID-en var
fortsatt kjent som privat og satt i karantene. Disk-readback viste
den opprinnelige A-bruker-GUID-en, slettet rot-tilstand, den nye
videoens numeric ID og GUID samt rot-GUID i det varige registeret.

Rapport: `bin/native-member-growth-whole-root-results.json`.
Completed, NativeDeletionReadback, OwnershipConfigDigestUnchanged,
ApprovalDidNotChangeLedgerDigest, RestartVerified,
NewMemberPersistedAfterScan, PrivateKnownAfterDeletionAndRestart,
QuarantinedAfterRestart og RemovedNumericGuidReferencesAndOwnerReadback
er alle true.

Første kjøring stoppet før admin-sletting fordi kontrollen forventet
404 og fikk native adminavvisning 403 for B. Den kjøringen beviser
ikke sletting/restart og er separat bevart som
`bin/native-member-growth-whole-root-first-incomplete.json`.

## Fortsatt uavklart

Disse kontrollene dekker katalogmetadata og varig klassifisering.
De beviser ikke at alle eventuelle gjenværende Ready Sync-filer,
gamle LiveStreamId/OpenToken eller andre avledede ressurser nektes.
En metadata-404 for et katalogelement Emby har slettet kan ikke
alene bevise den grensen. Ingen videobyter ble hentet i denne testen.

Virtuell biblioteksletting trenger ikke slette de lokale mediefilene;
testens opprydding fjerner de syntetiske filene separat. Ikke forveksle
native katalog-fravær med fysisk fil-fravær eller generell full
skjerming. Nyoppretting med samme navn/sti/native identitet, diskfeil,
hendelsestiming, avbrutt lagring og faktisk YouTube-avspilling i alle
klientfamilier er fortsatt ikke verifisert.

Oppfølging: en faktisk gjenværende native strøm og et lagret OpenToken
er nå kontrollert i samme root-slettingsflyt. B ble nektet den beholdte
strømmen, og gamle fraværende strøm-ID-er etter restart svarte som
tilfeldig ukjente ID-er. Dette dekker metadata/open/close, ikke
strømbytes eller Ready Sync-filer. Se
[NATIVE-DELETED-ROOT-LIVE-STREAMS.md](NATIVE-DELETED-ROOT-LIVE-STREAMS.md).

Testbrukere, biblioteker, medier, fixture, guard, registre, tempfiler
og journal er fjernet og serverprosessen stoppet. Alle felter i
`bin/native-member-growth-whole-root-cleanup.json` er true.
