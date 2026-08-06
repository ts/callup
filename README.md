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

## Safety

- Do not commit indexer, metadata-provider, SABnzbd, or existing application API
  keys.
- Do not add download submission before a displayed recommendation, explicit
  confirmation, durable idempotency record, and post-submit verification exist.
