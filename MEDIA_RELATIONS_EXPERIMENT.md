# Media Relations Experiment

Status: hypothesis only; no implementation decision yet.

## Question

Can Callup become simpler and more extensible if media remain passive things,
while identity, hierarchy, user intent, preferences, provider responsibility,
candidates, and downloads are modeled as explicit typed relationships around
them?

This branch exists to test that idea without changing the known-good
`media-model` branch. The result may be the right foundation or unnecessary
abstraction. Either outcome is useful.

## Hypothesis

```text
Media
  stable local identity
  kind

Identity
  media <-> external provider reference

Hierarchy
  parent media <-> child media

Tracking
  user intent <-> media

Preferences
  policy <-> media or hierarchy scope

Candidate
  indexer result <-> acquisition targets

Download
  candidate <-> download client and job

Management
  service configuration <-> media kinds or targets it handles
```

The media item does not own tracking, preferences, providers, candidates, or
downloads. Those facts can change independently without changing the media.

For example, one television show may be described by TVmaze, identified by
TheTVDB and IMDb, tracked by the user, governed by a policy inherited by its
episodes, searched through one or more indexers, and downloaded through
SABnzbd. Replacing any provider changes a relationship, not the show.

Managers act by querying relationships:

```text
metadata adapter -> media needing description
indexer adapter  -> acquisition targets needing candidates
download client  -> submissions assigned to that client
monitor          -> tracked leaves due for checking
```

## URL consequence

Product URLs use Callup's media vocabulary and a stable local locator:

```text
/tv/<media-id>
```

Provider names such as `tvmaze` never appear in canonical product URLs.
External identifiers remain replaceable integration details.

## Candidate persistent pieces

The smallest schema worth testing is:

```text
media
media_identifiers
media_relationships
tracked_media
download_submissions
```

These should be concrete typed structures with clear constraints, not one
universal graph or relationship table.

## Evaluation rules

Keep the experiment only if it makes the existing television behavior easier
to explain and makes a movie leaf fit without parallel machinery.

Reject or reduce it if it:

- adds joins and indirection without removing real duplication;
- turns simple provider calls into a generic framework;
- obscures which component owns a mutation;
- weakens identity, idempotency, or foreign-key guarantees;
- makes the current fast UI or API harder to understand;
- invents requirements for music or books before those domains exert pressure.

## First proof

Model one existing tracked show, one episode, and one movie using the proposed
pieces. Compare the resulting types, schema, queries, and mutation paths with
the current `media-model` implementation before changing the application.
