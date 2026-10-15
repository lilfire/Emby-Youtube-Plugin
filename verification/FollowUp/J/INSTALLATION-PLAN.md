# J – testbar installasjons- og utgivelsesplan

Dette er en prosedyre for en ny isolert native prøve. Den er ikke gjennomført
av J, og gir ikke klarsignal for installasjon eller tilbakeføring på Lilflix.
Pakkeverifikatoren er gjennomført separat. Bruk egne datamapper og porter,
syntetiske A/B-kontoer og ett Emby-prosesskrivende miljø per datamappe.

## Kandidatbygg og pakke

Fra repo-roten:

```powershell
dotnet build Emby.YouTubePlugin.csproj -c Release
if ($LASTEXITCODE) { throw 'Build failed' }
$zip = & ./verification/PersonalChannels/Build-ClosedAlphaPackage.ps1 -Status candidate-not-approved
if ($LASTEXITCODE) { throw 'Packaging failed' }
$digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
python ./verification/FollowUp/J/verify_package.py $zip --sha256 $digest
if ($LASTEXITCODE) { throw 'Verification failed' }
python ./verification/FollowUp/J/test_package.py $zip
```

Hash beregnet lokalt tester konsistens. Ved distribusjon må forventet ZIP-hash
komme fra en separat betrodd kanal. ZIP-manifestet autentiserer ikke avsenderen.
Bygg fra en gjennomgått, ren commit for en utgivelse; dagens prøve bygget en
arbeidskopi med andre kapitlers endringer. Lagre commit, SDK-versjon, pluginhash,
pakkehash og eksakte verktøyversjoner/-hasher i utgivelsesbeviset.

Byggskriptet pakker eksisterende DLL og bygger ikke selv. Det sjekker assembly
2.0.10.0, men ikke sammenheng mellom vilkårlig Version-parameter og faktisk
InformationalVersion, kildecommit eller godkjenningsstatus. En utgivelsesjobb
må kontrollere disse før status endres til closed-alpha-ready.

## Ren installasjon og oppgradering

1. Opprett helt ny isolert Emby 4.10.1.0-datafolder med privat tilgang for
   serverkontoen. Registrer serverversjon, OS, arkitektur og prosesskonto.
2. Stopp serveren. Verifiser pakken og kopier bare plugin-DLL og thumb.png
   til plugins. Installer/pinn verktøy i vedvarende lagring som serverkontoen
   faktisk kan kjøre. Kontroller også ffprobe ved siden av FFmpeg.
3. Start og les administratorstatus. Kontroller Creation, References, Lists,
   underliggende StaticSources/AssetSources og faktisk arbeideroppstart.
   Prøv eieravspilling og fremmedavslag, samt offentlig innhold.
4. Opprett personlige samlinger for A og B. Ta en samlet offline sikkerhetskopi
   av konfigurasjon, profiler/servernøkkel, journal/marker, bindingsdata,
   personlige medier og native bibliotekdatabase. Beskytt backup like strengt.
5. Stopp, bytt til kandidat, start og les profiler, generasjoner, native røtter
   og verktøyversjoner tilbake. Prøv begge eiere, fremmedavslag, gammel referanse,
   ny refresh og offentlig innhold. Omstart alene er utilstrekkelig: fjern og
   opprett en ny container med samme vedvarende mounts, gjenta kontrollene.
6. Prøv verktøymismatch separat i denne fixturen: manglende fil, execute-bit,
   feil arkitektur, feil versjon, manglende ffprobe og nødvendig wrappermiljø.
   Registrer at dagens produksjon ikke har en generell verktøyversjonssperre.

## Tilbakeføring som innebærer eldre tilgangskontroll

Slett alle personlige samlinger gjennom API/UI mens alfaens kontroller er
aktive. Bruk native konto-/bibliotekinventar og eierskapsjournal til å inkludere
slettede/deaktiverte kontoer; bare dagens brukeroversikt er utilstrekkelig.
Vent på Deleted, men godta ikke bare denne statusen som oppryddingsbevis.

Les tilbake at det ikke finnes personlige native røtter/barn, mediefiler,
staging, avledede Sync-filer, aktive live-kilder eller andre private kopier som
en eldre DLL kan servere. Test gamle referanser og nye forespørsler med A/B
etter omstart. Behold beskyttet historikk/backup og sperrene frem til kontrollen
er ferdig; ikke gjenopprett gammel native database med personlige biblioteker
etter at nyere tilgangskontroll er fjernet.

**Stoppkriterium:** ethvert restobjekt, mismatch, oppryddingsfeil eller manglende
inventar stopper tilbakeføringen til eldre tilgangskontroll. Behold alfaens
kontroller. E/F/B/C har dokumentert restdata og restore-/provenienshull, så
denne betingelsen er ennå ikke bevist for alle produksjonsforløp. Ikke slett
ukjente bibliotek-/mediemapper for å oppfylle den.

Når kontrollene består i isolert prøve: stopp serveren, erstatt DLL og
kompatibel konfigurasjon, start og prøv offentlig innhold og gamle private
referanser igjen. Først da er denne konkrete tilbakeføringskombinasjonen prøvd.

## Publisering

En lokal ZIP eller git-push er ikke en binær utgivelse. En eventuell GitHub
utgivelse må ha alpha-tag, prerelease=true, ZIP og separat SHA256, og beskrive
den konkrete prøvde kombinasjonen og åpne hull. Publiser bare artefakt bygget
fra utgivelsens commit. J har ikke opprettet tag, push eller GitHub-utgivelse.
Før automatisering: integrer commit-/versjonsbinding i pakkebyggeren og velg
det nødvendige godkjenningsnivået med K. Plattformtestene her gir ikke alene
closed-alpha-ready eller bredere støttestatus.
