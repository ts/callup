# Project: Callup

Status: active
Owner: ts
Last updated: 2026-08-06

## Start here

This document is the durable handoff from the original exploratory conversation.
It should be enough to open `/Users/ts/src/callup` as a standalone project and
continue without reconstructing the product decisions from chat.

### Current executable state

- Vapor service executable: `callup`, listening on `127.0.0.1:8484`.
- The canonical local instance is a macOS LaunchAgent built from clean,
  committed `main`. It survives Codex tasks and restarts independently;
  `/health` reports its deployed source revision. `WORKFLOW.md` defines the
  shared verification and deployment cycle. A forced supervisor restart has
  verified this behavior.
- Browser UI performs live, read-only TVmaze series search and displays seasons
  and episodes. The current source also offers an unranked, read-only release
  search for each season through NZBGeek. The UI labels these provider roles
  separately so indexer connectivity does not imply metadata search switched.
- Generic Newznab code builds TV searches and normalizes XML responses.
  NZBGeek is the first configured indexer.
- `GET /api/tv/releases` is read-only and disabled unless
  `CALLUP_NZBGEEK_API_KEY` exists in the process environment.
- The API key and credential-bearing NZB download URLs are never stored in the
  source models or returned to the browser.
- Six fixture tests pass. Live TVmaze and controlled NZBGeek smoke tests passed.
- No database, queue mutation, SABnzbd submission, media renaming, or library
  management exists yet.

### Immediate next step

Restart the updated build under the existing process-only NZBGeek key and verify
the new connection indicator and unranked season-results UI. Then begin parsing
episode coverage and traits from release titles. Discovery remains intentionally
in-memory; only sanitized response shapes belong in test fixtures during this
phase. Do not rank or submit downloads yet.

### Secret-handling rule learned during setup

Never ask the user to paste a secret into chat, a screenshot, a literal shell
command, or an interactive `read` embedded in a pasted multi-line command. The
original key was exposed during a flawed setup instruction and must not be
reused. The replacement key exists only in the currently running process
environment. The temporary clipboard launcher was removed after startup.

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

Television is the first vertical slice, not the product boundary. The app does
not need to organize the resulting media to make the acquisition workflow
valuable. SABnzbd remains responsible for downloading and its existing category
paths.

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

- Renaming, sorting, moving, importing, or owning a media library.
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

Provider responses must be stored separately from domain models so replacing or
adding a provider does not rewrite the product. Protocol boundaries should be
defined from actual integrations, but cardinality must not be artificially
limited to one.

## Minimal domain model

```text
Media(id, kind, metadataProviderID, externalID, title, attributes)
WorkUnit(id, mediaID, kind, ordinal?, title, attributes)
AcquisitionTarget(id, mediaID, targetKind, attributes)
Policy(id, name, mediaKind?, preferences)
Search(id, targetID, policySnapshot, state)
Provider(id, kind, adapterType, displayName, enabled, priority)
Candidate(id, searchID, providerID, title, sizeBytes, parsedTraits, providerRef)
CandidateCoverage(candidateID, workUnitID)
Decision(candidateID, disposition, rank, reasons[])
Download(id, candidateID, clientID, clientJobID, state, lastObservedAt)
```

The initial schema may use JSON columns for domain attributes, raw provider
payloads, preferences, and parsed traits while each media vocabulary stabilizes.
`CandidateCoverage` is intentionally many-to-many: a release may cover an
episode, several episodes, a season, an album, selected tracks, a movie, or a
particular book edition.

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
- [x] Display normalized candidates without ranking or downloading.
- [x] Build and fixture-test a generic Newznab request/response seam for
  NZBGeek without making a live credentialed call.
- [x] Verify TVmaze decoding using captured, secret-free fixtures.

### Milestone 2 — Understandable recommendations

- [ ] Parse standard release titles into episode, resolution, codec, and source
  traits.
- [ ] Apply resolution and size rules.
- [ ] Recommend one candidate per episode.
- [ ] Show missing episodes and rejection reasons.
- [ ] Add fixture-driven tests for every decision branch.

### Milestone 3 — Queue to SABnzbd

- [ ] Display the complete queue plan before mutation.
- [ ] Submit one approved candidate to the existing SAB category.
- [ ] Persist the provider reference and SAB job ID transactionally.
- [ ] Reconcile queued, downloading, completed, and failed state.
- [ ] Prove repeated submission and process restart cannot duplicate a job.
- [ ] Expand from one episode to **Queue recommended season**.

### Milestone 4 — Make it faster

- [ ] Retry missing episodes without repeating successful work.
- [ ] Remember the last useful preferences per series or globally.
- [ ] Add a lightweight monitored-season scheduler only after manual acquisition
  is trustworthy.
- [ ] Add season-pack selection using the existing candidate-coverage model,
  comparing a pack with the best set of episode releases.

### Subsequent product capabilities

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

- 2026-08-06 — Run the fast-iteration canonical instance as a macOS LaunchAgent
  bound to loopback. Deploy explicit, clean-main release checkpoints without
  coupling the running service to active source edits. Defer Proxmox/systemd
  deployment until durable workflow state and download mutations make a stable
  homelab release valuable. Treat Cloudflare Tunnel as later authenticated
  reachability, not process supervision.
- 2026-08-06 — Normalize development around one canonical local instance on
  port 8484, built from clean committed `main` and identified by its Git revision
  in `/health`. Codex owns automated verification, coherent commits, and the
  canonical process lifecycle; the user owns browser acceptance at useful
  checkpoints and needs no terminal workflow. The local launcher retrieves the
  rotated indexer key from macOS Keychain without storing it in the project.
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
- 2026-08-06 — Use TVmaze for the first read-only television discovery slice.
  Its public API requires no credential and supplies fuzzy series search and
  complete episode lists. Keep provider IDs behind `ProviderReference`.
- 2026-08-05 — Vapor is the server framework; the service targets Linux and is
  operated through a browser.
- 2026-08-05 — Secrets are runtime configuration and must never be committed.

## Active step

**Restart the updated build with environment-only NZBGeek configuration, verify
the visible connection state and unranked season-results UI, then parse coverage
and traits from titles. Keep discovery in-memory and do not rank or download.**

## Open questions

- `/Users/ts/src/callup` is the canonical source repository; Git was initialized
  on `main` on 2026-08-06.
- NZBGeek is the first indexer and exposes the Newznab protocol. The adapter
  currently supports `tvsearch` request generation, pagination fields, and XML
  release normalization. Live capabilities discovery remains unverified.
- TVmaze is the initial television metadata provider and requires no API key for
  the selected public endpoints.
- `UNKNOWN`: Whether the first release should accept only indexer search results
  or also consume its feed for later monitoring.
- `UNKNOWN`: Authentication boundary before exposure through Caddy or Tailscale.

## Known-good and rollback

- Sonarr, SABnzbd, and the indexer continue to operate independently.
- Callup has no credentials and makes no external writes.
- With no `CALLUP_NZBGEEK_API_KEY`, `/health` reports the indexer as
  `not-configured` and `/api/tv/releases` returns HTTP 503 without an external
  request.
- `GET /api/tv/search?q=The%20Good%20Place` returned the expected TVmaze match
  with provider ID `2790`.
- `GET /api/tv/series/2790/seasons` returned four seasons of 13 episodes each;
  the first normalized episode was `S01E01`, "Everything Is Fine."
- The browser UI supports live series search and displays grouped seasons and
  episodes.
- A controlled search for TVmaze series `2790`, season 1, reported 202 NZBGeek
  candidates and returned the first page of 100. All inspected candidates had
  size and publication date; none had reported coverage, resolution, or codec.
  No URL or credential pattern appeared in the browser-safe JSON.
- The `com.callup.local` LaunchAgent returned to healthy state after a forced
  restart, incrementing its launch count while preserving revision identity and
  both provider connections.
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
| 2026-08-06 | Installed the canonical macOS LaunchAgent | Callup runs independently on loopback from explicit release checkpoints and restarts automatically | Forced restart; `/health`; live TVmaze and NZBGeek smoke tests |

## Reference

- Source path: `/Users/ts/src/callup`
- SABnzbd: `http://10.69.42.22:8080`
- Existing indexer: NZBGeek through its Newznab-compatible API
- TV metadata API: `https://api.tvmaze.com`
- Secrets: runtime only; never commit API keys or provider URLs containing keys
