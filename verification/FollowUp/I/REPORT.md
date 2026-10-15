# I — brukerflyt, administratoroppsett og metadata

Utført 2026-10-14. Kapittelet er undersøkt, med rettelser og isolerte regresjonsprøver. Det er **ikke ferdig godkjent**: native serveravlesning etter lagring/omstart og fysisk Android TV-gjengivelse gjenstår.

## Miljø og faktisk testinngang

- Utgangspunkt: commit `e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7`, `2.0.10-alpha.1`. Endringene ligger i arbeidskopien, uten ny commit eller installasjon på Lilflix. Eksisterende endringer i andre kapitlers fixture-filer ble ikke endret av dette arbeidet.
- Windows, .NET SDK 8.0.416, produksjonsmål net6.0. Bygg: Release, null advarsler/feil. DLL SHA256: `ECCB1B92D991886551DD462B8E99FE1ED31F23C82861910BE234E792BD8E55B0`.
- Microsoft Edge 155.0.4283.45, headless, lokal HTTP-inngang på loopback port 18217. Produksjonens HTML, JavaScript-kontrollere og nettleserens ekte DOM brukes. Emby-komponenter/BaseView og API-transport er testadaptere; promises gir kontrollerte svar, feil og svarrekkefølger.
- Ingen Emby-server ble startet eller endret i denne prøven. Emby 4.10.1.0 er versjonen i de historiske startkildene, **ikke en ny integrasjonsprøve her**. Ingen Google, downloader, fysisk klient eller HA-tilkobling ble brukt.
- C#-prøven kompilerer den samme nye valideringsklassen som produksjonsbygget. Metadataobservasjonene reproduserer det inspeksjonsbekreftede publisher-uttrykket, ikke hele native publiseringskjeden.

## Funn, reproduksjon og rettelser

| Område | Status og bevis | Endring / begrensning |
|---|---|---|
| Sene jobbstatussvar | Tre reproduserte feil på originalkontrolleren: svar etter kontobytte ble vist; eldre svar overskrev nyere; status ble beholdt ved pause. `BASELINE-EVIDENCE.json` inneholder tre vellykkede reproduksjoner. | Svar bindes til forespørselens konto, API-klient, visningssekvens og egen jobbsekvens. Profilen bindes også til klienten. Private felt tømmes ved ugyldig kontekst; gamle svar brukes ikke. |
| Feilkoder | Alle produksjonskodene fra Jobs, Service, Catalog, JobRuntime og StorageBudget er kartlagt. 11 feilvisninger, inkludert ukjent kode, prøves med syntetisk privat detaljfelt. | Egne meldinger for CleanupFailed, RefreshFailed og StatusUnavailable. Kun faste tekster og textContent; rå detaljer vises ikke. Kvotemeldingen antar ikke lenger personlig kvotescope. |
| Faner og mutasjoner | To separate DOM-visninger sender samme revisjon; kontrollert transport gir én vinner og én 409-konflikt. Dobbel lagring/sletting, slettingsbekreftelse/avbrudd, blank/eksplisitt slettet nøkkel og serveravlesning av returnert profil prøves. | Ny innlasting ignoreres mens mutasjon pågår. Konflikt sperrer lagring/sletting til ny innlasting. Dette prøver kontrollerens reaksjon; ekte servers samtidighet og diskpersistens er ikke prøvd her. |
| Navigasjon og sesjon | Positive eierkontroller, fremmed profilsvar, konto-/serverbytte, gamle svar, endret jobbrevisjon og 401/403 prøves. | Polling stoppes ved navigasjon, ugyldig identitet og 401/403. Felt og eksisterende jobbstatus tømmes. Ekte tidsutløpt Emby-token er fortsatt uprøvd her. |
| Administratorvalidering | 14 C#-kontroller: gyldige eksisterende filer, deaktivert/blankt oppsett, relativ/manglende sti, mappe, kontrolltegn, antall, størrelser, relasjoner og øvre grenser. Nettleseren prøver tomme/ugyldige tall og størrelsesrelasjoner. | `Configuration/PersonalYouTubeConfigurationValidation.cs` validerer effektivt DTO + eksisterende konfigurasjon under SaveLock, før noen felt muteres. Hele MiB, video ≤ samling ≤ totalbudsjett. Absolutte eksisterende filer kreves ved aktivering; utførbarhet/versjon er ikke attestert av File.Exists. |
| Administratorstatus | Kontrollert respons viser stoppet arbeider, manglende kontrollkroker og medieverktøy, uten rå detaljer. Svar etter pause ignoreres. | Ny sjekkeknapp leser den eksisterende administratorruten PersonalServerStatus. Viser lagret alfa-innstilling, arbeider, Creation/References/Lists og verktøyfiler; minner om omstart. Installed-feltene er ikke fullstendig bevis for alle runtime-/skriverkroker. |
| Brukerens grenser/nøkkel | Skjemaet forklarer metadata-nøkkel, lokal buffer, manuell oppdatering, administratorens utvalg/lagring og delt totalbudsjett. Retain/clear prøves med riktig returnert nøkkelstatus. | Brukeren får ikke sette administratorgrenser. Administratoren informeres om staging og faktisk lavere tilgjengelig budsjett. Eksakte effektive grenser per bruker returneres ennå ikke av MyProfile/MyJob. |

Minimal reproduksjon av svarfeil: start MyJob for A; bytt klientens aktive konto til B før promise fullføres; svar med B-eid Ready-status. Originalen sammenligner bare dagens konto med svarets eier og viser svaret i A-profilvisningen. Rettelsen avviser fordi forespørselens fangede identitet er endret. Separate positive A-kontroller viser fortsatt Ready og lagret profil. Fremmed profilsvar og serverbytte avvises uten gamle kanalverdier.

`YouTubeConfigSaveService` returnerer også en fast melding ved malformed JSON i stedet for parserens rå feiltekst. Rutenes eksisterende admin-autorisasjon er beholdt; HTTP-status for ny validering og persistens etter avslag må bekreftes i ekte Emby.

## Metadata: HTML-entiteter og forslag til G/E/H

Inspeksjon viser at Catalog tar `snippet.description` som streng. NativePublisher lagrer `WebUtility.HtmlEncode(metadata.Description)` som Overview. Det gir:

| Input | Nåværende Overview |
|---|---|
| `Rock & roll` | `Rock &amp; roll` |
| `Rock &amp; roll` | `Rock &amp;amp; roll` |
| `<script>alert('synthetic')</script>` | `&lt;script&gt;alert(&#39;synthetic&#39;)&lt;/script&gt;` |

Dette forklarer en **mulig** entitetsvisning i en klient som gjengir Overview som ren tekst, og dobbel koding av allerede kodet input. Det beviser ikke den gamle Android TV-appens renderer. Den historiske TV-rapporten dokumenterer avspilling på AndroidTv 1.8.54g, men ingen paret beskrivelses-/entitetsprøve.

Forslag til G/E som eier Catalog/NativePublisher: definer først om Overview-kontrakten er ren tekst eller HTML, og prøv begge klientrenderere med vanlig ampersand, allerede kodet ampersand, numeriske entiteter, vinkelparenteser, bokstavelig script og kodet script. Normaliser høyst én gang ved den avklarte kildegrensen; ikke erstatt dagens HTML-koding med ukritisk HtmlDecode eller ukodet markup. HTML-rendering må fortsatt kode/sanitere ved riktig grense. Dersom TV krever ren tekst og Emby-web krever HTML, må klient-/DTO-grensen undersøkes fremfor å velge én uverifisert global konvertering. Ingen endring er gjort i andre kapitlers metadatafiler.

## Kontroller og reproduksjon

Kjør fra prosjektroten, sekvensielt; port 18217 og nettleserprofilen må være ledig:

```powershell
node verification/FollowUp/I/Run-Browser.mjs --baseline
node verification/FollowUp/I/Run-Browser.mjs
dotnet run --project verification/FollowUp/I/Validation.csproj -c Release -p:CheckEolTargetFramework=false
dotnet build Emby.YouTubePlugin.csproj -c Release --no-restore
```

- Baseline: 3/3 reproduksjoner på HEAD-kontrolleren.
- Endret produksjonskontroller/DOM: 60/60 nettleserkontroller, inkludert alle 12 jobbtilstander. `BROWSER-EVIDENCE.json`: Completed=true.
- `VALIDATION-EVIDENCE.json`: 14 beståtte valideringskontroller, tre avgrensede metadataobservasjoner og bekreftet slettet midlertidig verktøyfil. Metadataobservasjonene telles ikke som TV-/integrasjonskontroller. TXT-filen er tidligere kommandoutdata med SDK-varsel; JSON er endelig evidens.
- Produksjonsbygget og diff-whitespacekontroll passerer. Kildehashene ligger i `SOURCE-HASHES.json`.

## Gjenstående arbeid og sluttopprydding

I er fortsatt åpent for virkelig Emby-nettleserintegrasjon: fremprovoser jobbfeil isolert, kontroller serverens lagrede konfigurasjon etter gyldig/ugyldig POST og omstart, prøv tidsutløpt sesjon og samtidige faner med native profilpersistens. Kartlegg produktvalg for synlige effektive grenser per bruker med F/G. En fysisk Android TV-beskrivelsesprøve må avtales med H og sammenlignes med Emby-web før metadataendring integreres.

Ingen hovedserverinnstillinger, testkontoer, biblioteker, mediefiler eller Google-nøkler ble opprettet. Browser-prosessen avsluttet; readback bekrefter null prosesser med denne testprofilen og ingen lytter på 18217. C#-prøvens midlertidige fil er slettet. `FINAL-CLEANUP.json` dokumenterer resttilstanden. Automatisk kjøringskontroll avviste rekursiv sletting av den isolerte nettleserprofilen med «blocked by policy»; profilen ligger derfor igjen i den Git-ignorerte `bin/followup-i-edge`. Ingen alternative slettemekanismer ble brukt.

Leveransen endrer bare Configuration-filer, YouTubeConfigSaveService, denne I-mappen og I-kapittelet i TODO. Ingen commit, utrulling eller generell støtteerklæring er utført.
