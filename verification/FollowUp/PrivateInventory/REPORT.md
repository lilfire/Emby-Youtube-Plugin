# A: betrodd privat kildeoversikt — kontraktprøver 2026-10-15

Historisk kontraktundersøkelse. Senere produksjonsimplementering og sluttbevis:
[IMPLEMENTATION.md](IMPLEMENTATION.md). Utsagnene nedenfor om uendret
produksjonskode og ikke erstattet skanning gjelder undersøkelsen alene.

Neste åpne punkt etter Tags-optimaliseringen. Undersøkelsen og den isolerte
prototypen er levert; **full biblioteksskanning er ikke erstattet**, og TODO-punktet
er fortsatt åpent. Kandidaten er bare testkode og skal ikke aktiveres i gaten.
Ingen produksjonskode eller Lilflix er endret i denne leveransen.

## Resultat

[Candidate.cs](Candidate.cs) bygger en avgrenset oversikt fra begge permanente
bindingsaliaser, journalrøtter/reserverte GUID-er, private native stier og
virtual-folder-lokasjoner. Den sammenligner native AncestorIds med iterasjon over
direkte ParentIds. Spørringene er uten User, slik at usynlige private kilder
også kan finnes.

[22 komponentobservasjoner](EVIDENCE.json) fullførte uten uventede avvik. De bruker
produksjons-Store, NativeBindings, PublicationJournal og NativeAccess over en
SDK-bibliotekadapter. Den gamle resolveren er referansen for hva som må finnes
og avvises. Beståtte prøver betyr at forventede hull ble funnet, ikke at
kandidaten har bestått produktakseptanse.

- Registrert aktivt innhold har positiv eierkontroll og negativ fremmedkontroll.
  Vanlig offentlig innhold fungerer for begge kontoer.
- Direkte foreldre finner uregistrerte private barn, nestede barn med eksterne
  stier, media-orphans, etterkommere av private fysiske mapper og reserverte
  røtter/barn som ennå ikke har en binding.
- Den simulerte forfedreindeksen mangler et barn som finnes i den faktiske
  foreldrekjeden. ParentIds-varianten dekker dette. Dette er et adaptertilfelle;
  en naturlig indeksmismatch i kjørt Emby er ikke reprodusert her.
- Begge avgrensede kandidater kan mangle en sti som ligger leksikalsk utenfor
  media, men kanonisk innenfor: `ordinary/../media/alias.mp4`. Produksjonsresolveren
  bruker Path.GetFullPath og avviser denne kilden for både eier og fremmed.
  Kandidaten kan derfor ikke erklære alt den ikke fant som offentlig.
- Tilbakekalling fjerner tidligere eiertilgang. Korrupt enkeltprofil avviser
  privat innhold og bevarer offentlig kontroll. Korrupt global journal blokkerer
  også offentlig kontroll i den eksisterende produksjonsresolveren.

## Native evidens og begrensninger

[NATIVE-CONTRACT.json](NATIVE-CONTRACT.json) leser IL fra den eksisterende lokale
Emby.Server.Implementations **4.10.1.0**, uten å laste eller kjøre assemblyen.
Assemblyhash, signaturer og IL-offsets er lagret. Inventaret omfatter 20
LibraryManager-metoder og 29 kildefilter-/hendelsesmetoder, samt repository-
skrivekall i denne assemblyen. Det er ikke et fullstendig transitivt inventar
for alle assemblies/plugins, og ikke et timing-/runtime-bevis.

| Native metode | Lagring og hendelse | Betydning for oversikten |
|---|---|---|
| CreateItems, full overload | SaveItems ved offset 19; TriggerItemAdded ved 50; ItemAdding omtales senere ved 81/110 | ItemAdding/Added alene etablerer ikke en før-lagring-barriere. |
| UpdateItems, full overload | SaveItems ved 68; ItemUpdated-felt ved 144; EnableItemChangeEvents ved 171; Invoke ved 214 | Hendelsen er betinget og kommer etter lagring i den viste metoden. |
| DeleteItems(long[]) | Direkte IItemRepository.DeleteItems ved offset 7 | Ingen LibraryManager-endringshendelse kalles i denne metodebodyen. |
| SqliteItemRepository.UpdateProgramsForChannel | Repositoryets SaveItems finnes i kallinventaret | LibraryManager alene er ikke inventar over alle native skriveveier. |

Disse metodene gir ingen kontrakt om at hendelsesbasert invalidering skjer før
nye data kan leses. Et faktisk samtidighetsvindu er ikke kjørt eller målt her.
En TTL eller bare ItemAdded/Updated/Removed kan ikke dokumentere at den ferske
skanningen kan fjernes.

GetWhereClauses leser PathStartsWith ved offset 2913/2928 og bygger et Path-
filter med `like` og `%` i samme IL-segment. Ingen Path.GetFullPath forekommer i
det inspiserte segmentet. [SQLite-prøven](SQLITE-PATH-EVIDENCE.json) kjører den
tilsvarende leksikalske predikaten i en minnedatabase: 3/3 forventede
observasjoner, inkludert den manglende kanoniske aliasstien. Dette viser
predikatens begrensning. Det er ikke bevis for at alle native skriveveier kan
lagre en slik sti, eller at en fjernbruker kan skape den.

## Kontrakt som må implementeres før erstatning

1. Initialiser en kanonisk kildeoversikt fra den eksisterende fullstendige
   resolveren. Behold direkte ID/GUID, faktisk ParentId, kanoniske kilder,
   betrodde virtual-folder-lokasjoner, private aliaser/reservasjoner og tombstones.
2. Fang native kilde-/foreldre-/identitetsendringer før lagring/synlighet, med
   eksplisitt kontrakt for repositoryets skrive- og sletteinnganger. Avklar
   direkte repositorykall og muterte native objekter. Prøv hele kjeden i native
   Emby med eksakte kontrakthasher; hendelser alene er ikke grunnlaget.
3. Bind hvert listekall til en kildeversjon. Endring mellom query, resultat og
   skriver må gi fersk rekonstruksjon eller avslag før utlevering. Behold dagens
   profil-/generasjons-/journal- og writer-lease-kontroller.
4. Opprett en uavhengig, varig privat scope-/reservasjonsoversikt før journal-
   eller native publisering. Først da kan korrupt enkeltjournal avgrenses uten
   å kalle ukjente reserverte røtter offentlige. Globalt tap av klassifikasjons-
   autoritet må fortsatt avvises.
5. Prøv aliaser, foreldre, reservasjoner, orphans og korrupsjon mot faktisk
   native persistens og eksisterende query/resultat/skriver-racer. Mål deretter
   integrert kandidat med stort bibliotek og parallelle hjemmekall.

## Reproduksjon og sluttopprydding

```powershell
dotnet run --project verification/FollowUp/PrivateInventory/Probe.csproj -c Release -p:CheckEolTargetFramework=false
dotnet run --project verification/FollowUp/PrivateInventory/NativeContract/Inspect.csproj -c Release -- .
python verification/FollowUp/PrivateInventory/NativeContract/Probe-PathPredicate.py
```

Produksjons-DLL er uendret:
`B27179ED140841FCA94525F9DB1941619148EA406F7FE47992E079905ACA3C3A`.
Plattform: Windows 10.0.19045, .NET 8 for prøveverktøyet; pluginen er fortsatt
net6.0. Probe- og IL-verktøyene bygget og kjørte uten rapporterte feil/advarsler.
Ingen Emby-prosess ble startet, ingen native database skrevet, og ingen ekte
Google-/HA-/nettverksforbindelse brukt. Ingen ny ytelses-/Lilflix-måling.
Temporær profildata ble slettet og lest tilbake som fraværende
(`TestDataGone=true`); øvrige bygg ligger i ignorert bin/obj. Portable bevis
inneholder syntetiske observasjoner og statiske kodekontrakter, ikke tokens,
private medier eller rå serverlogger.
