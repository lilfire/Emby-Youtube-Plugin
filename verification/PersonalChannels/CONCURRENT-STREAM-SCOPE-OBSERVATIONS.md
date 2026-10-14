# Overlappende native Open-oppgaver med to kontoer

Isolert Emby 4.10.1.0, 2026-10-12. Testfixture/prototype, ikke produksjon.

Test-NativeConcurrentStreamScopes.ps1 brukte seks HTTP-arbeidere i en
PowerShell-runspacepool, tre per faktisk autentisert vanlig konto.
Hver fikk sin egen gyldige native strom-ID og testet:

1. Egen native Open: 200.
2. Egne strommetadata: 200 med riktig privat videonavn.
3. Den andre kontoen hentet metadata med kjent strom-ID: 404 uten privat navn.
4. Den andre kontoen provde Close med kjent strom-/PlaySessionId: 404.
5. Eierens metadata etter fremmed Close: 200 med riktig navn.
6. Eierens Close: 204.

Begge kjoringer fullforte med exit 0 og 36 observasjoner hver, totalt 72.
Mellom dem ble serveren faktisk restartet; ny BootId og Enabled/Ready ble
kontrollert. Rapporter i bin/:
native-concurrent-stream-scopes-before-restart-results.json,
native-concurrent-stream-scopes-after-restart-results.json og
native-concurrent-stream-scopes-restart-ready.json.

## Faktisk overlapp og async-kontroll

En adminbeskyttet fixture-probe satte lokal leverandor til aa avvente
Task.Delay(1500ms) for kontroll av kildeeier. Dette endrer ikke Embys
native oppgaver, laaser eller tilgangsruter. Kontroll av faktisk eier
skjedde dermed etter en asynkron venting i leverandoren, med autentisert
AsyncLocal-scope fra den faktiske HTTP-foresporselen.

En observasjon rundt den native OpenLiveStream-oppgavens ferdigstillelse
registrerte aktive invokasjoner og autentiserte subjects, uten aa lagre
tokens eller vise subject-ID-er. Begge kjoringer maalte:

- NativeOpenCalls=6 og DistinctSubjects=2.
- CrossSubjectOverlapEvents=5 og MaximumActive=6.
- ActiveCalls=0 etter at alle arbeidere var ferdige.
- Native _openStreams var tom etter eiernes egne Close.

Dette er overlappende native Open-oppgaver fra begge kontoer, ikke bare
parallelle prosesser eller planlagte requests. Maalingen beviser ikke at
alle native kritiske seksjoner eller selve kildeautorisasjonen kjorte
samtidig; serverens egne laaser kan fortsatt serialisere deler av dem.
Eierens positive kontroller passerte likevel for begge kontoer mens
deres native oppgaver overlappet og kildekontrollen skjedde etter await.

Det forste testskriptet brukte funksjonsnavnet R, som PowerShell sin
innebygde r-alias overstyrte. Arbeiderne feilet for native Open-kall;
funksjonen ble omdopt og oppsettsfeilen er bevart i
native-concurrent-stream-scopes-alias-failure.json. Den teller ikke som
tilgangsobservasjon. Kildeproben ble slaatt av etter hver vellykket kjoring.

## Bevisgrenser og opprydding

Her ble allerede utstedte referanser og riktig eier-ID ved Open brukt.
Konstruerte referanser under samtidig last, sletting/eierskifte under
Open, bakgrunnsjobber uten HTTP-scope og alle mulige scheduling-forlop
er ikke provd. Testen overforer ikke videobytes og beviser ikke fysisk
YouTube-/TV-/mobilklientavspilling eller andre medieleverandorer.
Full skjerming er fortsatt ikke bevist.

Normal fixture-opprydding leste tilbake at brukere/biblioteker var borte
og fjernet de journalforte filene. Den separate kontrollen
bin/native-concurrent-stream-scopes-cleanup.json bekrefter stoppet server
og fravaer av journal, fixture, guard, tokenregister og tempfil.
Ingen hovedserver eller produksjonskode ble endret.
