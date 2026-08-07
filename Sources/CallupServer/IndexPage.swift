let indexHTML = #"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Callup</title>
  <style>
    :root { color-scheme: dark; font-family: ui-sans-serif, system-ui, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #0b1017; color: #edf2f7; }
    main { max-width: 980px; margin: 0 auto; padding: 52px 22px 80px; }
    h1 { font-size: clamp(2.7rem, 7vw, 5rem); letter-spacing: -.055em; margin: 8px 0 4px; }
    h2 { margin-top: 36px; }
    h3, p { margin: 0; }
    .lede, .muted, .meta { color: #91a0b3; }
    .lede { font-size: 1.1rem; margin-bottom: 30px; }
    .badge { display: inline-block; color: #64d67c; border: 1px solid #276b38; border-radius: 999px; padding: 4px 10px; }
    .runtime { min-height: 20px; margin: 0 0 18px; font-size: .9rem; }
    form { display: flex; gap: 10px; padding: 14px; background: #131b26; border: 1px solid #263244; border-radius: 14px; }
    input, button { font: inherit; border-radius: 9px; padding: 12px 14px; }
    input { flex: 1; min-width: 0; color: inherit; background: #0b1017; border: 1px solid #344258; }
    button { color: #07120a; background: #53d769; border: 0; font-weight: 760; cursor: pointer; }
    button.secondary { color: #edf2f7; background: #243247; }
    button:disabled { opacity: .55; cursor: wait; }
    .results { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 14px; margin-top: 18px; }
    .series { display: grid; grid-template-columns: 72px 1fr; gap: 14px; align-items: center; padding: 14px; background: #131b26; border: 1px solid #263244; border-radius: 13px; }
    .poster { width: 72px; height: 102px; object-fit: cover; background: #202b3a; border-radius: 8px; }
    .series-copy { display: grid; gap: 7px; min-width: 0; }
    .series button { justify-self: start; padding: 8px 11px; }
    .season { margin-top: 16px; background: #131b26; border: 1px solid #263244; border-radius: 13px; overflow: hidden; }
    .season-header { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 14px 16px; border-bottom: 1px solid #263244; }
    .season-header button { flex: 0 0 auto; padding: 8px 11px; }
    .episode { display: grid; grid-template-columns: 74px 1fr auto; gap: 12px; padding: 11px 16px; border-bottom: 1px solid #202b3a; }
    .episode:last-child { border-bottom: 0; }
    .episode-code { color: #64d67c; font-variant-numeric: tabular-nums; }
    .release-results { padding: 14px 16px; background: #0e151f; border-bottom: 1px solid #263244; }
    .release-summary { margin-bottom: 11px; color: #91a0b3; }
    .candidates { display: grid; gap: 9px; }
    .candidate { display: grid; gap: 5px; padding: 11px 12px; background: #131b26; border: 1px solid #263244; border-radius: 9px; }
    .candidate-title { overflow-wrap: anywhere; }
    .candidate-meta { color: #91a0b3; font-size: .92rem; }
    .status { min-height: 24px; margin-top: 14px; color: #f0b95b; }
    [hidden] { display: none !important; }
    @media (max-width: 600px) {
      form { flex-direction: column; }
      .episode { grid-template-columns: 66px 1fr; }
      .episode .meta { grid-column: 2; }
    }
  </style>
</head>
<body>
<main>
  <span class="badge">Read only</span>
  <h1>Callup</h1>
  <p class="lede">What do you want next?</p>
  <p id="runtime" class="runtime muted"></p>

  <form id="search-form">
    <input id="query" name="q" type="search" placeholder="Search for a television series" autocomplete="off" required>
    <button id="search-button" type="submit">Search</button>
  </form>
  <p id="status" class="status" role="status"></p>

  <section id="search-section" hidden>
    <h2>Matches</h2>
    <div id="results" class="results"></div>
  </section>

  <section id="lineup-section" hidden>
    <h2 id="selected-title">Lineup</h2>
    <p class="muted">Search is read only. Results are unranked and nothing can be downloaded yet.</p>
    <div id="seasons"></div>
  </section>
</main>
<script>
const form = document.querySelector('#search-form');
const runtime = document.querySelector('#runtime');
const query = document.querySelector('#query');
const searchButton = document.querySelector('#search-button');
const status = document.querySelector('#status');
const searchSection = document.querySelector('#search-section');
const results = document.querySelector('#results');
const lineupSection = document.querySelector('#lineup-section');
const selectedTitle = document.querySelector('#selected-title');
const seasons = document.querySelector('#seasons');

loadRuntime();

async function loadRuntime() {
  try {
    const health = await requestJSON('/health');
    const connected = health.indexer === 'nzbgeek';
    const details = [
      'Series and episodes: TVmaze',
      connected ? 'Releases: NZBGeek connected' : 'Releases: NZBGeek not configured',
      health.database === 'sqlite' ? 'Store: SQLite' : null
    ].filter(Boolean);
    if (health.revision && health.revision !== 'unknown') {
      details.push(`Revision: ${health.revision}`);
    }
    runtime.textContent = details.join(' · ');
  } catch {
    runtime.textContent = 'Provider status unavailable';
  }
}

form.addEventListener('submit', async event => {
  event.preventDefault();
  setBusy(searchButton, true, 'Searching…');
  status.textContent = '';
  lineupSection.hidden = true;
  try {
    const data = await requestJSON(`/api/tv/search?q=${encodeURIComponent(query.value)}`);
    renderResults(data.results);
    status.textContent = data.results.length ? '' : 'No matching series found.';
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(searchButton, false, 'Search');
  }
});

function renderResults(items) {
  results.replaceChildren();
  searchSection.hidden = items.length === 0;
  for (const series of items) {
    const card = document.createElement('article');
    card.className = 'series';

    const image = document.createElement('img');
    image.className = 'poster';
    image.alt = '';
    if (series.imageURL) image.src = series.imageURL;

    const copy = document.createElement('div');
    copy.className = 'series-copy';
    const title = document.createElement('h3');
    title.textContent = series.title;
    const meta = document.createElement('p');
    meta.className = 'meta';
    meta.textContent = [series.premieredYear, series.network, series.status].filter(Boolean).join(' · ');
    const select = document.createElement('button');
    select.className = 'secondary';
    select.textContent = 'Show seasons';
    select.addEventListener('click', () => loadSeries(series, select));
    copy.append(title, meta, select);
    card.append(image, copy);
    results.append(card);
  }
}

async function loadSeries(series, button) {
  setBusy(button, true, 'Loading…');
  status.textContent = '';
  try {
    const data = await requestJSON(`/api/tv/series/${encodeURIComponent(series.id.value)}/seasons`);
    renderSeasons(series, data.seasons);
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Show seasons');
  }
}

function renderSeasons(series, items) {
  selectedTitle.textContent = `${series.title} lineup`;
  seasons.replaceChildren();
  for (const season of items) {
    const section = document.createElement('section');
    section.className = 'season';
    const header = document.createElement('div');
    header.className = 'season-header';
    const heading = document.createElement('h3');
    heading.textContent = `Season ${season.number} · ${season.episodes.length} episodes`;
    const findReleases = document.createElement('button');
    findReleases.className = 'secondary';
    findReleases.textContent = 'Find releases';
    const releaseResults = document.createElement('div');
    releaseResults.className = 'release-results';
    releaseResults.hidden = true;
    findReleases.addEventListener('click', () => loadReleases(series, season, findReleases, releaseResults));
    header.append(heading, findReleases);
    section.append(header, releaseResults);
    for (const episode of season.episodes) {
      const row = document.createElement('div');
      row.className = 'episode';
      const code = document.createElement('span');
      code.className = 'episode-code';
      code.textContent = episode.episodeNumber == null
        ? `S${pad(episode.seasonNumber)} special`
        : `S${pad(episode.seasonNumber)}E${pad(episode.episodeNumber)}`;
      const title = document.createElement('span');
      title.textContent = episode.title;
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = [episode.airDate, episode.runtimeMinutes && `${episode.runtimeMinutes} min`].filter(Boolean).join(' · ');
      row.append(code, title, meta);
      section.append(row);
    }
    seasons.append(section);
  }
  lineupSection.hidden = false;
  lineupSection.scrollIntoView({behavior: 'smooth', block: 'start'});
}

async function loadReleases(series, season, button, container) {
  setBusy(button, true, 'Searching…');
  status.textContent = '';
  const parameters = new URLSearchParams({
    q: series.title,
    tvmazeID: series.id.value,
    season: String(season.number)
  });
  try {
    const data = await requestJSON(`/api/tv/releases?${parameters}`);
    renderReleases(data, container);
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Find releases');
  }
}

function renderReleases(data, container) {
  container.replaceChildren();
  const summary = document.createElement('p');
  summary.className = 'release-summary';
  summary.textContent = data.results.length
    ? `${data.results.length} of ${data.total} unranked results shown.`
    : 'No releases were reported for this season.';
  container.append(summary);

  if (data.results.length) {
    const candidates = document.createElement('div');
    candidates.className = 'candidates';
    for (const candidate of data.results) {
      const item = document.createElement('article');
      item.className = 'candidate';
      const title = document.createElement('strong');
      title.className = 'candidate-title';
      title.textContent = candidate.title;
      const traits = [
        candidate.reportedTraits.resolution,
        candidate.reportedTraits.videoCodec,
        formatBytes(candidate.sizeBytes),
        formatCoverage(candidate.coverage),
        formatDate(candidate.publishedAt)
      ].filter(Boolean);
      const meta = document.createElement('p');
      meta.className = 'candidate-meta';
      meta.textContent = traits.join(' · ');
      item.append(title, meta);
      candidates.append(item);
    }
    container.append(candidates);
  }
  container.hidden = false;
}

function formatCoverage(coverage) {
  const episodes = coverage.flatMap(item => item.episodeNumbers.map(number =>
    `S${pad(item.seasonNumber)}E${pad(number)}`
  ));
  return episodes.length ? episodes.join(', ') : 'Coverage not reported';
}

function formatBytes(bytes) {
  if (bytes == null) return null;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit < 2 ? 0 : 1)} ${units[unit]}`;
}

function formatDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date.toLocaleDateString();
}

async function requestJSON(url) {
  const response = await fetch(url);
  const data = await response.json();
  if (!response.ok) throw new Error(data.reason || 'The request failed.');
  return data;
}

function setBusy(button, busy, label) {
  button.disabled = busy;
  button.textContent = label;
}

function pad(number) {
  return String(number).padStart(2, '0');
}
</script>
</body>
</html>
"""#
