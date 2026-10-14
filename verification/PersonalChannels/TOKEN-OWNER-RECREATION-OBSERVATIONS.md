# Slettet tokeneier og ny konto med samme navn

Isolert Emby 4.10.1.0, 2026-10-12. Testen endret bare testbrukere i
journalfort fixture. Ingen produksjonskode eller hovedserver ble endret.

Test-NativeTokenOwnerRecreation.ps1 fullforte med exit 0 og 18 observasjoner.
Rapport: bin/native-token-owner-recreation-results.json. Completed,
SameNameDifferentGuid, DeletedOwnerAbsentReadback, OldOwnerGuidPreserved
og RestartVerified er alle true.

## Positivt oppsett og identitetskontroll

Begge vanlige eiere fikk egne native Open=200, MediaInfo=200 med riktig
syntetisk videonavn og Close=204. A sin gyldige innpakkede OpenToken var
registrert som SHA256 -> A sin bruker-GUID i fixture-registeret.

A ble deretter slettet via native Users/{Id}. Administrators userliste
ble lest tilbake og bekreftet at den gamle GUID-en var borte. En ny
vanlig konto ble opprettet med eksakt samme navn. Den fikk en annen GUID;
innloggingen bekreftet den nye identiteten og ikke-administratorrollen.
Den nye kontoen ble journalfort for opprydding for videre testkall.

## Resultater for/etter restart

Alle forsok nedenfor brukte A sin gamle gyldige OpenToken og utelot ItemId,
altsaa den tidligere paviste omgaelsesformen. Tokenverdien ble ikke
vist eller skrevet til rapport.

| Konto | For restart | Etter verifisert restart | Native sideeffekt |
| --- | --- | --- | --- |
| Den andre vanlige eieren B | 404 | 404 | Ingen A-provider-Open eller ny A-strom |
| Ny konto med A sitt gamle navn | 404 | 404 | Ingen A-provider-Open eller ny A-strom |
| A sin gamle innloggingstoken | 401 | 401 | Ingen A-provider-Open eller ny A-strom |

Ingen av de seks avviste svarene hadde A sitt private videonavn. Native
_openStreams og provider-Open-tellere ble sammenlignet for/etter hvert
forsok; dette er ikke et bevis bare ut fra HTTP-status.

B sine egne Open/MediaInfo/Close var 200/200/204 baade etter sletting av
A og etter restart. Dermed oppstod ingen global oppstarts-/tilgangssvikt
for den gjenværende eieren i dette scenariet. Restart var kontrollert med
ny BootId og Enabled/Ready=true.

Registeret ble lest etter restart: SHA256-nokkelen for A sin gamle token
var fortsatt bundet til den opprinnelige GUID-en, og var ikke overtatt
av den nye kontoen med samme navn. Guarden laster manglende bruker som
sperret eier -1; før restart sammenlignes den gamle interne identiteten
med de faktiske autentiserte kontoene. Native tabell var tom ved testslutt.

## Bevisets grenser

Testen gjelder allerede utstedt referanse, slettet bruker, bevart privat
biblioteksrot og samme-navn-konto. Den beviser ikke slettet biblioteksrot,
flyttet kilde, konstruert aldri-utstedt token, bevisst eierskapsoverforing,
korrupt register eller alle samtidige livssyklusendringer. Native provider
er syntetisk og lokal; ingen videobytes, faktisk YouTube-avspilling eller
TV-/mobilklient ble provd. Full skjerming er fortsatt ikke bevist.

Normal fixture-opprydding leste tilbake at brukere og biblioteker var
borte, inkludert den journalforte nye kontoen med samme navn. Mediefiler,
fixture, guard og register/tempfil ble fjernet. Den separate kontrollen
bin/native-token-owner-recreation-cleanup.json bekrefter stoppet server
og fravaer av journal, fixture, guard og begge registerfilene.
