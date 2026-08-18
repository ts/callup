# Callup

A server-installed Swift application for finding and queuing television,
movies, music, and books through one understandable acquisition workflow.

Callup uses one shared acquisition workflow for a user's `Lineup` of wanted
media. One search combines cached TVMaze show metadata with cached TMDB movie
metadata. Television continues through the existing tracked-show, episode,
Newznab, and download workflow. Movies can be added to the same tracked view,
tracked movies can show preference-ranked Newznab matches, and a confirmed
release can be sent to the same download client. The Connections screen
configures NZBGeek, TMDB, and one SABnzbd or NZBGet download client.

Tracked television separates following a show from wanting a particular
episode. New shows monitor future episodes by default; **All**, **Future**, and
**None** establish the baseline while episode checkboxes remain explicit
overrides.

Television is the first implementation slice. It is not the product boundary.

## License

Copyright 2026 Tyson Soelberg. Callup is licensed under the GNU Affero General
Public License, version 3 or later. See [LICENSE](LICENSE).

The Callup name and logo are not licensed for use by derivative products.

## Install on Linux

Releases contain a prebuilt, static `x86_64` Linux executable. Installation
never compiles Swift on the destination host. To install a specific release as
root, use its immutable tag:

```bash
curl -fsSL https://raw.githubusercontent.com/ts/callup/v0.1.0-dev.13/deploy/install-from-release.sh | sudo sh -s -- 0.1.0-dev.13
```

The bootstrap downloads the release archive and its SHA-256 file, verifies the
archive, then installs and enables `callup.service`. Runtime configuration is
preserved at `/etc/callup/callup.env`; set the optional library roots there
before restarting the service.

Public artifacts are built from the token-free source with the matching
open-source Swift toolchain and static Linux SDK, then packaged with
`Scripts/package-linux-release VERSION`. The public build script selects the
static x86_64 target explicitly so packaging cannot reuse a stale artifact from
another architecture. `Scripts/build-linux-release` is only for private
credential-bearing builds: it temporarily injects the TMDB token from the
gitignored `.env`, removes the generated source afterward, and its output must
not be published.

```bash
Scripts/build-public-linux-release
Scripts/package-linux-release 0.1.0-dev.13
```

### Proxmox VE

For an optional dedicated LXC, run the versioned creator on the Proxmox host.
It creates a small unprivileged Debian 13 container, installs the same verified
release, and refuses to overwrite an existing container. Set
`CALLUP_MEDIA_SOURCE` only when the host path should be bind-mounted as
`/data`.

```bash
CALLUP_RELEASE=0.1.0-dev.13 bash -c "$(curl -fsSL https://raw.githubusercontent.com/ts/callup/v0.1.0-dev.13/deploy/proxmox-create-lxc.sh)"
```

## Restart the live app

From this directory, run:

```bash
./restart
```

That rebuilds and restarts the persistent local app at
<http://localhost:8484>. It also performs the one-time service installation if
needed. A failed build leaves the currently running version alone.

## Run locally

```bash
swift run callup
```

Open <http://localhost:8484>. The health endpoint is at `/health`.

The interface has bookmarkable top-level views at `/`, `/lineup`,
`/downloads`, and `/settings`. Navigation between them stays inside the live
page. Lineup ordering is calculated server-side; `/lineup?sort=nextAiring`,
`lastDownloaded`, and `title` are supported.

The live app runs as a macOS LaunchAgent independently of an active Codex task.
[`WORKFLOW.md`](WORKFLOW.md) documents the internals when troubleshooting is
needed.

The current API surface is intentionally small:

- `GET /api/search?q=<title>`
- `GET /api/tv/search?q=<series>`
- `GET /api/lineup?sort=nextAiring|lastDownloaded|title`
- `GET /api/tv/series/<tvmaze-id>/seasons`
- `GET /api/tv/releases?q=<series>&tvmazeID=<id>&season=<number>`
- `GET|POST /api/movies/tracked`
- `DELETE /api/movies/tracked/<provider>/<id>`
- `PUT /api/movies/tracked/<provider>/<id>/download-settings`
- `GET /api/movies/tracked/<provider>/<id>/releases`
- `GET /api/downloads`
- `POST /api/downloads`

`CallupNewznab` builds Newznab television searches and normalizes XML results
into provider-neutral release candidates. Credential-bearing NZB URLs never
enter that shared candidate model or browser responses. Manual submissions are
reserved before the external request, store SABnzbd's returned job ID, and
reconcile snatched, downloading, downloaded, and blocked states from SABnzbd.
A lifecycle-managed Swift worker performs that reconciliation at startup and
once per minute, independently of whether the Downloads screen is open.

The Connections screen is the normal setup path. Connection secrets are kept in
an owner-readable `connections.json` beside the database and are never returned
by the settings API. `CALLUP_NZBGEEK_API_KEY` and `CALLUP_NZBGEEK_URL` remain
available as deployment fallbacks; a saved in-app indexer takes precedence.
Movie metadata connections use the same provider-neutral settings collection;
TMDB is the first adapter. Its API Read Access Token is validated before being
saved server-side and takes effect without a restart. Public release artifacts
contain no TMDB credential. `CALLUP_TMDB_ACCESS_TOKEN` remains an optional
deployment override. Local launch scripts load build and runtime overrides from
the gitignored `.env` file. `CALLUP_CONNECTIONS_PATH` can override the
connection file location.

In its homelab container, Callup reads the canonical final library roots
`/data/complete/Television` and `/data/complete/Movies` (never SABnzbd's
working folders), caches a small in-memory inventory for one minute, and marks
conservative title/episode matches as **On disk**. The deployment can override
either canonical root with `CALLUP_TV_LIBRARY_PATH` or
`CALLUP_MOVIE_LIBRARY_PATH`.

## Application store

Callup uses one embedded SQLite database through SQLiteNIO, without an ORM.
Durable product state and replaceable provider cache entries will share this
store while retaining different semantics. The current slice caches TVMaze
series and episode responses, TMDB movie searches and details, and normalized
Newznab searches.

Fresh cache entries are returned directly. Expired entries are returned
immediately and refreshed in the background. Provider cache data is disposable,
contains no credentials or credential-bearing download URLs, and never becomes
the authority for provider facts.

The default macOS database is
`~/Library/Application Support/Callup/callup.sqlite`. Linux deployments should
set `CALLUP_DATABASE_PATH`; it can also override the local path for tests or
operations.

Settings can export a versioned JSON backup containing the Lineup, television
monitoring overrides, media preferences, and download history. Saved connections
are excluded by default and can be included only through an explicit choice,
because they contain credentials. Restoring requires confirmation and replaces
the destination's durable product state in one transaction. Provider caches and
the read-only library inventory are intentionally rebuilt instead of restored.

## Safety

- Do not commit indexer, metadata-provider, SABnzbd, NZBGet, or existing
  application credentials.
- Keep every submission behind a displayed candidate, explicit confirmation,
  durable idempotency record, returned client job ID, and status reconciliation.
