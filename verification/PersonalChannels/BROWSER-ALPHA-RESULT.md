# Nettleserkontroll av lukket alfa

Kontrollert 2026-10-14 i Chrome mot isolert Emby 4.10.1 på port 18096.
Vanlig prøvebruker, produksjonsjobb og produksjonsbibliotek; simulert Google-
katalogtransport og dummy API-nøkkel, men ekte bufret YouTube-prøvevideo.

- YouTube vises under brukerens Preferences.
- Lagring av kanal fra skjemaet ender i «Biblioteket er klart med 1 videoer».
- Biblioteket «YouTube» og lesbar videotittel vises på den vanlige hjemmesiden.
- Videoens native detaljside viser H264/AAC og kodet katalogbeskrivelse.
- Play åpner vanlig Emby-avspiller og viser selve prøvevideoen.
  DOM-observasjon: currentTime 15.39593, paused false, readyState 4, error null.
- Sletting viser forklaring og «Bekreft sletting»; «Avbryt sletting» går
  tilbake uten å slette samlingen.
- Kanalbytte med blankt nøkkelfelt ender igjen i «Biblioteket er klart med
  1 videoer». Lagret nøkkel beholdes og ny prøvegenerasjon er journalført.
- Vanlig Change User og innlogging som native-privacy-fixture-b viser B sitt
  eget prøvebibliotek og prøvevideo; A sitt YouTube-bibliotek er ikke synlig
  på B sin ferdig lastede hjemmeside. Menyen bekrefter innlogget B.

Android/Android TV-test er klargjort på lokalnettadressen
http://10.0.10.17:18096, server «Isolated Watch State Test».
Prøvekonto native-privacy-fixture-a har ikke passord. Serveridentitet og
versjon er kontrollert fra vertsmaskinen; tilgang fra enheten, bilde og lyd
må fortsatt bekreftes. Ingen ny brannmurregel eller portvideresending er laget.

Denne kontrollen beviser ikke ekte Google-API i nettleserflyten, Android-
avspilling, Docker-avspilling eller full skjerming mellom alle klienter.
Hovedserveren er ikke endret. APK/TV-apptest gjenstår.

## Administratorlagring

Den faktiske nettlesertesten fant at SaveConfiguration-endepunktet ignorerte
de nye alfa-feltene, selv om skjemaet viste lagret-status. Endepunktets nullable
DTO og feltkopiering er rettet for alle åtte PersonalYouTube-felt. Bygg bestod
med null feil og advarsler, og den isolerte serveren lastet den rettede DLL-en.

Fra Chrome ble aktivering, alle tre verktøystier og fire grenser endret.
Serverens GET av plugin-konfigurasjon bekreftet true, stiene, 51 videoer og
65/130/260 MiB som 68157440/136314880/272629760 byte. Positiv avlesning:
bin/alpha-browser-admin-positive.json. Prøveinnstillingene er deretter satt
tilbake fra skjemaet; aktivering er false. Dette tester feltlagring, ikke
omstart med ekte Google fra Windows. Den kontrollerte arbeideren har egen
testkonfigurasjon og beholder Android-prøvebiblioteket.

Denne rettelsen endrer kandidat-DLL-en. En eldre ZIP eller Docker-DLL beviser
ikke endepunktet i denne rettede versjonen.

## Feilmeldinger og sletting

B fikk en kontrollert Google 403/quotaExceeded-respons fra testtransporten,
som ble behandlet av produksjonskatalogen og jobben. Chrome viste:
«YouTube-kvoten for nøkkelen din er brukt opp. Prøv igjen når kvoten er
tilgjengelig.» Denne prøven gjorde ingen ekte Google-kall.

B sin disponibelprofil ble slettet fra skjemaet etter bekreftelse. Siden
viste slettet samling, ingen lagret nøkkel og tom kanalliste. Innskriving av
«ikke-en-kanal» og Save ga en forklaring om gyldige UC-ID-er. De øvrige
feilkodene er ikke individuelt prøvd i nettleser i denne kontrollen.
