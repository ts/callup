# Callup

A server-installed Swift application for finding and queuing television,
movies, music, and books through one understandable acquisition workflow.

Callup uses one shared acquisition workflow for a user's `Lineup` of wanted
media. The current milestone searches TVmaze for series and episode metadata,
then can display unranked season candidates from NZBGeek through its
fixture-tested Newznab seam. The Connections screen configures NZBGeek and one
SABnzbd or NZBGet download client. With SABnzbd connected, an explicitly
confirmed result can be fetched server-side and uploaded to SABnzbd.

Tracked television separates following a show from wanting a particular
episode. New shows monitor future episodes by default; **All**, **Future**, and
**None** establish the baseline while episode checkboxes remain explicit
overrides.

Television is the first implementation slice. It is not the product boundary.

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

The live app runs as a macOS LaunchAgent independently of an active Codex task.
[`WORKFLOW.md`](WORKFLOW.md) documents the internals when troubleshooting is
needed.

The current API surface is intentionally small:

- `GET /api/tv/search?q=<series>`
- `GET /api/tv/series/<tvmaze-id>/seasons`
- `GET /api/tv/releases?q=<series>&tvmazeID=<id>&season=<number>`
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
`CALLUP_CONNECTIONS_PATH` can override the connection file location.

## Application store

Callup uses one embedded SQLite database through SQLiteNIO, without an ORM.
Durable product state and replaceable provider cache entries will share this
store while retaining different semantics. The current slice caches TVmaze
series and episode responses and normalized Newznab searches.

Fresh cache entries are returned directly. Expired entries are returned
immediately and refreshed in the background. Provider cache data is disposable,
contains no credentials or credential-bearing download URLs, and never becomes
the authority for provider facts.

The default macOS database is
`~/Library/Application Support/Callup/callup.sqlite`. Linux deployments should
set `CALLUP_DATABASE_PATH`; it can also override the local path for tests or
operations.

## Safety

- Do not commit indexer, metadata-provider, SABnzbd, NZBGet, or existing
  application credentials.
- Keep every submission behind a displayed candidate, explicit confirmation,
  durable idempotency record, returned client job ID, and status reconciliation.
