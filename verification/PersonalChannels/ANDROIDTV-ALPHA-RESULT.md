# Stue-TV: faktisk Android TV-prøve

2026-10-14. Kontrollert via Home Assistant sin eksisterende Android Debug
Bridge-integrasjon, media_player.1etg_stue_androidtv_tv. Emby AndroidTv
1.8.54g, Android 12, klientnavn StueTV, TV-IP 10.0.0.95.

Backend er den isolerte Windows-serveren Emby 4.10.1.0 på 10.0.10.17:18096.
Katalogtransporten er simulert, nøkkelen er en dummy, mediet er den ekte
bufrede YouTube-prøvevideoen. Docker med ekte Google er en separat prøve.

- Appen viste prøvebruker A, vanlig YouTube-bibliotek og Public upstream
  test video. Native detaljside viste 1080p H264 og AAC stereo.
- Første avspillingsforsøk feilet: original.mp4 med native MediaSourceId
  fikk 404. Native ProcessRequest setter Static=true for original.* etter
  ServiceController-kontrollen. Kontrollen var derfor for tidlig.
- Rettelsen følger denne verifiserte normaliseringen, med kontroll av
  native metodehash, samme eier-/kilde-/leserbeskyttelse og fortsatt avvisning
  av live-/dynamiske kilder. Sju HTTP-regresjoner bestod, inkludert fremmed
  konto, feil kilde, HEAD og byte-range. Se bin/android-original-route-results.json.
- Etter rettelsen viste ADB-skjermbildet selve YouTube-prøvevideoen i appens
  avspiller. Bilde: bin/androidtv-visible-frame.png.
- Serveren rapporterte AndroidTv/StueTV/A, Public upstream test video og
  DirectStream. Pauseposisjoner økte fra 32670000 til 59550000 ticks etter
  gjenopptatt avspilling (3,267 til 5,955 sekunder).
- AudioFlinger viste Emby-prosess 6161, sesjon 97 og aktiv stereo-track
  ved 44100 Hz, uten underruns. PCM-stereo ble skrevet til SPEAKER-utgangen
  ved 48000 Hz, master mute off, 97280 skrevne rammer. Dette beviser aktiv
  lydbehandling/utgang; lyden er ikke hørt gjennom en mikrofon.
- Bytt til prøvebruker B viste B sitt eget prøvebibliotek og egen video.
  Den ferdig lastede hjemmesiden viste innlogget B og ikke A sitt YouTube-
  bibliotek eller Public upstream test video. B har den opprinnelige
  begrensede native bibliotekpolicyen; Docker-kontrollene med brede
  bibliotekrettigheter er et separat bevis for serverfiltreringen.

Testet produksjons-DLL SHA256:
2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC.
Den gamle ZIP-en og tidligere Docker-resultater gjelder ikke denne rettelsen.

Serveren var opprinnelig loopback-begrenset og avviste TV-en med HTTP 403.
Tilgang er midlertidig gitt bare til TV-ens /32-adresse; generell remote
access er fortsatt false. Før-innstillinger ligger i
bin/androidtv-alpha-network.json. Tilbakeføring er bekreftet: de lagrede
nettverksfeltene ble lest tilbake identisk etter Restore, med remote access
false. Appen viste igjen Lilflix sitt vanlige bibliotek og brukeren thomas.
Etter HOME var com.spocky.projengmenu/.ui.home.MainActivity aktiv, som ved
teststart. De to disponibel-filene på TV-en ble fjernet. Ingen hovedserver-
plugin eller hovedserverkonfigurasjon ble endret.

Android mobil og øvrige klienter er ikke prøvd. Dette er ingen garanti for
full skjerming av alle Emby-innganger eller lokale klientlagre.
