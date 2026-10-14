# Gjenstaende grenser for full skjerming

Kontrollert 2026-10-11. Dette er en undersokelse, ikke en produksjonsendring
eller en godkjenning av full skjerming.

Brukeren har avklart at kravet gjelder mellom Emby-kontoer ved tilgang til
serveren. Allerede lagrede data pa samme lokale OS-/nettleserprofil er
utenfor denne garantien. Klientenes foresporsler til serveren og fungerende
biblioteker i alle klienttyper er fortsatt innenfor kravet.

## Dokumentert native privatmerking: ny vanlig-bibliotek-test

Emby dokumenterer [MakePrivate](https://dev.emby.media/reference/RestAPI/UserLibraryService/postItemsByIdMakeprivate.html)
og [Items/Access](https://dev.emby.media/reference/RestAPI/UserLibraryService/postItemsAccess.html).
Den tidligere kanaltesten i README kunne ikke alene avgjore hvordan disse
virket pa vanlige biblioteker. Derfor ble normal Folder og Video provd
separat pa den isolerte 4.10.1.0-serveren, med guard Disabled.

`Test-NativeItemAccess.ps1` fullforte med exit 0. Rapporten
`bin/native-item-access-results.json` har 14 observasjoner:

| Handling | Vanlig bruker med tilgang til biblioteket | Admin |
| --- | --- | --- |
| MakePrivate, biblioteksrot | 400 | 400 |
| MakePrivate, video | 400 | 400 |
| Items/Access None for annen bruker, rot | 403 | 403 |
| Items/Access None for annen bruker, video | 403 | 403 |

Egen metadata var 200 bade for og etter. Annen bruker fikk fremmed metadata
med markornavn og PlaybackInfo med 200 etter kallene. Fremmed Download gav
200; denne nye testen gjorde ingen byte/hash-verifikasjon og ma ikke alene
beskrives som bevis for hele filens innhold. Tidligere baseline-rapporter har
egne byte/hash-kontroller. De avviste API-kallene beviser ikke at tilgang ble
lagret, og heller ikke at disse rutene er ubrukelige for andre elementtyper.

Fixture-oppryddingen bekreftet at brukere, biblioteker, plugin, guard og
mediefiler var borte. Dens umiddelbare prosesskontroll registrerte
ServerStopped=false; en etterfolgende autoritativ Get-Process-kontroll
bekreftet null EmbyServer-prosesser og ingen aktiv klientjournal. Den
opprinnelige oppryddingsrapporten er beholdt. Ingen hovedserver ble endret.

## Serverutlevering og allerede lagret klientinnhold

Emby beskriver [lokal offline-avspilling](https://emby.media/support/articles/Offline-Access.html)
for Android Mobile, iOS og Windows. [Download Options](https://emby.media/support/articles/Sync.html)
beskriver dessuten at webnedlasting bruker nettleserens vanlige Downloads-mappe,
og at iOS kan lagre i en selvvalgt mappe via Apple Files.

Slutning fra disse dokumenterte mekanismene: en serverplugin som bare vurderer
foresporsler, kan nekte ny utlevering, men kan ikke via den vurderingen hindre
lesing av en kopi som allerede finnes pa en frakoblet klient. Dette er ikke
et nytt runtime-bevis for at Emby-apper faktisk blander to brukeres downloads.
Det er en forskjell i hvilket system som ma handheve hver garanti.

Den faktiske Chrome-testen fant allerede en gammel videotittel i fanen
etter brukerbytte og historikknavigasjon, selv om serveren nektet detaljsiden.
Se NATIVE-WEB-CLIENT-OBSERVATIONS.md. Ingen av de provde serverfiltrene har
bevist sletting eller isolering av slik klienthistorikk.

## Arbeid som ville lukke konkrete funn

Disse punktene bevarer kravet om vanlige biblioteker og alle klienttyper.
Ingen ekstern gateway, annen biblioteksmodell eller utkobling av funksjoner
er her brukt som erstatning for full skjerming.

1. En varig eierskapstabell ma knytte bruker-GUID, samling, biblioteksrot,
   elementer og avledede Sync-referanser sammen. Gamle referanser trenger
   bevart eierinformasjon selv om kilde eller bruker er slettet.
2. Manglende/slettet eier ma sette bare vedkommendes samling i sperret tilstand.
   Den gamle identiteten skal ikke gjenoppsta ved gjenbruk av navn, og andre
   eiere ma beholde fungerende tilgang etter restart. Slettet-eier-testens
   globale oppstartsfeil oppfyller ikke dette.
3. Tilgang ma sjekkes der native ruter utleverer eller endrer data, inkludert
   ferdige filer og meldinger. En dokumentert serverkontrakt eller eksplisitt
   verifisert serverversjon er nodvendig; intern Harmony-kode og et endelig
   sett passerende tester er ingen garanti for fremtidige interne endringer.
4. Hver aktuell klientfamilie trenger positiv egen-avspilling og negative
   kontroller av foresporsler til serveren ved brukerbytte og gamle lenker.
   Klientene som laster ned trenger kontroll av eier og fremmed tilgang ved
   filoverforing fra serveren. Lesing av allerede overforte filer uten
   serverkontakt er utenfor den avklarte garantien. Webtester og serverens
   ReadyToTransfer erstatter ikke faktisk klientkompatibilitet.
5. Private data som allerede er utlevert til samme lokale OS-/nettleserprofil
   krever lokal isolering/sletting. Brukeren avklarte at dette er utenfor
   servergarantien; det er derfor ikke et gjenstaende hinder for akkurat
   denne garantien. Det er heller ikke beskrevet som lost av pluginen.

Produksjonsimplementasjon av disse punktene er utenfor den opprinnelige
instruksen om kun undersokelse. De isolerte testene er fortsettelsen av
brukerens tillatelse til sma verifikasjonstester. Full skjerming er fortsatt
ikke oppnadd eller bevist.
