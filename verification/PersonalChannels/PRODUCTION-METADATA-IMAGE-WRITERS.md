# Metadatabilder ved samtidig profilsletting

Isolert Windows Emby 4.10.1.0, 2026-10-13. Ingen produksjonsendring eller
installasjon på hovedserveren i denne oppfølgingen. Den eksisterende
produksjonskontrollen er testet ved to faktiske native skrivergrenser.
Full skjerming er fortsatt ubevist.

## Hva som er kontrollert

28 separate løp bestod, med 5 474 observasjoner og null IsolationPass=false.
Matrisen er kryssproduktet av:

- Genres og Studios via navn, navn med /0 og numerisk ID; Tags via ID.
- Original PNG og faktisk nedskalert PNG på 80x45.
- Profilsletting før skriverens tilgangskontroll og sletting etter den.

Hvert løp har samme aktive/slettede/omstartede bildematrise som
[PRODUCTION-METADATA-IMAGES.md](PRODUCTION-METADATA-IMAGES.md): faktiske
A-/B-/anonyme HTTP-kall, egne positive bytekontroller, fremmede og gamle
referanser, brede native bibliotekrettigheter og eksperimentell guard av.
De ekstra observasjonene kontrollerer selve samtidighetsgrensen.

## Faktisk skriver, ingen simulert respons

NativeReferenceWriteGate støtter nå det konkrete GetItemByNameImage-DTO-et
som timingmål, i tillegg til GetItemImage for numeriske metadata-ID-er.
Kroken gjelder bare den syntetiske A-kontoen og et eksplisitt markert kall.
Det faktisk returnerte objektet må være native
Emby.Server.Implementations.HttpServer.FileWriter. Det pauses i sin
WriteToAsync, med prioritet før eller etter produksjonens tilgangsprefix.
Kroken gir ingen tilgangsavgjørelse og erstatter ikke native bildebytes.
Pause har timeout, og slipp utføres i finally.

Før kontrollen: A-profilen slettes og Deleted leses tilbake mens det
allerede produserte bildet venter ved skriveren. Etter slipp må svaret
være HTTP 404, den generiske teksten `Items not found.` på 16 bytes og
ingen ETag, Last-Modified, Content-Disposition, Content-Range eller
Accept-Ranges. Den faktiske skriverkontrollen må registrere én avvisning.

Etter kontrollen: produksjonens eierlås må være holdt, og slettingen må
vente mens forespørselen er uferdig og profilen fortsatt er Draft. B må
kunne lagre en profilendring og få ny revisjon samtidig. Når skriveren
slippes, fullfører den allerede tillatte overføringen med HTTP 200 og
korrekte A-bytes. Originalt bilde må ha eksakt kildehash; nedskalert bilde
dekodes og sjekkes for størrelse og A-farge. Skriveren registrerer ingen
avvisning. Først etter overføringen fullfører slettingen; Deleted og en
frigitt lås uten ventere kontrolleres. Senere kall avvises.

Dette følger samme overføringsgaranti som planen: sletting som er lagret
før skriverkontrollen hindrer utlevering; sletting etter at en kontrollert
overføring har tatt eierlåsen blir lagret etter overføringen.

## Rapporter og opprydding

`bin/production-metadata-image-writers-cleanup.json` lister alle 28 rapporter
med SHA256, kategori, rutestil, original/avledet, tidspunkt, antall
observasjoner, responsstatus og faktisk antall skriveravvisninger.
Alle rapportene har Completed=true. De 14 løpene før kontrollen har 195
observasjoner hver, og de 14 løpene etter kontrollen har 196 hver.

Sluttilstand er lest tilbake: testserver stoppet, testbrukere/biblioteker,
prøvefiler og fixture fjernet, personlige testprofiler og fixturejournal
fraværende. Installert produksjons-DLL har samme hash som bygget DLL.
Manifestet bevarer også tidligere oppryddingsstatus og hash for den faktisk
brukte timingkoden, testskriptet og fixture-DLL. Native generelle cachefiler
hevdes ikke fysisk purget.

## Det dette ikke beviser

Kontosletting, tokenrevokering, bibliotekflytting, endring av bilde under
utlevering, alle avbrudd/IO-feil og øvrige metadata-/bildefamilier er ikke
dekket av denne samtidighetsmatrisen. Den beviser heller ikke komplett
cacheinnholdsproveniens, alle serverbuilds, alle klienter eller personlig
YouTube-publisering. PLAN-FULL-SKJERMING.md gjelder fortsatt i sin helhet.
