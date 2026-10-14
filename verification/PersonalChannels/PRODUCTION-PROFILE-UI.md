# Personlig YouTube-side i produksjonspluginen

Verifisert 2026-10-12 i Chrome mot isolert Emby 4.10.1.0. Hovedserveren er ikke endret. Dette er en ferdig byggestein for personlige innstillinger, ikke bevis for full skjerming av medier.

## Implementasjon

`Plugin.GetPages()` registrerer `YouTubePersonalSettings` med Emby sin innebygde `EnableInUserMenu`. Vanlige brukere får YouTube under sine preferanser. Ingen ny Harmony-endring av brukermenyen er nødvendig. Et innledende forsøk med ressursendring viste ikke menypunktet i nettleseren og ble fjernet.

`Configuration/YouTubePersonalSettings.html` og `.js` bruker produksjonsruten `/YouTubePlugin/MyProfile`. Siden viser egne kanal-ID-er og nøkkelstatus, men mottar ikke den lagrede nøkkelen. Nøkkelfeltet tømmes etter lagringsforsøk. Tomt felt beholder nøkkelen; egen avkryssing sletter den. Kanal-ID-er valideres, og lagring bruker forventet profilrevisjon. En konflikt deaktiverer lagring til brukeren har hentet profilen på nytt. Konto og aktiv visningssekvens kontrolleres før svar brukes i skjemaet.

Siden sier uttrykkelig at personlige biblioteker ennå ikke er tilgjengelige. Innstillingene brukes ikke ennå av produksjonens YouTube-kall, bakgrunnsjobber eller native bibliotekpublisering.

## Faktisk nettlesertest

To vanlige, syntetiske kontoer ble opprettet i den isolerte serveren. Kun syntetiske nøkler og kanal-ID-er ble brukt; ingen Google-kall eller ekte nøkkel ble brukt.

- A åpnet YouTube fra den innebygde innstillingsmenyen og lagret egen nøkkel og kanal. Etterpå var nøkkelfeltet tomt og nøkkelstatus viste lagret nøkkel.
- Ugyldig kanal ga synlig valideringsfeil. «Last inn på nytt» hentet A sin tidligere lagrede kanal.
- Etter faktisk brukerbytte til B ble A sin sideadresse åpnet, fortsatt med A sin `userId` i URL-en. Siden viste B sin tomme profil. B lagret egne verdier; A sin profilfil beholdt samme SHA-256 og revisjon.
- Et separat autentisert HTTP-kall oppdaterte B fra revisjon 1 til 2 mens nettleseren beholdt revisjon 1. Nettleserens neste lagring viste konflikt og deaktiverte Lagre. Ny innlasting viste den nyere kanalen og aktiverte Lagre.
- B slettet egen nøkkel og fikk status «Ingen nøkkel er lagret». Persistens ble kontrollert: revisjon 3, korrekt kanal og ingen kryptert nøkkel.
- Etter faktisk innlogging som A igjen viste siden opprinnelig kanal og lagret nøkkelstatus. A sin profilfil var fortsatt uendret på revisjon 1.

Observasjonene og sluttkontrollene er lagret i `bin/production-profile-ui-results.json` (Completed=true). Sluttilstand på disk ble kontrollert separat med riktige dokumentfelter (`Current`). En innledende avlesning brukte feil feltnavn (`CurrentGeneration`) og ga null; den brukes ikke som evidens.

`dotnet build Emby.YouTubePlugin.csproj -c Release --no-restore` passerte uten advarsler/feil. Produksjonslagerets 26 kontroller ble kjørt på nytt og passerte. Profilrutens tidligere 35 HTTP-kontroller er dokumentert i [PRODUCTION-PROFILE-SERVICE.md](PRODUCTION-PROFILE-SERVICE.md).

## Opprydding og begrensning

Testfanen ble lukket. Syntetiske kontoer, biblioteker, prøvefiler, profilfiler og isolert krypteringsnøkkel ble slettet gjennom kontrollert testopprydding. Uavhengig sluttkontroll bekreftet stoppet server og fjernet journal/profilmappe. `bin/production-profile-ui-cleanup.json` har alle åtte felt true.

Denne testen dekker Emby-web i Chrome på den oppgitte serverversjonen. Den dokumenterer ikke menystøtte i hver TV-/mobilapp, faktisk YouTube-avspilling, native medieskjerming eller alle mulige samtidige nettleserhendelser. De resterende kravene i [PLAN-FULL-SKJERMING.md](PLAN-FULL-SKJERMING.md) består.
