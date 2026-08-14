# Callup development workflow

## Canonical local instance

The shared canonical instance is the `com.callup.local` macOS LaunchAgent at
<http://localhost:8484>. It has four invariants:

1. It is the latest coherent build that Codex has finished and verified, from
   whatever branch is currently under development.
2. It stays available independently of Codex tasks and terminal sessions.
3. `launchd` starts it at login and restarts it if it exits.
4. `/health` reports the branch, short Git revision, and a `dirty` marker when
   the build included uncommitted source.

"Canonical" means one dependable address and process, not a stable release
channel. During discovery, seeing the current product is more useful than
protecting an older `main` checkpoint.

## Responsibilities

Codex implements changes, runs proportionate automated checks, updates the
durable handoff, and refreshes the canonical instance as part of finishing each
coherent change. Codex does not probe, curl, smoke-test, or otherwise verify the
live instance after deployment; browser acceptance belongs to the user.
Committing and merging are source-control concerns, not gates to browser review.

Provider credentials belong only to the running Callup service; never copy them
into chat, source, command arguments, logs, fixtures, or browser-visible
responses.

Automatic metadata suppliers may also require backend credentials. The local
launch scripts load `.env`, and the TMDB supplier reads its backend-only
`CALLUP_TMDB_ACCESS_TOKEN` from that environment. It is not a user-managed
connection in Settings.

## Connection setup

Open **Connections** in Callup to configure NZBGeek and either SABnzbd or
NZBGet. Secrets are written to an owner-only file outside the repository and
never returned to the browser after submission. Environment variables remain
optional development and deployment fallbacks; neither is required to start
Callup.

## Install once

Codex installs the user LaunchAgent with:

```bash
Scripts/install-canonical-service
```

It builds a release checkpoint, installs the agent, and starts Callup. The agent
binds only to `127.0.0.1:8484`; it is not exposed to the LAN or Internet.

## Refresh the running product

After a coherent change, restart the live app from the repository root:

```bash
./restart
```

This is the public operational command. It installs the LaunchAgent if needed;
otherwise it builds the current checkout, records its branch and revision, and
asks `launchd` to restart the service. Dirty builds are identified explicitly.
If a build fails, the currently running product is left alone. The scripts in
`Scripts/` are implementation details and troubleshooting tools. Codex performs
this refresh automatically after a coherent tested change and stops when
deployment succeeds, without live verification.

## Normal change cycle

1. Implement a coherent change.
2. Run automated tests and relevant safety checks.
3. Update `PROJECT_CONTEXT.md` when the durable state or next step changes.
4. Refresh the always-running instance at <http://localhost:8484> without
   verifying it live afterward.
5. Commit coherent source-control checkpoints and merge when useful.
6. Record any observed provider behavior in sanitized fixtures.

The eventual Linux homelab service should preserve these same invariants using
systemd credentials and a build revision in `/health`; that deployment is a
separate milestone.
