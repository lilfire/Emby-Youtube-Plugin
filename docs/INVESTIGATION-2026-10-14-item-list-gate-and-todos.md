# Investigation: item-list 404 and follow-up reports

Investigated 2026-10-14 against HEAD
`e49dc06ec5edf4de3c966a4d49d9cb51419ecfe7` and the existing dirty working tree.
Production access modules were read, not changed. No Lilflix, HA, TV, server
configuration, token, private data or deployment was accessed or changed.

## Findings

1. **Confirmed availability defect: null-user requests are always rejected.**
   [BeforeService](../PersonalYouTubeItemListGate.cs) lines 211–241 checks
   `GetAuthorizationInfo(request).User` and rejects null before executing any
   native service. It does not distinguish a server API key from other
   authentication states. The component probe reproduces the precise generic
   not-found exception with a non-null authorization-info object whose User is
   null. This confirms the code mechanism; actual API-key authentication and
   HTTP status on Lilflix remain observations from the supplied bug report.
   Administrator virtual-folder bypass is after this rejection.

2. **Confirmed broad cost: the full scan is followed by repeated native and
   storage resolution.** The prefix scans the library for every covered DTO.
   [DecideOrdinaryItem](../PersonalYouTubeNativeAccess.cs) lines 164–185 calls
   GetCollectionFolders, walks parents, and calls GetVirtualFolders for each
   ordinary item, including ordinary non-YouTube content. Its journal decision
   loads bindings, journal, and the direct binding lookup again; these loaders
   use File.ReadAllText/JSON parsing when their files exist. Bound owner items
   also read profiles. Genre/Studio/Tag decisions issue further native source
   queries. Cost therefore depends on total library size, ancestry, metadata,
   persisted binding size and parallel requests, not the requested Limit=12.
   This supports a performance defect, but is not a measurement or proof of
   why the reported 32.6-second request ended in 404.

3. **The logged-in-user cause is still unproven, and is not confined to the
   prefix catch.** The report's assumption that it must be an exception later
   in BeforeService is too narrow. Additional failure boundaries are:
   - ServiceFailed (lines 339–344), which replaces a synchronous native error.
   - Finish (346–375), which can reject absent query/source coverage, changed
     denials, unstable tag provenance, null results, or unsupported writers.
   - BeforeWrite (387–405), which can reject lease acquisition or fresh access.
   Async native service failures can also propagate through Finish.
   These paths cannot be distinguished from the supplied generic response.
   The seven component observations include proof that Covers(empty) is false
   without any recorded source, and true after recording an empty source.
   This is intentional privacy protection, not itself a demonstrated bug;
   native shortcuts or cached result paths need explicit source-coverage tests.

4. **There are concrete scan-failure candidates beyond null fields.**
   [NativeBindings.DecideItem](../PersonalYouTubeNativeBindings.cs) lines
   135–140 throws for nonpositive native IDs, empty GUIDs or invalid ancestors.
   [PublicationJournal](../PersonalYouTubePublicationJournal.cs) rejects
   missing required markers/journals and corrupt documents, checks source
   cardinality, and canonicalizes every supplied nonempty path. Native calls,
   storage reads and path conversion can throw. One unrelated inventory item
   can consequently abort an entire list before its actual query runs.
   These are source-proven possible failures, not an identification of the
   production offender. E already reproduces global journal failure affecting
   unrelated owner B. Inspect concrete item type/identity and journal state
   in an isolated reproduction before choosing a correction.

5. **Disabling the alpha setting does not disable these gates.**
   [PluginEntryPoint.Run](../PluginEntryPoint.cs) lines 179–199 installs both
   service-reference and item-list gates whenever its library/data dependencies
   are present. PersonalYouTubeAlphaEnabled is checked only for job startup.
   The bug report's “turn off the gate” is not an available configuration
   workaround. Adding a global bypass could expose existing native personal
   libraries. J also documents why downgrading the DLL alone is not a proven
   privacy-safe rollback when private native objects or derived files remain.

## Relationship to the TODO reports

All A–K reports were reviewed with TODO and K's evidence index. They describe
different test layers and DLLs, not one accepted end-to-end implementation.

| Chapter | Finding relevant to the next implementation |
|---|---|
| A | Native tests expose Similar, Recommendations, Years/Ratings/Persons and playlist source/reference leaks. Tested GetItems paging passes in a small Windows fixture; this does not reproduce or disprove the Linux/full-library incident. |
| B | Sync metadata and original/converted bytes bypass ownership; live Open/MediaInfo/Close and controlled WebSocket delivery have defects. Derived references require their own lifetime model. DLNA/live bytes lack positive support controls. |
| C | Controlled replacement of an authorized image/subtitle cache file delivers B bytes through A's valid path. Trusted content provenance is missing; this is a local file-substitution experiment, not a demonstrated remote file-write route. |
| D | Audio serves foreign complete MP4 bytes; HLS exposes foreign playlists/references. Controlled original-file substitution also passes path-based checks. Static video controls work in the tested scope; dynamic/HLS media support is unproven. |
| E | Journal/binding mismatch, global corruption impact, pre-Begin staging orphans and Linux storage-root symlinks need repair. Component adapters and process-kill tests do not establish native-server recovery. |
| F | Tested identity/token/disabled-account controls work. Deleted-account profile/media retention, backup reactivation, process-local locking and inherited file permissions remain limitations. |
| G | Body reads and inherited-pipe draining can wait beyond nominal timeouts; a global job lease spreads the impact. Null-byte MP4 output is accepted, duplicate IDs can fail selection, and new page tokens allow unbounded requests. These job defects are not evidence for a list-request timeout. |
| H | Fresh web HomeSections/SectionItems requests expose foreign library/video metadata, while tested Views filters it. Home routing bypass is independent of the gated-route 404 incident. Own-thumbnail 404 also needs positive image diagnostics. |
| I | Existing local UI/save-validation fixes passed adapter/DOM checks, not native persistence/restart acceptance. Keep these changes separate from a gate fix and verify them on the final integrated DLL. |
| J | Exact native contracts and runtime Harmony behavior need verification. Patch metadata can survive a competing prefix that skips the checked code. Packaging/rollback tests do not certify safe native upgrade or rollback. |
| K | Evidence consolidation is delivered; known product defects remain open. Most native checks were indexed rather than rerun; its fresh G run reproduced requirements not met, not product acceptance. |

K records Lilflix DLL `2E68B8DE68DE787DCEEB8AC30C44A417BD28126A3EE630F988F183ED193347EC`,
A–D/F/H native DLL `AD5D3A3BC97308A085AD5BAB71911F54D25E2C37C7553E12FDA39DE449AEB0D8`,
and the current build `ECCB1B92D991886551DD462B8E99FE1ED31F23C82861910BE234E792BD8E55B0`.
Same version/commit labels do not establish identical binaries. This probe
loaded the current build, whose hash matches K's current-build record.

## Recommended correction order and acceptance

1. Treat this availability incident as a release blocker alongside the P0
   privacy defects. Add bounded, sanitized diagnostics at prefix, native
   service, result and writer boundaries: DTO, phase, error type/reason,
   correlation ID, scan duration/count and coverage status. Do not log raw
   requests, credentials, private paths or unsanitized exception messages.
   Distinguish expected ownership denials from infrastructure failures.
2. Define and verify server-key semantics using native authentication state.
   Null User alone must never be proof of a trusted server key. A verified
   administrative key may need a separate trusted service scope; inspect
   the service-reference gate as well as the list gate and keep anonymous,
   invalid-key and disabled-user negative controls. Returning 200 without
   the expected public inventory is not acceptance.
3. Replace full ordinary-library scans with a trustworthy private-source
   inventory/snapshot. DeniedRegisteredIds alone is insufficient: unregistered
   private descendants, reserved roots, moves and corrupt journal states still
   require coverage. Any cache must track profile/generation, bindings/journal,
   native changes and policy, and preserve fresh result/write revalidation.
   A TTL-only cache or exception-driven whole-service fail-open would regress
   existing privacy protections. Preserve public availability by isolating
   reliably classified private failures; uncertainty is not proof of publicness.
4. Run an isolated native matrix with exact candidate hash: server-key
   Counts/VirtualFolders/Items, owner/foreign/public user Items/Views/Latest,
   empty and cached sources, admin/disabled/anonymous/invalid-key states,
   count/page correctness, corruption isolation and query/result/writer races.
   Use production-shaped library size and parallel home requests. Then obtain
   read-only Lilflix timings to verify the reported <1-second criterion.
5. Integrate H's HomeSections/SectionItems source filtering with A's remaining
   discovery gaps; fix B/D's direct foreign-byte paths and C/D's content
   provenance with E/G's trusted publication/recovery model. A list availability
   fix alone cannot close these independent TODO requirements.

## Verification performed for this investigation

Run from the repository root:

```powershell
dotnet run --project verification/FollowUp/ItemListGate404/Probe.csproj -c Release -p:CheckEolTargetFramework=false
```

Build/run completed without reported warnings/errors. **7/7 expected component
observations reproduced**, including the null-user rejection and late-coverage
semantics. [Probe source](../verification/FollowUp/ItemListGate404/Program.cs)
invokes the actual production prefix/coverage class using reflection. DTO
registration and authorization are adapters. No real token, Harmony-installed
native route, Emby process, Linux runtime or latency was tested. Static fields
are restored in finally and the probe process exits; only ignored build outputs
remain. No production fix, deployment or TODO completion is claimed.
