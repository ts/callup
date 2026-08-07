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
coherent change. Committing and merging are source-control concerns, not gates
to browser review. The user needs no terminal workflow and can open the same URL
for browser acceptance whenever useful.

The NZBGeek key belongs only to the service process or macOS Keychain; never
copy it into chat, source, command arguments, logs, fixtures, or browser-visible
responses.

## One-time credential setup

Create a macOS Keychain password item with:

- Name: `callup-nzbgeek-api-key`
- Account: the output of `id -un`
- Password: the rotated NZBGeek API key

The service reads this item directly. The key remains outside the repository and
is passed only in the child service's environment. Manual Keychain creation is
temporary development bootstrap, not the intended product configuration UX.

## Install once

Codex installs the user LaunchAgent with:

```bash
Scripts/install-canonical-service
```

It builds a release checkpoint, installs the agent, and starts Callup. The agent
binds only to `127.0.0.1:8484`; it is not exposed to the LAN or Internet.

## Refresh the running product

After committing a coherent change, Codex runs:

```bash
Scripts/deploy-canonical
```

The script builds the current checkout, records its branch and revision, and
asks `launchd` to restart the service. Dirty builds are identified explicitly.
If a build fails, the currently running product is left alone.
`Scripts/run-canonical` remains a foreground troubleshooting tool, not the
normal runtime.

Codex normally performs this refresh automatically after a coherent tested
change. Verify the exact running source at <http://localhost:8484/health>.

## Normal change cycle

1. Implement a coherent change.
2. Run automated tests and relevant safety checks.
3. Update `PROJECT_CONTEXT.md` when the durable state or next step changes.
4. Refresh the always-running instance at <http://localhost:8484>.
5. Commit coherent source-control checkpoints and merge when useful.
6. Record any observed provider behavior in sanitized fixtures.

The eventual Linux homelab service should preserve these same invariants using
systemd credentials and a build revision in `/health`; that deployment is a
separate milestone.
