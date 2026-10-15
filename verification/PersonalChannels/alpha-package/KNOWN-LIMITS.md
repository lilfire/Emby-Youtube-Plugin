# Lukket alfa: verifisering og begrensninger

Denne pakken er for kontrollert lukket alfa på Emby 4.10.1.0. Den er ikke en
garanti for full skjerming eller alle klienter. Testene og kildedeltavurderingen
er dokumentert i verification/PersonalChannels.

Status 2026-10-15: 2.0.11-alpha.1 er installert og aktivert på Lilflix, se
[utrullingsrapporten](../LILFLIX-ALPHA-DEPLOYMENT.md). Ingen offentlig binærutgivelse
er dokumentert. Senere isolerte undersøkelser påviser tilgangshull i Similar,
anbefalinger, metadata, spillelister, Sync, live-referanser, audio/HLS og
cacheinnhold. Sletting av profil sperrer ikke alle disse inngangene.
[Rapportindeksen](../../FollowUp/K/INDEX.md) viser versjoner, bevis og
godkjenningsnivåer. Bruk fortsatt bare kontrollert prøveinnhold.

Kildeoversiktens native skrivebarriere er ikke aktiv på Lilflix/Linux;
`SourceBarrierInstalled=false` gir full skanning som reserve. Oppstart og
utvalgte HTTP-kall er verifisert der, men Windows-fixturens ytelsestall gjelder
ikke som dokumentasjon for Linux eller andre serverbuilds.

- Full skjerming på alle Emby-innganger og klienter er ikke bevist. Administrator
  og serverhost er betrodd. Bruk bare kontrollert prøveinnhold i kandidaten.
- Windows-testen omfatter native publisering, metadata, eierreferanser,
  kanalbytte, sletting, faktisk omstart og et faktisk avbrudd i Preparing.
  Google-transporten i denne testen er kontrollert.
- Kandidat-DLL-en med administratorlagringsrettelsen bestod ekte Google,
  personlig nøkkel, native HTTP-strømmer, omstart, sletting, to kanaler og
  faktisk prosessavbrudd under Buffering med automatisk gjenoppretting i Docker.
  Én video fra hver kanal og titler fra Google ble kontrollert.
- Ugyldig nøkkel og brukt opp Google-kvote er observert i Docker. Ny jobb med
  beholdt gyldig nøkkel etter kvotefeilen kom tilbake til Ready.
- Chrome-brukerflyten er prøvd: innstillingsmeny, kanalvalg, native bibliotek,
  faktisk videoavspilling, kanalbytte med beholdt nøkkel og avbrutt sletting.
  Google-katalogen var simulert, med ekte YouTube-prøvemedia.
- Administratorens åtte alfa-felt er lagret fra Chrome og lest tilbake fra
  serveren. Den første prøven fant en manglende DTO-mapping som er rettet.
- Kvotefeilmelding, ugyldig kanal-ID og bekreftet profilsletting er prøvd i
  Chrome. Kvoteprøven brukte en kontrollert Google-feilrespons; øvrige
  feilkoder er ikke individuelt prøvd i nettleseren.
- Emby Android TV 1.8.54g på stue-TV-en med Android 12 viste faktisk video.
  Avspillingsposisjonen økte, og et aktivt Emby-lydspor skrev stereo til
  høyttalerutgangen uten mute/underruns. Lyden er ikke hørt med mikrofon.
  Dette var Windows-backend med simulert katalog og ekte YouTube-media.
- TV-prøven fant og rettet 404 på original.mp4 uten Static-parameter.
  Samme normalisering som verifisert native kode brukes før eierkontrollen.
  Riktig eier, fremmed bruker, feil kilde, HEAD og byte-range er kontrollert.
  Den rettede DLL-en har også en fersk ekte Google-publisering i Docker,
  med egen/fremmed original-rute kontrollert for begge videoer.
- Android mobil og øvrige klienter er ikke individuelt prøvd. Beskrivelser
  med HTML-tegn kan vises som HTML-entiteter i den gamle Android TV-appen.
- Preparing-avbrudd er prøvd på Windows; Linux-avbruddet gjelder Buffering.
- En HTTP 200 med MP4-data beviser ikke faktisk avspilling i TV-/mobilapp.
  Øvrige klienter skal merkes uverifisert, ikke erklæres støttet gjennom
  bare serverens rutetester.
- Oppdatering er manuell gjennom «Lagre og oppdater». Kandidaten velger et
  begrenset nylig utvalg per kanal; den kopierer ikke hele kanalen.
- Verktøyene installeres separat, og opptatt Google-kvote håndteres med feil,
  ikke gjennom en annen brukers eller en global reservenøkkel.

Testresultatene ovenfor beskriver testfasen før Lilflix-utrullingen. Kilde-
dokumentet er oppdatert; den historiske ZIP-pakken er ikke pakket om av K.
