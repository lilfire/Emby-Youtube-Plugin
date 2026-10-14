# Slettet vanlig biblioteksrot: omstartfeil

Undersokelse 12. oktober 2026, isolert Emby 4.10.1.0. Hovedserveren
og produksjonskoden er ikke endret. Testen bruker to vanlige testkontoer,
to native HomeVideos-biblioteker og lokale syntetiske MP4-filer.

## Faktisk test

`Test-NativeRootDeletion.ps1` utforte ekte
`POST Library/VirtualFolders/Delete` for A sin biblioteksrot (204).
Roten var deretter borte fra VirtualFolders/Query, og admin sin direkte
foresporsel til den gamle rot-ID-en fikk 404. B sin egen video hadde
korrekt ID/navn med 200 bade for og etter sletting; B sin foresporsel
til A sin video fikk 404.

For den betrodde adminhandlingen var bare A-roten midlertidig tilordnet
testadmin; B-roten beholdt B som eier. A sin tilgjengelighet under dette
intervallet er ikke testet. Den slettede rotens mapping ble med hensikt
beholdt pa disk. Dette er et livssyklusfeilscenario, ikke et bevis pa
omgaelse av en ordinary konto.

Den opprinnelige testen, ved forste HTTP-svar etter faktisk
stopp/start med ny prosess-ID, fikk alle fire kontroller
500: Public server info, guard-endepunktet, B sin egen video og B sin
foresporsel til den gamle A-videoen. Ingen av de fire svarene inneholdt
de syntetiske private videonavnene. Resultatet er en tilgjengelighets-
feil for et fortsatt gyldig privat bibliotek, ikke en observert lekkasje.

Opprinnelig rapport: `bin/native-root-deletion-first-response-results.json`, 11 observasjoner,
Completed=true betyr at eksperimentet er utfort, ikke at isolasjon er
godkjent. Source-level gjennomgang viser at PrivacyGuard.Enable kaster
`ArgumentException("Unknown private library root")` nar lagret rot-ID
ikke finnes, for eierskapskartene bygges. Dette er den identifiserte
oppstartsrisikoen som er konsistent med 500-resultatene; denne forste
testen lagret ikke exception-body. En ny kontroll venter pa guard-ready
i opptil 30 sekunder og observerer vedvarende 503 med gammel logikk,
og loggen bekrefter Unknown private library root. Den rapporten er naa
`bin/native-root-deletion-results.json`. Se
[NATIVE-REFERENCE-LEDGER-EXPERIMENT.md](NATIVE-REFERENCE-LEDGER-EXPERIMENT.md).

## Nodvendig losning og neste verifikasjon

En manglende rot ma behandles som en slettet privat samling, slik at
gyldige andre samlinger kan lastes. Bare a hoppe over rot-ID-en er
ikke tilstrekkelig: etter omstart ma gamle item-, kilde-, token-, stream-
og Sync-referanser fortsatt ha en kjent privat opprinnelse og nektes.

Et varig register trenger stabil samlings-ID, eierens Emby-bruker-GUID,
native rot- og medlemsidentiteter, og en slettet/inaktiv tilstand.
Sletting ma sperre samlingen og dens avledede referanser, og den
tilstanden ma leses for private foresporsler godtas ved oppstart.
Gjenoppretting av samme biblioteknavn eller brukernavn ma ikke arve
tidligere private referanser. Token-ledgeren alene dekker ikke dette.

Den lokalt installerte SDK-dokumentasjonen beskriver ILibraryManager
ItemRemoved, ItemAdded og ItemUpdated. Disse er mulige integrasjonspunkter,
men hendelsesrekkefolge, dekning ved rot-sletting og persistens ma testes.
Oppstartsavstemming er nodvendig ogsa hvis en hendelse ikke ble lagret
for prosessen stoppet. Ingen slik produksjonslosning er implementert.

En avgrenset prototype for slettede samlinger er naa testet:
B sitt eget innhold ma fortsatt returnere korrekt 200 etter omstart,
gamle A-referanser ma nektes, og en ny samling med samme navn ma fa
egen identitet. Metadata/PlaybackInfo-recovery er bestatt, mens
samme-navn-gjenoppretting ikke er testet. Ready Sync-filer og aktive strommer trenger egne kontroller;
denne metadata-testen sier ikke noe om de referansene.

## Opprydding og begrensning

Testbrukere og biblioteker ble lest tilbake som fjernet. Syntetiske
mediefiler, guard, testplugin, ledger og journal ble fjernet. En separat
etterkontroll bekreftet at EmbyServer-prosessen var stoppet (den generelle
cleanup-rapportens umiddelbare ServerStopped=false var en prosess-exit-race).
Se `bin/native-root-deletion-cleanup.json`.

Dette beviser ikke full skjerming eller YouTube-avspilling i alle klienter.
Omfanget er kontotilgang til serveren; lokale kopier og nettleserhistorikk
etter tidligere legitim tilgang ligger utenfor den aksepterte garantien.
