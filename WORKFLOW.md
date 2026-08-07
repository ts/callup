# Callup development workflow

## Canonical local instance

The shared canonical instance is the `com.callup.local` macOS LaunchAgent at
<http://localhost:8484>. It has four invariants:

1. Its release binary was built from a clean, committed `main`.
2. Active source edits do not change or restart the deployed checkpoint.
3. `launchd` starts it at login and restarts it if it exits.
4. `/health` reports the short Git revision used to build it.

This makes the browser instance understandable to both the user and Codex. A
healthy process is not necessarily current; its reported revision must match
`git rev-parse --short HEAD`.

## Responsibilities

Codex implements changes, runs proportionate automated checks, updates the
durable handoff, commits a coherent result, and starts or restarts the canonical
instance at agreed checkpoints. The user needs no terminal workflow and performs
browser acceptance when useful.

Deployment is an explicit checkpoint. Restarting after every build would make
the review target unstable and is unnecessary. The NZBGeek key belongs only to
the service process or macOS Keychain; never copy it into chat, source, command
arguments, logs, fixtures, or browser-visible responses.

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

## Deploy a checkpoint

After committing a coherent change, Codex runs:

```bash
Scripts/deploy-canonical
```

The script refuses non-`main` or dirty source, builds the release binary, records
the revision, and asks `launchd` to restart the service. If a build fails, the
currently running checkpoint is left alone. `Scripts/run-canonical` remains a
foreground troubleshooting tool, not the normal runtime.

The user can ask Codex to restart the canonical instance at any time. Verify the
exact running revision at <http://localhost:8484/health> before browser
acceptance.

## Normal change cycle

1. Implement a coherent change.
2. Run automated tests and relevant safety checks.
3. Update `PROJECT_CONTEXT.md` when the durable state or next step changes.
4. Commit the result on `main`.
5. Codex deploys the canonical instance when the user wants to verify that
   checkpoint.
6. Record any observed provider behavior in sanitized fixtures.

The eventual Linux homelab service should preserve these same invariants using
systemd credentials and a build revision in `/health`; that deployment is a
separate milestone.
