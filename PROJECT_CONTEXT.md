# Project: Callup

Status: active
Owner: ts
Last updated: 2026-08-19

## Start here

This document is the durable handoff from the original exploratory conversation.
It should be enough to open `/Users/ts/src/callup` as a standalone project and
continue without reconstructing the product decisions from chat.

### Current executable state

- Vapor service executable: `callup`, distributed as a static Linux release
  and running in the canonical homelab LXC at `http://10.69.42.18:8484`.
- The LXC release is the sole review and handoff path. Do not use or offer a
  local macOS instance: Callup is being made distributable for other users,
  who do not share the owner’s computer. `/health` identifies the installed
  release and revision.
- Settings exposes application update discovery and explicit installation.
  Release discovery, semantic version policy, and request coordination live in
  `CallupUpdates`, not in Vapor routes. The unprivileged app can only request
  the newest validated release; a narrowly scoped root-owned systemd updater
  verifies and stages it, restarts Callup, checks `/health`, and rolls back the
  binary and release identity if the new version does not become healthy. The
  Proxmox/install commands remain bootstrap and recovery paths rather than the
  intended recurring user experience.
- Browser UI performs one mixed TVMaze show and TMDB movie search and persists
  shows and movies in one minimal tracked view. It labels each tracked show as
  ended or with its next announced air date and displays seasons and episodes.
  The current source also
  offers an unranked, read-only release search for each season
  through NZBGeek. The UI labels these provider roles separately so indexer
  connectivity does not imply metadata search switched.
- New tracked shows monitor episodes airing today or later by default. A
  show-level All/Future/None policy controls newly discovered episodes, while
  season and episode checkboxes remain explicit durable overrides. Existing
  tracked lineups retain their prior all-episodes baseline.
- The domain now treats episodes and movies as the same atomic acquisition
  shape: a canonical leaf plus optional ancestors. Tracked roots share one
  kind-keyed SQLite table, while television retains only its genuinely
  media-specific sparse episode policy.
- Generic Newznab code builds TV searches and normalizes XML responses.
  NZBGeek is the first configured indexer.
- A minimal Settings panel configures NZBGeek and one download client,
  choosing SABnzbd or NZBGet. SABnzbd connections can accept one explicitly
  confirmed indexer result through a manual **Send to SABnzbd** action.
- Download activity and completed history live in a separate, on-demand
  Downloads panel instead of occupying the tracked-shows flow.
- In its eventual dedicated LXC, Callup will share the canonical `/data` bind
  mount and scan `/data/complete/Television` and `/data/complete/Movies` into a
  short-lived inventory. It replaces—not integrates with—Sonarr, Radarr, and
  Prowlarr. It marks conservative movie and standard `S01E01`/`1x01` episode
  matches as on disk; it does not rename, move, import, or otherwise manage
  files.
- The Linux deployment targets Debian's native Swift 6.0 toolchain. Keep the
  package manifest at Swift tools 6.0 unless an observed source requirement
  needs a newer toolchain.
- Public Linux binaries are stripped at link time, and release archives exclude
  macOS extended attributes. Packaging rejects unstripped, stale, dynamic, or
  non-x86_64 artifacts so small destination filesystems do not absorb build
  metadata.
- Callup fetches the NZB server-side, uploads it to SABnzbd, persists the
  provider reference and returned SAB job ID, prevents repeat submission, and
  reconciles sending, snatched, downloading, downloaded, and blocked states.
  A lifecycle-managed Swift worker now checks active SABnzbd jobs at startup
  and once per minute; opening Downloads only reads the durable state.
  A confirmed submission is durable delivery intent, even when SABnzbd is
  temporarily unreachable. A future delivery worker should retry transient
  failures with bounded exponential backoff, reconcile before every retry to
  avoid duplicate SAB jobs after ambiguous failures, and surface permanent or
  exhausted failures with explicit Retry now and Cancel actions. A user never
  needs to repeat discovery or confirmation merely because the download host
  was offline.
  Downloaded episodes render unchecked in their season checklist and are
  therefore omitted from later checked-episode searches.
- Connection secrets live in an owner-only file beside SQLite, never in SQLite,
  source models, logs, or browser responses. A gitignored `.env` supplies
  optional operator and development overrides; Callup does not use Keychain.
- Settings exports and restores a versioned JSON backup of the Lineup,
  monitoring overrides, preferences, and download history. Connections are an
  explicit opt-in because they include credentials; provider caches and the
  read-only library inventory are rebuilt on the destination.
- TMDB is a typed, cached movie metadata supplier loaded from a backend-only
  bearer token. Tracking returns after its local write and optimistically
  hydrates detail metadata in the background. Tracked movies expose cached,
  identity-checked, preference-ranked Newznab matches but cannot yet submit one.
- Seventy-eight tests pass.
- The running `sqlite-cache` build introduces the first application-store slice
  with one explicitly confirmed manual SABnzbd submission seam. No automated
  recommendation queueing, media renaming, or library management exists yet.

### Immediate next step

Add explicit submission of one re-verified movie candidate through SABnzbd's
stable `movies` category without disturbing the television acquisition path.

### Secret-handling rule learned during setup

Never ask the user to paste a secret into chat, a screenshot, a literal shell
command, or an interactive `read` embedded in a pasted multi-line command. The
original key was exposed during a flawed setup instruction and must not be
reused. Operator credentials belong in the gitignored `.env`, while the in-app
Connections panel is the normal setup path for user-owned services. Saved
secrets remain server-side in an owner-only file. The temporary clipboard
launcher was removed after startup.

Callup is the working product name. Its central action is to call up wanted
media through existing metadata, search, and download APIs; `Lineup` names the
unified list of requested television, movies, music, and books.

## Product promise

**Get the television, movies, music, and books I want through one fast,
understandable system without making me learn the application's implementation
model.**

The product must be:

- **Better:** decisions are based on concepts people recognize, and every
  choice or rejection can be explained plainly.
- **Faster:** a season can be found and queued as one intent, without repeatedly
  searching for individual episodes.
- **Easier:** useful defaults and one obvious path come first; advanced controls
  appear only when a real need earns them.

## Product advantage

Existing automation splits media into separate applications with duplicated
configuration, inconsistent concepts, separate queues, and separate histories.
This product treats acquisition as one capability:

```text
discover -> search -> understand -> choose -> queue -> track
```

Television, movies, music, and books use that shared pipeline while retaining
the media-specific metadata and matching rules that make each domain accurate.
The unified application, policy vocabulary, provider management, activity view,
and history are a primary value proposition—not a later convenience.

## The first job to be done

Given a series and season, find available releases for its episodes, choose sane
candidates, show the choices, and send the approved downloads to SABnzbd.

Television is the first vertical slice, not the product boundary. SABnzbd
remains responsible for downloading and unpacking. Callup submits through one
stable category per media kind and will own final library placement in a
separate importer module; it never creates per-show or per-season downloader
categories.

## MVP interaction

1. Search for and select a television series.
2. Select a season.
3. Choose one simple preference, initially a resolution preset. File-size
   bounds and codec preference have useful defaults and remain editable.
4. Run one search covering the season.
5. See one recommended candidate per episode, missing episodes, and concise
   reasons for rejected candidates.
6. Queue all recommendations or adjust individual episodes.
7. See queued, downloading, completed, failed, and retryable states.

The primary action is **Get this season**, not profile administration.

## Success criteria for the first useful release

- [ ] A user can select a series and season without manually entering every
  episode number.
- [ ] One action searches all known episodes in that season through the single
  configured indexer.
- [ ] The app recommends no more than one release per episode using predictable
  resolution and size rules.
- [ ] A codec preference may improve ranking but is not required for the basic
  flow.
- [ ] Every skipped result has a short human-readable explanation.
- [ ] The user can queue selected recommendations to SABnzbd and see their
  current download state.
- [ ] Repeating the action does not enqueue the same episode twice without an
  explicit override.
- [ ] The service runs on Linux in the homelab and survives restart without
  losing its history.

## Strict MVP boundary

### Included

- Television episodes with standard season/episode numbering.
- One metadata provider for series and episode discovery.
- One indexer connection.
- SABnzbd as the only download client.
- Manual season acquisition.
- 720p, 1080p, and 2160p resolution choices.
- Understandable target and maximum sizes.
- Optional codec preference.
- Recommendation explanations, confirmation, deduplication, and status.
- Server-side Swift/Vapor, SQLite, and a browser interface.

### Deferred from the first vertical slice

- Renaming, moving, importing, or owning a media library. Canonical destination
  preferences remain Callup concerns rather than downloader configuration.
- Sonarr configuration or compatibility as a product requirement.
- Automatic upgrades of existing files.
- Additional live indexers and download clients. The domain and persistence
  model must support more than one from the beginning.
- Movies, music, books, anime numbering, daily shows, and absolute numbering are
  deferred from the first executable slice. Movies, music, and books are
  first-class product domains in this application, never separate companion
  applications.
- Selecting season packs in the first end-to-end slice. A candidate must be able
  to cover multiple episodes from the beginning so packs do not require a schema
  rewrite.
- Transcoding, playback, subtitles, notifications, and user accounts.
- A generic rules engine, opaque custom-format scoring system, or per-source
  bitrate sliders. Understandable reusable preference profiles are in scope.

## Core product rules

1. Defaults are product decisions, not blank fields delegated to the user.
2. The UI speaks in resolution, approximate file size, and recognizable codec
   names. Internal units and scoring never become primary controls.
3. A result is either recommended, available as an alternative, or rejected
   with a reason.
4. Searching is read-only. Queuing requires a visible recommendation and an
   explicit user action.
5. Idempotency is mandatory: retries and repeated searches must be safe.
6. Complexity is added from observed failures, not copied from existing apps.

## Core engineering tenets

- **Identity:** determine which work, edition, season, episode, album, track, or
  file a provider result actually represents.
- **Normalization:** translate inconsistent provider payloads into comparable
  candidates without discarding their provenance or raw evidence.
- **Selection:** make deterministic choices from understandable policies and
  media-specific knowledge.
- **Explanation:** preserve why every candidate was recommended, offered as an
  alternative, or rejected.
- **Idempotency:** repeated searches, retries, submissions, callbacks, and
  restarts must not accidentally duplicate work or downloads.
- **State:** persist enough durable workflow state to recover cleanly from
  process restarts, provider failures, and delayed download-client updates.

These are product guarantees. Provider adapters, web routes, background jobs,
and persistence exist to uphold them.

## Persistence doctrine

- Callup has one application store and one read boundary. Durable product truth
  and disposable provider caches use the same SQLite database, not separate
  databases or parallel in-memory copies.
- User intent, decisions, idempotency records, and externally consequential
  workflow state are durable product truth.
- External facts remain provider-owned. Cached snapshots include provenance,
  fetch time, expiry, and payload schema version and may be deleted or rebuilt.
- Views and services read through the shared store so a committed change is
  visible consistently. Observation mechanics may evolve without introducing a
  second source of truth.
- Fresh cache values return immediately. Stale values also return immediately
  while one background refresh updates the shared entry. A provider outage does
  not erase the last useful view.
- Credentials and credential-bearing download URLs never enter SQLite.
- Prefer embedded SQLite for the single-node product. Add a database server only
  after an observed need for multiple application writers or remote shared
  storage.

## Proposed architecture

```text
Browser
   |
Vapor routes and HTML
   |
Unified acquisition service ----------------------- SQLite
   |                                                  |-- media/work units
   |-- shared provider and download orchestration     |-- searches/candidates
   |-- shared decision/explanation framework          |-- decisions/reasons
   |-- TV domain                                      `-- jobs/history
   |-- movie domain
   |-- music domain
   |-- book domain
   `-- SABnzbd adapter
```

### Module boundaries

- `Domain`: media, work units, candidates, policies, recommendations, and
  acquisition state. No Vapor or provider types.
- `MediaDomains`: TV, movie, music, and book modules define their metadata,
  matching, and meaningful policy traits without creating separate apps.
- `Metadata`: resolves a selected work into the expected acquirable units, such
  as episodes, a movie, album tracks, or book editions.
- `Indexer`: performs searches and normalizes provider results.
- `DecisionEngine`: filters and ranks candidates while producing explanation
  codes.
- `DownloadClient`: submits to SABnzbd and reconciles job state.
- `Persistence`: SQLite repositories and migrations.
- `Web`: the single guided workflow and status views.
- `Updates`: release discovery, version/channel policy, and update request
  coordination. A separate packaged systemd helper owns the privileged
  install/restart/rollback boundary; the web process never runs as root and
  never replaces its own executable.

Provider responses must be stored separately from domain models so replacing or
adding a provider does not rewrite the product. Protocol boundaries should be
defined from actual integrations, but cardinality must not be artificially
limited to one.

## Minimal domain model

```text
MediaReference(kind, providerReference)
AcquisitionTarget(mediaReference, ancestors[])
AcquisitionContext(targets[])
TrackedMedia(kind, metadataPayload, settingsPayload, addedAt)
Candidate(providerReference, title, size, traits, reportedMediaIDs, coverage)
Download(candidateReference, acquisitionContext, clientJobID, state)
```

The canonical downloadable unit is a leaf media reference. An episode and a
movie are therefore the same acquisition shape: the episode has a series among
its ancestors, while the movie may optionally have a collection ancestor.
Hierarchy affects navigation, inheritance, and presentation; it does not create
a separate download mechanism. A candidate remains separate from the media it
claims to cover, and download state belongs to the acquisition attempt rather
than to the media item.

SQLite stores all tracked roots in one `tracked_media` table keyed by media
kind and provider identity. Typed metadata and settings remain JSON payloads
while each media vocabulary stabilizes. Television keeps a separate sparse
lineup policy because tracking a series and wanting its episode leaves are
distinct intentions. Download submissions store one shared acquisition context
instead of television-only series and episode columns.

`Policy` is the useful version of profile administration: named, understandable
preferences with defaults, optional media-specific fields, and per-request
overrides. Each search stores an immutable policy snapshot so changing a profile
later cannot silently change the explanation for an existing recommendation.

## Candidate decision model

The first engine does not need numeric user-visible scores. It applies ordered
decisions:

1. Reject results that cannot be tied confidently to the requested series,
   season, and episode.
2. Reject unsupported or explicitly unwanted resolutions.
3. Reject files above the understandable maximum size.
4. Prefer the requested resolution.
5. Prefer files near the target size rather than merely accepting the largest.
6. Use codec as a tie-breaker or hard requirement only when the user asks.
7. Merge duplicate candidates reported by multiple indexers while retaining
   provenance from every provider.
8. Use remaining stable signals such as age or indexer metadata only to break a
   genuine tie.

Every branch emits a stable explanation such as `wrong_episode`, `too_large`,
`wrong_resolution`, or `codec_preferred` plus display text.

## Delivery plan

### Milestone 0 — Product skeleton (completed)

- [x] Runnable Vapor service and browser form.
- [x] Provider-neutral television discovery models and fixture tests.
- [x] No writes to Sonarr or SABnzbd.

The existing compiler is disposable scaffolding where it encodes Sonarr-specific
concepts; its human-facing preference types remain useful.

### Milestone 1 — Honest search

- [x] Choose TVmaze as the first television metadata provider and NZBGeek as the
  first indexer, reached through a provider-neutral Newznab adapter.
- [x] Add environment-based secret configuration with no keys in source or
  SQLite.
- [x] Search/select a series and inspect its seasons.
- [x] Fetch and group the episode list.
- [x] Make one controlled read-only season query through the indexer.
- [x] Capture observed, sanitized provider evidence in a fixture without storing
  raw credential-bearing download URLs.
- [x] Add one SQLite application store and cache TVmaze and normalized Newznab
  responses with fresh/stale semantics.
- [x] Display normalized candidates without ranking or downloading.
- [x] Persist a minimal tracked-series checklist where every season and episode
  is included by default and the user may uncheck either level.
  Season checkboxes are bulk controls, not gates: an episode remains selectable
  under an unchecked season and promotes that season to a partial selection.
- [x] Show one concise lifecycle signal on tracked cards: ended or the next
  announced TVmaze air date.
- [x] Build and fixture-test a generic Newznab request/response seam for
  NZBGeek without making a live credentialed call.
- [x] Verify TVmaze decoding using captured, secret-free fixtures.

### Milestone 2 — Understandable recommendations

- [x] Parse standard release titles into episode, resolution, codec, and source
  traits.
- [ ] Apply resolution and size rules.
- [ ] Recommend one candidate per episode.
- [ ] Show missing episodes and rejection reasons.
- [ ] Add fixture-driven tests for every decision branch.

### Milestone 3 — Queue to SABnzbd

- [ ] Display the complete queue plan before mutation.
- [x] Submit one explicitly confirmed television candidate through SABnzbd's
  stable `tv` category without reading or mutating downloader configuration.
- [x] Reserve the provider reference before submission and persist the returned
  SAB job ID.
- [x] Reconcile snatched, downloading, downloaded, and blocked state.
- [x] Prevent repeated submission across double-clicks and process restarts.
- [ ] Expand from one episode to **Queue recommended season**.

### Milestone 4 — Make it faster

- [ ] Retry missing episodes without repeating successful work.
- [x] Remember a preferred resolution and video codec per tracked series and
  rank exact matches first without hiding alternatives.
- [ ] Add a lightweight monitored-season scheduler only after manual acquisition
  is trustworthy.
- [ ] Add season-pack selection using the existing candidate-coverage model,
  comparing a pack with the best set of episode releases.

### Subsequent product capabilities

- Optional automatic application updates, built on the same explicit update
  coordinator and restricted system updater after manual updates have proven
  reliable.
- A full TVmaze schedule and calendar for tracked shows.
- Named profiles and per-request overrides using the same transparent policy
  model.
- Multiple indexers with concurrent search, health, provenance, and duplicate
  merging.
- Movies through the shared acquisition pipeline and a movie-specific metadata
  and matching module.
- Music through the shared acquisition pipeline with album, artist, track,
  format, and edition-aware matching.
- Books through the shared acquisition pipeline with author, work, edition,
  language, and file-format-aware matching.
- Library awareness and existing-file detection.
- Additional download clients.
- Nonstandard episode numbering.
- Automatic acquisition and upgrade policies.

## Verification gates

- Search fixtures contain no credentials or live download URLs.
- The decision engine is deterministic for the same inputs.
- No mutation endpoint exists before Milestone 3.
- SAB submission is verified first with one intentionally selected episode.
- Restart and duplicate-submission tests pass before season-wide queuing.
- Deployment is not declared complete until systemd restart persistence and
  configuration recovery are documented.

## Decisions

- 2026-08-06 — Use one embedded SQLite database through SQLiteNIO directly,
  without Fluent. Durable product state and disposable provider cache entries
  share one store and observation boundary while retaining distinct retention
  rules. Start with a single cache table and migration ledger; add explicit
  durable tables only when real product state exists.
- 2026-08-18 — Treat metadata as a provider collection, not a TMDB-shaped
  singleton setting. Direct provider credentials are validated, stored
  server-side, and remain an advanced self-hosted fallback. The intended
  ordinary-user default is a Callup-operated metadata gateway so installing
  Callup does not require acquiring third-party API credentials.
- 2026-08-06 — Run the fast-iteration canonical instance as a macOS LaunchAgent
  bound to loopback. Refresh it from the current coherent tested build so one
  dependable URL always shows the product being developed. Defer Proxmox/systemd
  deployment until durable workflow state and download mutations make a stable
  homelab release valuable. Treat Cloudflare Tunnel as later authenticated
  reachability, not process supervision.
- 2026-08-06 — Normalize development around one canonical local instance on
  port 8484, identified by branch and Git revision in `/health`. Codex owns
  automated verification and the canonical process lifecycle; the user can
  inspect the latest coherent build at any time without a terminal workflow or
  merge/deploy gate. The local launcher retrieves the rotated indexer key from
  macOS Keychain without storing it in the project.
- 2026-08-06 — The first controlled NZBGeek season search returned 100
  candidates with sizes and publication dates, but no provider-reported episode
  coverage, resolution, or codec. Treat title parsing as required evidence
  recovery rather than an optional enhancement. The normalized response
  contained no URLs or credentials.
- 2026-08-06 — Use the existing NZBGeek account as the first indexer and keep
  its implementation generic to the Newznab protocol. Begin with secret-free
  request and response fixtures; do not make a credentialed request until the
  API key is supplied through process environment outside source, logs, and
  browser responses.
- 2026-08-05 — Adopt `Callup` as the working product name and `Lineup` as the
  user-facing collection of requested media.
- 2026-08-05 — Build a standalone acquisition product, not a Sonarr configuration
  interface.
- 2026-08-05 — Start with one narrow end-to-end television workflow rather than
  feature parity with any existing application.
- 2026-08-05 — Exclude renaming, sorting, and library management from the MVP.
- 2026-08-05 — HEVC is an optional preference, not the product architecture.
- 2026-08-05 — Profiles, multiple indexers, movies, and season packs are deferred
  capabilities, not architectural exclusions. The initial domain supports
  reusable policy, provider provenance, multiple acquisition target types, and
  candidates covering multiple episodes.
- 2026-08-05 — The product unifies television, movies, music, and books in one
  application. Acquisition orchestration, provider management, policies,
  activity, and history are shared; metadata and matching remain media-specific.
- 2026-08-05 — Identity, normalization, deterministic selection, explanation,
  idempotency, and durable state are explicit product and engineering tenets.
- 2026-08-10 — Model every canonical downloadable leaf as a media reference
  with optional ancestors. Episodes and movies share one acquisition context;
  media-specific metadata, intent rules, preferences, and presentation remain
  typed at the edges.
- 2026-08-06 — Use TVmaze for the first read-only television discovery slice.
  Its public API requires no credential and supplies fuzzy series search and
  complete episode lists. Keep provider IDs behind `ProviderReference`.
- 2026-08-05 — Vapor is the server framework; the service targets Linux and is
  operated through a browser.
- 2026-08-05 — Secrets are runtime configuration and must never be committed.

## Active step

**Prove the first explicit movie handoff through the existing atomic download
pipeline, then keep importer and final-placement work separate.**

## Open questions

- `/Users/ts/src/callup` is the canonical source repository; Git was initialized
  on `main` on 2026-08-06.
- NZBGeek is the first indexer and exposes the Newznab protocol. Its live
  capabilities advertise TV and movie search; the adapter normalizes both into
  shared release candidates while keeping credentials and NZB URLs server-side.
- TVmaze is the initial television metadata provider and requires no API key for
  the selected public endpoints.
- Series identity must cross the metadata/indexer boundary using one canonical
  identifier per request. Prefer TheTVDB for Newznab TV searches; reject an
  explicit conflicting result ID, but accept unlabeled results from that
  identifier-scoped search because NZBGeek does not echo IDs per result.
- `UNKNOWN`: Whether the first release should accept only indexer search results
  or also consume its feed for later monitoring.
- `UNKNOWN`: Authentication boundary before exposure through Caddy or Tailscale.

## Known-good and rollback

- Sonarr, SABnzbd, and the indexer continue to operate independently.
- Callup stores configured provider credentials outside SQLite. Its only
  external mutation is an explicitly confirmed, idempotently reserved manual
  TV or movie NZB submission to SABnzbd.
- With no `CALLUP_NZBGEEK_API_KEY`, `/health` reports the indexer as
  `not-configured` and `/api/tv/releases` returns HTTP 503 without an external
  request.
- `GET /api/tv/search?q=The%20Good%20Place` returned the expected TVmaze match
  with provider ID `2790`.
- `GET /api/tv/series/2790/seasons` returned four seasons of 13 episodes each;
  the first normalized episode was `S01E01`, "Everything Is Fine."
- The browser UI supports live series search and displays grouped seasons and
  episodes. Release candidates are collated beneath their matching TVmaze
  episode, and saved SAB states are reflected on the episode after reload.
- A controlled search for TVmaze series `2790`, season 1, reported 202 NZBGeek
  candidates and returned the first page of 100. All inspected candidates had
  size and publication date; none had reported coverage, resolution, or codec.
  No URL or credential pattern appeared in the browser-safe JSON.
- The `com.callup.local` LaunchAgent returned to healthy state after a forced
  restart, incrementing its launch count while preserving revision identity and
  both provider connections.
- The `sqlite-cache` branch populated one disposable WAL database with TVmaze
  search, episode, and normalized Newznab namespaces. All three entries survived
  a process restart, normalized queries returned the same content, the directory
  and database used `0700` and `0600` permissions, and no credential-bearing URL
  entered the release cache.
- Removing the standalone source directory fully rolls back the software
  experiment without affecting the media stack.

## Change log

| Date | Change | Result | Verification |
|---|---|---|---|
| 2026-08-05 | Created the temporary Vapor scaffold | Runnable read-only preference preview | `swift test`; HTTP `/health` and `/api/plan` |
| 2026-08-05 | Reframed from Sonarr configurator to standalone acquisition service | MVP and explicit non-goals defined | Project-plan review |
| 2026-08-05 | Expanded the product boundary to unified TV, movies, music, and books | Shared pipeline and media-specific modules documented | Project-plan review |
| 2026-08-06 | Adopted Callup as the product name and Lineup as its central collection | Naming applied to package, source, UI, and documentation | Source search and test suite |
| 2026-08-06 | Replaced the Sonarr-shaped demo with live TV discovery | Read-only TVmaze search, season grouping, and browser UI work end to end | Three fixture tests; live HTTP search and season smoke test |
| 2026-08-06 | Added the generic Newznab seam for NZBGeek | TV search requests redact credentials; XML becomes safe candidate and coverage models | Six total tests; no live indexer request |
| 2026-08-06 | Gated the read-only NZBGeek route behind process environment | No credential means no external request; credential-bearing download URLs stay server-private | `/health` reports `not-configured`; release route returns HTTP 503 |
| 2026-08-06 | Ran the first controlled NZBGeek season search and added the browser results view | Confirmed real results omit structured coverage and traits; candidates remain read-only and unranked | 100 normalized results; sanitized fixture; six tests |
| 2026-08-06 | Parsed television coverage and release traits from NZB titles | Single episodes, multi-episodes, ranges, season packs, resolution, codec, and source are normalized without ranking or downloading | Fixture and parser edge-case tests |
| 2026-08-06 | Installed the canonical macOS LaunchAgent | Callup runs independently on loopback from explicit release checkpoints and restarts automatically | Forced restart; `/health`; live TVmaze and NZBGeek smoke tests |
| 2026-08-06 | Added the first unified SQLite application-store slice on `sqlite-cache` | TVmaze and normalized Newznab responses share one stale-while-refresh cache without Fluent | Twelve tests; disposable-file restart and live provider smoke tests |
| 2026-08-06 | Added the minimal tracked-shows list | Add/remove is durable product intent keyed by provider identity; it does not yet imply monitoring or acquisition | Store restart tests and live local API round-trip; eighteen tests |
| 2026-08-06 | Added the cascading television lineup checklist | A tracked series includes everything; only unchecked seasons and episodes are stored | Persistence tests, JavaScript syntax check, and local API round-trip |
| 2026-08-06 | Added minimal in-app provider connections | NZBGeek, SABnzbd, and NZBGet share one Connections surface; secrets use an owner-only file and download clients are probed read-only before save | Twenty-three tests; settings API smoke test confirms secrets are omitted |
| 2026-08-06 | Added the first manual SABnzbd handoff | One confirmed result is fetched server-side, uploaded as an NZB, deduplicated durably, and reconciled through a small visible download lifecycle | Thirty-one tests; no credential-bearing URL reaches the browser or SABnzbd |
| 2026-08-06 | Joined release and download history back to TVmaze episodes | Season searches render candidates beneath matching episodes; durable submissions retain/backfill episode identity and mark the lineup without changing wanted state | Thirty-two tests; embedded JavaScript syntax check |
| 2026-08-06 | Added a minimal airing signal to tracked-show cards | Ended shows are labeled directly; active shows derive their next announced date from the cached TVmaze episode feed, leaving the full schedule and calendar for later | Thirty-three tests; embedded JavaScript syntax check |
| 2026-08-06 | Moved secondary utilities out of the tracked-shows flow | Settings owns provider connections; Downloads opens activity and completed history on demand without background refreshes forcing it visible | Thirty-three tests; embedded JavaScript syntax check |
| 2026-08-07 | Closed a same-title television identity collision | TVmaze `567` (Gossip Girl, 2007) searches Newznab by its canonical TheTVDB ID `80547`; explicit conflicting result IDs are rejected, unlabeled identifier-scoped results remain usable, and SAB submission re-verifies the exact series and episodes | Thirty-seven tests; corrected an initial multi-ID query that returned zero results; cleared 80 transient cache entries |
| 2026-08-10 | Moved SABnzbd reconciliation into a lifecycle-managed Swift worker | Active downloads progress without the Downloads screen being open; the worker runs immediately, repeats once per minute, isolates per-job failures, and cancels before SQLite closes | Forty-seven tests, including worker start/stop and partial-failure coverage |
| 2026-08-10 | Separated show tracking from episode monitoring | New shows default to future episodes; All/Future/None supplies the baseline for newly discovered episodes and checkboxes persist explicit overrides without changing the policy | Fifty tests, including cutoff, override, persistence, and legacy-payload coverage; embedded JavaScript syntax check |
| 2026-08-10 | Reduced television acquisition to atomic media targets | Tracked roots share one kind-keyed store; downloads reference leaf targets and ancestors; movies prove the same shape without a parallel persistence pipeline | Full test suite, embedded JavaScript syntax check, and isolated migration of the live database snapshot |
| 2026-08-11 | Removed per-show and per-season SABnzbd categories | SABnzbd is a transport adapter using stable media categories; final placement belongs to a future modular Callup importer | Full test suite and source search for removed category mutation APIs |
| 2026-08-11 | Added read-only movie release matching | Tracking optimistically hydrates cached TMDB detail without delaying the local write; matches search Newznab by normalized IMDb identity, reject reported conflicts, and rank the full list using persisted movie preferences | Sixty-three tests and embedded JavaScript syntax check |
| 2026-08-11 | Added the first manual movie handoff | A selected result is re-verified server-side, fetched without exposing its NZB URL, submitted idempotently to SABnzbd's stable `movies` category, and associated with the tracked movie | Sixty-three tests, including durable generic movie acquisition context; embedded JavaScript syntax check |
| 2026-08-17 | Added in-app backup and restore | Settings downloads/uploads a versioned logical backup of durable user state; connections require explicit secret inclusion, restore replaces state transactionally, and disposable caches are rebuilt | Sixty-seven tests; embedded JavaScript syntax check; isolated HTTP round-trip of 8 shows, 6 movies, and 57 download records |
| 2026-08-18 | Generalized movie metadata connection settings | Metadata providers are a durable collection with provider-neutral routes; TMDB credentials can be validated and saved without entering browser responses, take effect immediately, and remain compatible with older connection files | Seventy-one tests; embedded JavaScript syntax check; isolated no-token-to-live-movie-search HTTP verification |

## Reference

- Source path: `/Users/ts/src/callup`
- SABnzbd: `http://10.69.42.22:8080`
- Existing indexer: NZBGeek through its Newznab-compatible API
- TV metadata API: `https://api.tvmaze.com`
- Secrets: owner-only connection file or runtime injection; never commit API
  keys or provider URLs containing keys
