# Callup

A server-installed Swift application for finding and queuing television,
movies, music, and books through one understandable acquisition workflow.

Callup uses one shared acquisition workflow for a user's `Lineup` of wanted
media. The current milestone is deliberately read-only. It searches TVmaze for
series and episode metadata, then can display unranked season candidates from
NZBGeek through its fixture-tested Newznab seam. No credential is stored in the
project, and Callup cannot modify Sonarr or SABnzbd.

Television is the first implementation slice. It is not the product boundary.

## Run locally

```bash
swift run callup
```

Open <http://localhost:8484>. The health endpoint is at `/health`.

For the shared, revision-identifiable local instance, follow
[`WORKFLOW.md`](WORKFLOW.md). It runs as a macOS LaunchAgent independently of an
active Codex task.

The current API surface is intentionally small:

- `GET /api/tv/search?q=<series>`
- `GET /api/tv/series/<tvmaze-id>/seasons`
- `GET /api/tv/releases?q=<series>&tvmazeID=<id>&season=<number>`

`CallupNewznab` builds Newznab television searches and normalizes XML results
into provider-neutral release candidates. Credential-bearing NZB URLs never
enter that shared candidate model or browser responses.

The release route stays disabled until `CALLUP_NZBGEEK_API_KEY` exists in the
server process environment. `CALLUP_NZBGEEK_URL` can override the default API
endpoint. Never put either value in source control or a browser URL.

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

- Do not commit indexer, metadata-provider, SABnzbd, or existing application API
  keys.
- Do not add download submission before a displayed recommendation, explicit
  confirmation, durable idempotency record, and post-submit verification exist.
