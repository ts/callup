# Callup development workflow

## Canonical local instance

The shared canonical instance is the service at <http://localhost:8484>. It has
three invariants:

1. It runs from the `main` branch.
2. Its working tree was clean when it started.
3. `/health` reports the short Git revision used to start it.

This makes the browser instance understandable to both the user and Codex. A
healthy process is not necessarily current; its reported revision must match
`git rev-parse --short HEAD`.

## Responsibilities

Codex implements changes, runs proportionate automated checks, updates the
durable handoff, commits a coherent result, and starts or restarts the canonical
instance at agreed checkpoints. The user needs no terminal workflow and performs
browser acceptance when useful.

Restarting is an explicit handoff point because the NZBGeek key belongs only to
the service process or macOS Keychain. Never copy it into chat, source, command
arguments, logs, fixtures, or browser-visible responses.

## One-time credential setup

Create a macOS Keychain password item with:

- Name: `callup-nzbgeek-api-key`
- Account: the output of `id -un`
- Password: the rotated NZBGeek API key

The launcher reads this item directly. The key remains outside the repository
and is passed only in the child service's environment.

## Start or restart

Codex stops the existing Callup process and runs:

```bash
Scripts/run-canonical
```

The launcher refuses to start from a non-`main` branch or a dirty working tree,
builds the committed source, retrieves the key from Keychain when it is not
already in the environment, and starts Callup on port 8484.

The user can ask Codex to restart the canonical instance at any time. Verify the
exact running revision at <http://localhost:8484/health> before browser
acceptance.

## Normal change cycle

1. Implement a coherent change.
2. Run automated tests and relevant safety checks.
3. Update `PROJECT_CONTEXT.md` when the durable state or next step changes.
4. Commit the result on `main`.
5. Codex restarts the canonical instance when the user wants to verify that
   checkpoint.
6. Record any observed provider behavior in sanitized fixtures.

The eventual Linux homelab service should preserve these same invariants using
systemd credentials and a build revision in `/health`; that deployment is a
separate milestone.
