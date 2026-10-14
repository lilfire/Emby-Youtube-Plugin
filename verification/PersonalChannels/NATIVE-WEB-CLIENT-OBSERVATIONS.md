# Faktisk Emby-webtest i Chrome

Dato: 2026-10-11. Emby 4.10.1.0, servernavn `Isolated Watch State Test`.

Senere avklaring: brukeren valgte skjerming mellom Emby-kontoer ved tilgang
til serveren. Gammel lokal fanetittel er derfor et bevart klientfunn, men
ikke et moteksempel mot den avklarte servergarantien.
Den separate testpluginens guard var Enabled=true og Ready=true, BootId
`3e8b63bbdbc94946b5a99d7845fbea9a`. Produksjonspluginen er uendret.

Dette er observasjoner fra faktisk brukergrensesnitt gjennom nettleserverktoyet,
ikke en automatisert API-test. To vanlige testbrukere hadde hvert sitt native
homevideos-bibliotek, egne bibliotekrettigheter og en seks sekunders MP4.
A hadde blatt videobilde, B rodt. Begge videoer er syntetiske.

| Handling | Observert resultat |
| --- | --- |
| Innlogging som A | My Media viste bare Private Native Fixture a. |
| A apner sitt bibliotek | Ett element, PrivateNativeVideo_a_client, id 2371. |
| A spiller egen video | Faktisk blatt videobilde ble observert i avspilleren. |
| Change User, innlogging som B | My Media viste bare Private Native Fixture b og Bs video. |
| B bruker Tilbake til As gamle detaljside | Innholdet viste generell foresporselsfeil, Bs bibliotek i sidefeltet, ingen videotittel eller avspillingsknapp i selve siden. |
| Samme historikkhandling, nettleserfane | Verktoyets fanetittel var fortsatt PrivateNativeVideo_a_client. Dette er en klientrest av tidligere autorisert innhold og kan ikke regnes som full skjerming pa samme nettleserprofil. |
| B laster As gamle detaljlenke pa nytt | Generell foresporselsfeil; fanetittelen ble Isolated Watch State Test. |
| B apner sin video | Egen detaljside id 2372 med korrekt navn. |
| B spiller egen video | Faktisk rodt videobilde ble observert i avspilleren. |
| Hurtigbytte tilbake til A via brukermeny | Startside og sidefelt viste bare As bibliotek. |
| A apner Bs tidligere observerte detaljlenke | Generell foresporselsfeil, ingen Bs metadata eller avspillingsknapp i siden. |
| Sign Out | Innloggingsskjermen ble bekreftet; testfanen ble lukket. |

Observasjonene beviser disse positive avspillingskontrollene og avvisningen
av de provde fremmede detaljsidene. De beviser ikke alle klientruter,
nettleserhistorikkrydding, HTTP-cache, flervindu-/offlineforlop eller andre
TV-/mobilapper. Ingen faktiske YouTube-kilder eller API-nokler ble brukt.
Fanetittelresten er bevart som funn, ikke bortforklart som en bestatt kontroll.

## Separat slettet-eier-test etter webtesten

`Test-NativeOwnerDeletion.ps1` brukte samme isolerte native biblioteker.
Rapport: `bin/native-owner-deletion-results.json`, ti HTTP-observasjoner.
Faktiske positive kontroller for A/B gav 200 med eget markornavn, B mot A 404.
A ble slettet med API-readback. As gamle token gav 404, Bs egen metadata
fortsatt 200, Bs tilgang til As gjenværende video 404.

Etter bekreftet prosessbytte ved restart gav bade offentlig serverinfo,
Bs egen metadata, Bs fremmede foresporsel og As gamle token HTTP 500.
Det nye serverlogget inneholdt `Unknown root owner`, kontrollert som en
boolsk markor uten aa skrive ut logginnhold eller hemmeligheter. Kodeinspeksjon
viser at gjenoppretting kaller `PrivacyGuard.Enable` med den slettede eierens
GUID og at dette kaster nar brukeren ikke finnes. Testen viser derfor en
oppstarts-/tilgjengelighetsfeil; feilresponsene er ikke et fungerende
sikkerhetsbevis. Den viser ikke hvor mange andre API-ruter som ville feile.

Opprydding i den forste kjoringen feilet fordi normal shutdown og readiness
ikke kunne brukes pa den feilstartede serveren. Bare den verifiserte isolerte
EmbyServer-prosessen ble stoppet, deretter ble standard fixture-opprydding
kjort med exit 0. `bin/native-client-cleanup.json` bekrefter UsersGone,
LibrariesGone, FixtureGone, GuardGone, MediaGone og ServerStopped=true.
Testscriptet har na en verifisert prosess-fallback for dette feilforlopet;
hele testen er ikke kjort pa nytt etter endringen i oppryddingen.

En videre losning trenger varig behandling av foreldrelost eierskap: sletting
ma sperre gammel identitet og gamle referanser, beholde eierskapsinformasjon
sa lenge private referanser finnes, og la andre eiere fungere etter restart.
Dette er et krav utledet fra funnet, ikke en implementert eller verifisert
produksjonslosning.
