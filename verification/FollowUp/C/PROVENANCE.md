# C – foreslått innholdsproveniens

Dette er en konkret produksjonskontrakt til videre implementering, **ikke en
installert rettelse**. Prøvene i REPORT.md påviser hvorfor sti-/oppskriftskontroll
alene ikke er nok. Produksjonens SubtitleConversionJob.OutputPath har heller
ikke bildets uavhengige oppskriftskontroll.

En attest må binde følgende felt før en privat avledet fil kan brukes:

| Felt | Bilde | Undertekst |
|---|---|---|
| Eierskap | Autentisert eier, aktiv samling og generasjon | Samme, samt valgt native media source |
| Original | Publiseringsattest eller annen betrodd original, SHA-256 og stabilt åpent filhåndtak | Videofingerprint og track-index/codec/metadata; ekstern sidecar har egen fingerprint |
| Transformasjon | Hele resize-/format-/enhancement-oppskriften og inspisert provider-versjon | Track, format, tidsgrenser, kontekst og alle flagg som påvirker utdata; embedded ekstraksjon er eget trinn |
| Produksjon | Attest registrert ved betrodd produksjon og atomisk ferdigstilling | Attest ved betrodd ekstraksjon/konvertering og atomisk ferdigstilling |
| Utdata | Forventet sti, lengde og SHA-256 fra produsentens egne ferdige bytes | Uavhengig forventet outputsti/oppskrift, lengde og SHA-256 |
| Utlevering | Verifiser **samme åpne fil** som faktisk sendes, også ved HEAD/304/range | Samme krav, ikke bare en senere gjenåpning av filnavnet |

En hash beregnet ved første cachetreff beviser ikke hvor innholdet kom fra.
Uattesterte gamle cachetreff må avvises eller regenereres fra en betrodd original.
En ny hash i FinishImage/FinishSubtitle alene ville godkjenne den forgiftede
cachen i reproduksjonen. Også originalen må ha etablert proveniens; å hashe en
vilkårlig fil på en tillatt originalsti løser ikke filutskiftning før produksjon.

Attesten må beholdes gjennom produsent, fabrikk, åpnet leser og skriver. Leseren
må verifisere filidentitet/bytes uten gap mellom kontroll og faktisk lesing.
Windows sitt åpne håndtak hindret våre to post-check-overskrivinger; det er ikke
et bevis for Linux rename/inode-bytte eller alle native lesere. Buffer-/hashgrenser
for store undertekster og avbrutte overføringer må avklares sammen med D/G.

Stale generasjon eller konto-/tokenavslag skal fortsatt gi generisk avslag uten
private entityheadere. Overføring som allerede holder eierlåsen følger dagens
prøvde modell: riktig innhold fullføres før profilsletting lagres. Cacheopprydding
må være separat fra tilgangsavslag og bare slette filer med dokumentert eierskap.

E/F må etablere kilde-/generasjonsattester, C må attestere asset-produksjon, og
koordinator/D må integrere kontroll av det faktiske åpne filhåndtaket i
StaticSourceGate og livssyklus/readback. Ikke utvid native hash-allowlist eller
lov generell provider-/klientstøtte basert på dette kontraktforslaget.
