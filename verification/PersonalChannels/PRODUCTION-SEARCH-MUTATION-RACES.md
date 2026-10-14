# Profilsletting ved faktisk historikkmutasjon

Isolert Windows Emby 4.10.1.0, 2026-10-13. Produksjons-DLL er uendret fra
historikkrettelsen. Hovedserveren er ikke endret. Full skjerming er ubevist.

## Kontrollerte grenser

To løp bestod: 41 og 42 observasjoner, Completed=true og null feil.
Begge gjentar den private historikkmatrisen fra
[PRODUCTION-SEARCH-HISTORY.md](PRODUCTION-SEARCH-HISTORY.md), med native
ID-/datolesing, egne positive kontroller, avviste blandede rammer,
profilsletting og omstart. De ekstra kontrollene pauser et virkelig
ReportItemsSearched-kall før native Post kan lagre noe.

NativeSearchMutationGate er en separat fixturekrok på ServiceController.Execute.
Den godtar bare et eksplisitt markert kall fra syntetisk A, og kan armeres
bare gjennom en adminbegrenset testrute. Prioritet 1000 ligger før
produksjonens tilgangsprefix; 100 ligger etter. Kroken utfører ingen
tilgangsavgjørelse, lager ingen historikkdata og erstatter ingen native
respons. Pause har timeout og slipp ligger i finally.

Før kallet tømmes A-historikken gjennom den ordinære, tillatte native
ryddingen. Ved pause må HTTP-kallet være uferdig, ID-er og datoer hos
begge kontoer være uendret og produksjonens kontrollteller være henholdsvis
0 eller 1. Dermed er det kontrollert at mutasjonen ikke allerede har skjedd.

### Før tilgangskontrollen

A-profilen slettes mens rapportkallet venter. Deleted leses tilbake før
slipp. Kallet gir deretter generisk 404, `Item not found.` på 15 bytes.
Én produksjonskontroll og én avvisning registreres. Begge kontoers native
historikk-ID-er og datoer forblir uendret.

### Etter tilgangskontrollen, før native mutasjon

Den tillatte rapporten har tatt A sin eierlås. Slettingen startes samtidig
og må vente, med Held=true, minst én venter og profil fortsatt Draft.
B må kunne lagre egen profil og få ny revisjon mens dette pågår.

Etter slipp gir den tillatte rapporten 204 og A sitt riktige element blir
markert i A-historikken. B-historikken forblir tom. Én produksjonskontroll
og null avvisninger registreres. Den ventende slettingen fullfører deretter
med Deleted, frigitt lås og null ventere. Senere rapportkall og omstart
kontrolleres også.

Dette avklarer den konkrete serialiseringen: sletting lagret før
tilgangskontroll stanser mutasjonen; sletting som kommer etter at den
tillatte mutasjonen har eierlåsen, blir lagret etter mutasjonen.

## Arkiv og sluttilstand

`bin/evidence/20261013T153745836-search-mutation/` inneholder begge rapporter,
manifest, native IL-inspeksjon, produksjons-/fixturebinærer og brukt
skript/timingkode. Rapporthashene er kontrollert ved kopiering.
`production-search-mutation-cleanup.json` dokumenterer også avlest
sluttilstand: testserver stoppet, testbrukere/biblioteker/prøvefiler og
fixture fjernet, personlige testprofiler og fixturejournal fraværende.
Installert produksjons-DLL er identisk med bygget DLL.

## Begrensning

Denne kontrollen gjelder profilsletting og dette rapportkallet. Den
beviser ikke bibliotekflytting, fil-/element-/kontosletting, tokenrevokering,
lagrings-/IO-feil, events/sockets, andre mutasjonsfamilier, alle serverbuilds
eller alle klienter. Hele PLAN-FULL-SKJERMING.md gjelder fortsatt.
