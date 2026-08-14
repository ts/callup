# Media Relations Experiment

Status: active thin-slice experiment.

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

## Universal search and views

Callup has one product search, not one search box per media kind or provider.
Metadata adapters return normalized media summaries; the search service merges
and ranks them across television, movies, books, and music. Ambiguous results
remain visible with clear kind and date labels instead of being hidden behind a
fragile classifier.

Provider caches are not the UI read model. Callup maintains a small local,
queryable projection containing the common facts needed for search and views,
such as media identity, kind, title, aliases, relevant dates, status, and image
reference. Provider-specific detail may remain in typed or disposable payloads.
An SQLite full-text index can cover titles and aliases if ordinary indexed
queries stop being sufficient.

Views are fast SQLite queries over that projection and the explicit relations;
they are not separate applications or provider calls. The same result list can
therefore express:

- everything, television, movies, books, or music;
- upcoming television episodes and movies in one date-ordered view;
- past, calendar, tracked, wanted, active, and completed slices;
- later user-defined filters without duplicating media records.

Changing a view updates only local query state and the canonical URL. It must
never wait on a metadata provider, indexer, or download client.

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

## Smallest movie slice

Finding a movie and acquiring it are separate proofs.

To make the existing search find movies, Callup needs only:

1. one movie metadata adapter and cache;
2. one shared media-summary search response containing both shows and movies;
3. one result renderer that labels kind and date and routes to the correct
   canonical media URL.

The indexer and download client are intentionally absent from that first step.
They search releases and execute acquisitions only after the user selects a
canonical media item.

To manually acquire one selected movie, add:

1. an identifier-scoped Newznab movie search;
2. movie-specific candidate verification and video preferences;
3. one movie acquisition target using the shared download context;
4. the existing SABnzbd handoff using the configured movie destination;
5. the existing shared download reconciliation and history.

Do not add automatic monitoring, collections, upgrades, importing, or library
management to this proof.

## Metadata supplier seam

The first implemented step keeps each media domain typed while making its
metadata source replaceable. TVMaze is now one television metadata supplier;
the television catalog searches all configured suppliers and routes detail
requests by provider reference. Cache namespaces derive from the supplier
identity instead of naming TVMaze directly.

This does not yet define Callup-owned media identity, merge the same work across
suppliers, or create universal search. Those remain separate experiments.

## First universal-search proof

The first product search now asks the typed television and movie catalogs
concurrently, then returns one discriminated `kind + media` result stream.
TVMaze and TMDB keep their provider-specific decoding and caches; the UI keeps
typed show behavior while rendering movie discovery in the same result grid.
The next thin slice exposes the already-shared tracked-media persistence for
movies and renders shows and movies in one tracked view. It deliberately does
not add movie detail routes or acquisition.

The following slice resolves one tracked movie through cached detail metadata,
searches Newznab using its normalized IMDb identity, and ranks the read-only
candidate list with the movie's persisted video preferences. Submission remains
a separate mutation. Tracking starts detail hydration after its local write, so
identity enrichment normally finishes before acquisition without delaying the
user action or allowing a late response to re-add removed media.
