# Samme ra YouTube-ID i to personlige samlinger

Isolert Emby 4.10.1.0, 2026-10-12. Test-NativeClientFixture opprettet
to faktiske vanlige kontoer; Test-SharedChannelVideo.ps1 brukte dem med
den eksisterende syntetiske kanalmodellen. Ingen YouTube-nettverk eller
avspilling, ingen produksjonsendring.

De tidligere Run-TwoOwners/Run-Lifecycle-rapportene provde allerede ra
felles video-ID. Run-TwoOwners hadde administrator som den ene eieren.
Den nye testen verifiserte to ikke-admin-kontoer med dagens prototype
og la til et fremmed mutasjonsforsok pa avspillingshistorikk.

## Faktisk kjoring

shared-channel-video-results.json har Completed=true, ni observasjoner,
DistinctChannelAndItemIds=true, IndependentWatchedState=true og
ForeignMutationDenied=true. Kommandoen fullforte med exit 0.

Begge kanaler materialiserte ProviderIds.YouTube=shared00001 og samme
ChannelItemInfo.Id, men separate native kanal-/element-ID-er. Eierens
kopi kunne leses med 200; den andre kopien ble avvist med 404 i begge
retninger. A markerte sin egen kopi som sett (200). A sin UserData.Played
var da true og B sin egen kopi hadde Played=false. A sitt PlayedItems-
kall mot B sin kopi fikk 404; B sin Played-verdi var fortsatt false.

Dette viser at felles ekstern video-ID ikke i seg selv krever felles
eieridentitet eller seerhistorikk i denne kanalmodellen. Det beviser ikke
at produksjonens YouTube-import, kvote, API-cache eller vanlige native
biblioteker allerede bruker denne modellen.

## Navn er ikke et sikkert identitetsgrunnlag

Den tidligere autoritative lifecycle-results.json inneholder den bestatte
kontrollen: Changing channel Name changes identity despite the unchanged
declared Id property. Run-Lifecycle.ps1 provde dette faktisk ved omkonfigurering.
Det er derfor ikke nok aa anta at IChannel.Id alene holder samlings-ID-en
stabil ved endret bruker-/samlingsnavn.

Den endelige samlingen trenger en varig eier-GUID og egen immutable
CollectionId, pluss verifisert mapping til den valgte native modellen.
Mutable visningsnavn ma ikke overta eksisterende eierskap eller etterlate
gamle ubeskyttede elementer. En DTO-visningsalias eller annen navnemapping
er ikke implementert/provd av denne testen. Dette er fortsatt en egen
integrasjonsgrense, ikke lost av de ni kontrollerte foresporslene.

## Opprydding og begrensninger

Begge syntetiske kanaler ble eksplisitt prunet og konfigurasjonsfilen
fjernet. Etter vanlig journalfort fixture-opprydding ble serveren startet
uten fixture/guard for en separat admin-readback: Channels, channel-search
og shared-video-search hadde null gjenværende provde kanal/video-elementer.
Rapport: bin/shared-channel-video-cleanup-readback.json.

Serveren ble stoppet igjen. bin/shared-channel-video-final-cleanup.json
bekrefter fravaer av prosess, journal, fixture, guard, profilkonfigurasjon
og tokenregister. Ingen hovedserver ble endret.

Dette gjelder syntetiske Emby-kanaler, ikke faktisk YouTube-avspilling,
vanlig-bibliotek-import, API-nokkelvalg eller TV-/mobilklienter. Full
skjerming er fortsatt ikke bevist.
