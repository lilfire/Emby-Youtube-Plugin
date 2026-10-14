# Nye private medlemmer, sletting og omstart

Undersøkelse 12. oktober 2026, isolert Emby 4.10.1.0. Kun
testprototypen er endret; produksjonspluginen og hovedserveren er urørt.

## Påvist gap i snapshot-prototypen

`Test-NativeMemberGrowthDeletion.ps1` kopierte en syntetisk MP4 til A
sitt eksisterende HomeVideos-bibliotek etter opprettelse av guard og
eierskapsregister. Ekte biblioteksoppfrisking skannet inn den nye videoen.
A og B var begge autentiserte vanlige kontoer. A fikk riktig nytt item
med 200, B fikk 404, og B fikk riktig egen video med 200.

Det nye elementet var kjent som privat i minnet, men ID-en var ikke i
registeret på disk. Testadmin slettet deretter bare det nye elementet
via faktisk `ILibraryManager.DeleteItem`, med `DeleteFileLocation=true`.
Den avgrensede admin-fixture-endepunktet tillater kun nøyaktig denne
syntetiske videoens navn, katalog og private fixture-bibliotek. SDK-
readback bekreftet at katalogelementet og mediefilen var borte. Det ble
ikke gjort et nytt Guard Enable-kall eller endret eierskap før sletting.

Etter faktisk omstart var guard klar, men den gamle ID-en var ikke
lenger kjent som privat. Alle forespørsler til det slettede itemet fikk
likevel 404, og B beholdt korrekt eget innhold. Dette viser tapt varig
proveniens, **ikke en observert tilgangslekkasje**: Emby hadde selv
slettet den ressursen som metadataforespørslene gjaldt.

Baseline: `bin/native-member-growth-snapshot-results.json`, ni
metadataobservasjoner, Completed=true, PrivateKnownBeforeDeletion=true,
NewMemberPersistedAfterScan=false og
PrivateKnownAfterDeletionAndRestart=false.

## Testendring og resultat

`NativeReferenceLedger` lagrer nå faktiske ItemAdded/ItemUpdated/
ItemRemoved-hendelser for allerede registrerte private fixture-samlinger.
Nye medlemmer får både numeric ID og GUID i References. Slettede
medlemmer får begge identitetene i RemovedReferences. Slettede rot-
identiteter markeres Deleted. En lagret slettet referanse tilordnes
sentinel -1 og overskrives ikke av et senere vanlig snapshot.

Hendelsesoppdateringen skjer under guardens eksisterende lås. En
fjernet ressurs kan finnes i registeret selv hvis foreldrene allerede
er borte. Registeret oppfinner ikke en ny samling/eier ut fra en
forespørsel. Gjenbrukt native identitet reaktiveres ikke automatisk.

Den samme testen med `-RequireDurability` bestod. Etter native scan
var den nye ID-en på disk. Etter sletting og faktisk omstart var den
fortsatt kjent som privat og satt i karantene. Disk-readback bekreftet
begge slettede identiteter, den opprinnelige A-bruker-GUID-en og at
biblioteksroten fortsatt var aktiv. B sitt eget innhold var korrekt
med 200 i alle tre faser. De fem negative metadataforespørslene fikk
404 uten den nye private videomarkøren.

Rapport: `bin/native-member-growth-durable-results.json`, ni
metadataobservasjoner og eksplisitte register/readback-kontroller.

Sletting av hele roten med den nye hendelseslagringen bestod de 15
eksisterende kontrollene, inkludert B sitt eget PlaybackInfo med riktig
filkilde etter omstart. Navnebytte bestod 19 innholdskontrollerte
observasjoner; rot-ID/GUID og nytt visningsnavn var stabile. Se
`bin/native-member-events-root-regression-results.json` og
`bin/native-member-events-rename-regression-results.json`.

Totalt: 43 beståtte observasjoner med denne endringen, pluss den
separate ni-observasjoners baseline med tapt historikk. Dette er
avgrensede kontroller og ingen generell garanti for alle ruter.

## Hva dette ennå ikke beviser

Growth-testen sletter ett nytt medlem, ikke hele roten med et nytt
medlem som aldri har vært i et snapshot. Root-regresjonen bruker
allerede registrerte medlemmer og en midlertidig betrodd admin-
tilordning. Kombinasjonen ny innskanning/hel rot-sletting trenger derfor
fortsatt en egen kontroll uten et mellomliggende nytt snapshot.

Oppfølging: denne kombinasjonen er nå kontrollert med native rot-
sletting uten nytt Enable/snapshot eller eierbytte. 13 observasjoner
og SDK/register-readbacks bestod. Det lukker det avgrensede gapet
for katalogmetadata og varig klassifisering, ikke for gjenværende
avledede ressurser. Se
[NATIVE-GROWTH-WHOLE-ROOT-DELETION.md](NATIVE-GROWTH-WHOLE-ROOT-DELETION.md).

Det er ikke testet om Ready Sync-filer, gamle LiveStreamId/OpenToken
eller andre avledede native ressurser blir igjen etter denne slettingen.
Metadata-404 for et katalogelement som ikke finnes, beviser ikke
isolasjon av slike ressurser. SDK-sletting er en betrodd testhandling;
denne testen fastsetter heller ikke produktets admin-tilgangspolicy.

Tidsvinduet mellom native publisering og ItemAdded-handler, diskfeil,
avbrutt prosess midt i lagring, parallelle admin-konfigurasjoner og
legitim gjenoppretting med native identitetsgjenbruk er ikke verifisert.
Samme navn eller samme filsti er ikke i seg selv en ny samlingsidentitet.

Ingen YouTube-forespørsel, fysisk TV-/mobilapp eller produksjonsflyt for
brukerens egne API-nøkler og kanaler er testet her. Full skjerming for
den opprinnelige funksjonen er derfor fortsatt ikke bevist.

Opprydding er lest tilbake: testbrukere, biblioteker, mediefiler,
fixture, guard, begge registerfiler og tempfiler samt journal er borte,
og serverprosessen er stoppet. Alle felter i
`bin/native-member-events-cleanup.json` er true.
