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
    .topbar { display: flex; align-items: center; justify-content: space-between; gap: 18px; }
    .topbar-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; }
    .topbar-actions a { color: #b7c4d4; background: transparent; border: 1px solid #344258; border-radius: 9px; padding: 12px 14px; font-weight: 760; text-decoration: none; }
    .topbar-actions a[aria-current="page"] { color: #edf2f7; background: #243247; }
    .brand { min-width: 0; }
    .brand a { color: inherit; text-decoration: none; }
    .lede, .muted, .meta { color: #91a0b3; }
    .lede { font-size: 1.1rem; margin-bottom: 30px; }
    .badge { display: inline-block; color: #64d67c; border: 1px solid #276b38; border-radius: 999px; padding: 4px 10px; }
    .runtime { min-height: 20px; margin: 0 0 18px; font-size: .9rem; }
    form { background: #131b26; border: 1px solid #263244; border-radius: 14px; }
    .search-form { display: flex; gap: 10px; padding: 14px; }
    input, select, button { font: inherit; border-radius: 9px; padding: 12px 14px; }
    input[type="search"] { flex: 1; min-width: 0; color: inherit; background: #0b1017; border: 1px solid #344258; }
    input[type="url"], input[type="text"], input[type="password"], select { width: 100%; color: inherit; background: #0b1017; border: 1px solid #344258; }
    input[type="checkbox"] { width: 18px; height: 18px; margin: 0; accent-color: #53d769; cursor: pointer; }
    button { color: #07120a; background: #53d769; border: 0; font-weight: 760; cursor: pointer; }
    button.secondary { color: #edf2f7; background: #243247; }
    button.ghost, a.ghost { color: #b7c4d4; background: transparent; border: 1px solid #344258; }
    a.ghost { border-radius: 9px; padding: 12px 14px; font-weight: 760; text-decoration: none; }
    button:disabled { opacity: .55; cursor: wait; }
    .results { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 14px; margin-top: 18px; }
    .tracked-heading { display: flex; align-items: end; justify-content: space-between; gap: 16px; margin-top: 36px; }
    .tracked-heading h2 { margin: 0; }
    .search-heading { display: flex; align-items: end; justify-content: space-between; gap: 16px; margin-top: 36px; }
    .search-heading h2 { margin: 0; }
    .view-toggle { display: inline-flex; flex: 0 0 auto; padding: 3px; background: #131b26; border: 1px solid #344258; border-radius: 10px; }
    .view-toggle button { padding: 6px 10px; color: #91a0b3; background: transparent; border-radius: 7px; font-size: .85rem; }
    .view-toggle button[aria-pressed="true"] { color: #edf2f7; background: #344258; }
    .tracked-results.list-view { grid-template-columns: 1fr; gap: 0; }
    .tracked-results.list-view .series { grid-template-columns: 1fr; gap: 0; padding: 12px 0; background: transparent; border: 0; border-bottom: 1px solid #263244; border-radius: 0; }
    .tracked-results.list-view .poster { display: none; }
    .tracked-results.list-view .series-copy { grid-template-columns: minmax(140px, 1.4fr) minmax(110px, 1fr) minmax(130px, 1fr) auto; align-items: center; gap: 12px; }
    .tracked-results.list-view .series-actions { flex-wrap: nowrap; justify-content: flex-end; }
    .connections { padding: 20px 0 4px; }
    .connections-heading { display: flex; align-items: end; justify-content: space-between; gap: 16px; margin-bottom: 14px; }
    .connections-heading h2 { margin: 0; }
    .utility-panel { padding: 20px 0 4px; }
    .utility-heading { display: flex; align-items: end; justify-content: space-between; gap: 16px; margin-bottom: 14px; }
    .utility-heading h2 { margin: 0; }
    .connection-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .connection-form { display: grid; gap: 13px; padding: 18px; }
    .connection-title { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
    .connection-status { color: #91a0b3; font-size: .88rem; }
    .connection-status.connected { color: #64d67c; }
    .field { display: grid; gap: 6px; color: #b7c4d4; font-size: .9rem; }
    .field-note { color: #738399; font-size: .82rem; }
    .form-actions { display: flex; flex-wrap: wrap; gap: 8px; }
    .series { display: grid; grid-template-columns: 72px 1fr; gap: 14px; align-items: center; padding: 14px; background: #131b26; border: 1px solid #263244; border-radius: 13px; }
    .poster { width: 72px; height: 102px; object-fit: cover; background: #202b3a; border-radius: 8px; }
    .series-copy { display: grid; gap: 7px; min-width: 0; }
    .media-heading { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
    .media-kind { flex: 0 0 auto; padding: 3px 7px; color: #b7c4d4; background: #243247; border-radius: 999px; font-size: .72rem; font-weight: 760; text-transform: uppercase; letter-spacing: .04em; }
    .airing-status { color: #64d67c; font-size: .88rem; font-weight: 720; }
    .airing-status.ended { color: #91a0b3; }
    .airing-status.missing { color: #91a0b3; }
    .series-actions { display: flex; flex-wrap: wrap; gap: 8px; }
    .series button { padding: 8px 11px; }
    .empty { margin-top: 12px; }
    .season { margin-top: 16px; background: #131b26; border: 1px solid #263244; border-radius: 13px; overflow: hidden; }
    .season-header { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 14px 16px; border-bottom: 1px solid #263244; }
    .season-header button { flex: 0 0 auto; padding: 8px 11px; }
    .season-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; }
    .season-choice { display: flex; align-items: center; gap: 10px; }
    .download-settings { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-top: 16px; padding: 14px 16px; background: #131b26; border: 1px solid #263244; border-radius: 13px; }
    .download-settings-copy { display: grid; gap: 4px; }
    .download-settings-choice { display: flex; align-items: center; gap: 10px; color: #edf2f7; font-weight: 720; }
    .download-preferences { display: grid; grid-template-columns: repeat(3, minmax(120px, 1fr)); gap: 10px; min-width: min(100%, 460px); }
    .download-preferences .field { font-size: .82rem; }
    .episode { display: grid; grid-template-columns: 74px 1fr auto auto; gap: 12px; padding: 11px 16px; border-bottom: 1px solid #202b3a; }
    .episode.selectable { grid-template-columns: 18px 74px 1fr auto auto; align-items: center; }
    .episode:last-child { border-bottom: 0; }
    .episode.has-download { background: #12251a; }
    .episode-download-state { display: inline-block; margin-left: 8px; padding: 3px 8px; border-radius: 999px; color: #c8f8d0; background: #276b38; font-size: .78rem; font-weight: 750; }
    .episode-code { color: #64d67c; font-variant-numeric: tabular-nums; }
    .episode-search { padding: 6px 9px; }
    .release-results { padding: 14px 16px; background: #0e151f; border-bottom: 1px solid #263244; }
    .episode-releases { padding: 10px 16px 14px 120px; background: #0e151f; border-bottom: 1px solid #263244; }
    .episode-releases .candidates { margin-top: 0; }
    .release-options { display: grid; gap: 9px; margin-top: 9px; }
    .release-options-toggle { color: #b7c4d4; background: transparent; border: 1px solid #344258; }
    .release-summary { margin-bottom: 11px; color: #91a0b3; }
    .candidates { display: grid; gap: 9px; }
    .candidate { display: grid; gap: 5px; padding: 11px 12px; background: #131b26; border: 1px solid #263244; border-radius: 9px; }
    .candidate-title { overflow-wrap: anywhere; }
    .candidate-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; color: #91a0b3; font-size: .92rem; }
    .candidate-actions { display: flex; align-items: center; gap: 9px; margin-top: 5px; }
    .candidate-actions button { padding: 8px 11px; }
    .download-list { display: grid; gap: 9px; margin-top: 14px; }
    .download-row { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 13px 14px; background: #131b26; border: 1px solid #263244; border-radius: 11px; }
    .download-title { min-width: 0; overflow-wrap: anywhere; }
    .download-state { flex: 0 0 auto; padding: 3px 8px; border-radius: 999px; color: #dce6f2; background: #344258; font-size: .8rem; font-weight: 750; text-transform: capitalize; }
    .download-state-downloading { color: #b9e8ff; background: #23566f; }
    .download-state-downloaded { color: #c8f8d0; background: #276b38; }
    .download-state-blocked { color: #ffd7a1; background: #744b1f; }
    .trait-pill { display: inline-block; padding: 2px 7px; border-radius: 999px; color: #edf2f7; background: #344258; font-size: .78rem; font-weight: 700; line-height: 1.4; }
    .trait-resolution { background: #315b9b; }
    .trait-resolution-2160p { background: #7047a3; }
    .trait-resolution-1080p, .trait-resolution-1080i { background: #315b9b; }
    .trait-resolution-720p { background: #267080; }
    .trait-resolution-576p, .trait-resolution-480p { background: #4d6172; }
    .trait-codec { background: #2d7550; }
    .trait-codec-hevc { background: #2d7550; }
    .trait-codec-avc { background: #71612e; }
    .trait-codec-av1 { background: #8a493d; }
    .trait-codec-mpeg-2 { background: #6f4e70; }
    .trait-source { background: #704e86; }
    .trait-coverage { background: #49596e; }
    .status { min-height: 24px; margin-top: 14px; color: #f0b95b; }
    .metadata-credits { display: grid; gap: 8px; margin-top: 28px; padding-top: 22px; border-top: 1px solid #263244; }
    .metadata-credits img { display: block; width: 42px; height: 42px; }
    .metadata-credits .notice { max-width: 620px; font-size: .82rem; }
    [hidden] { display: none !important; }
    @media (max-width: 600px) {
      .search-form { flex-direction: column; }
      .connection-grid { grid-template-columns: 1fr; }
      .topbar { align-items: flex-start; }
      .tracked-results.list-view .series-copy { grid-template-columns: 1fr; gap: 6px; }
      .tracked-results.list-view .series-actions { justify-content: flex-start; margin-top: 3px; }
      .episode { grid-template-columns: 66px 1fr; }
      .episode.selectable { grid-template-columns: 18px 66px 1fr; }
      .episode .meta { grid-column: 2; }
      .episode.selectable .meta { grid-column: 3; }
      .episode .episode-search { grid-column: 2; justify-self: start; }
      .episode.selectable .episode-search { grid-column: 3; }
      .episode-releases { padding-left: 16px; }
      .download-settings { align-items: stretch; flex-direction: column; }
      .download-preferences { min-width: 0; }
    }
  </style>
</head>
<body>
<main>
  <div class="topbar">
    <div class="brand">
      <span class="badge">Tracking</span>
      <h1><a href="/" data-route>Callup</a></h1>
      <p class="lede">What do you want next?</p>
    </div>
    <nav class="topbar-actions" aria-label="Primary">
      <a href="/" data-route>Home</a>
      <a href="/downloads" data-route>Downloads</a>
      <a href="/settings" data-route>Settings</a>
    </nav>
  </div>
  <p id="runtime" class="runtime muted"></p>
  <p id="status" class="status" role="status"></p>

  <section id="connections-section" class="connections" data-view="settings" hidden>
    <div class="connections-heading">
      <div>
        <h2>Settings</h2>
        <p class="muted">Search in one place. Send approved downloads to one client.</p>
      </div>
      <a class="ghost" href="/" data-route>Done</a>
    </div>
    <div class="connection-grid">
      <form id="indexer-form" class="connection-form">
        <div class="connection-title">
          <h3>Search indexer</h3>
          <span id="indexer-status" class="connection-status">Not connected</span>
        </div>
        <label class="field">Name
          <input id="indexer-name" type="text" value="NZBGeek" autocomplete="off" required>
        </label>
        <label class="field">Address
          <input id="indexer-endpoint" type="url" value="https://api.nzbgeek.info/api" required>
        </label>
        <label class="field">API key
          <input id="indexer-key" type="password" autocomplete="new-password" placeholder="Leave blank to keep the saved key">
          <span class="field-note">Stored only on the Callup server.</span>
        </label>
        <div class="form-actions">
          <button id="indexer-save" type="submit">Save indexer</button>
          <button id="indexer-remove" class="ghost" type="button" hidden>Remove</button>
        </div>
      </form>

      <form id="download-client-form" class="connection-form">
        <div class="connection-title">
          <h3>Download client</h3>
          <span id="download-client-status" class="connection-status">Not connected</span>
        </div>
        <label class="field">Client
          <select id="download-client-kind">
            <option value="sabnzbd">SABnzbd</option>
            <option value="nzbget">NZBGet</option>
          </select>
        </label>
        <label class="field">Address
          <input id="download-client-endpoint" type="url" placeholder="http://server:8080" required>
        </label>
        <label id="download-client-username-field" class="field" hidden>Username
          <input id="download-client-username" type="text" autocomplete="username">
        </label>
        <label class="field"><span id="download-client-secret-label">API key</span>
          <input id="download-client-secret" type="password" autocomplete="new-password" placeholder="Leave blank to keep the saved credential">
          <span class="field-note">Callup tests the connection before saving it.</span>
        </label>
        <div class="form-actions">
          <button id="download-client-save" type="submit">Connect SABnzbd</button>
          <button id="download-client-remove" class="ghost" type="button" hidden>Remove</button>
        </div>
      </form>
    </div>
    <div class="metadata-credits">
      <h3>Metadata sources</h3>
      <p class="muted">TVMaze and TMDB are built in, cached locally, and used automatically.</p>
      <a href="https://www.themoviedb.org" target="_blank" rel="noreferrer" aria-label="The Movie Database">
        <img src="https://www.themoviedb.org/assets/2/v4/logos/v2/blue_square_1-5bdc75aaebeb75dc7ae79426ddd9be3b2be1e342510f8202baf6bffa71d7f5c4.svg" alt="TMDB">
      </a>
      <p class="notice muted">This product uses the TMDB API but is not endorsed or certified by TMDB.</p>
    </div>
  </section>

  <section id="downloads-section" class="utility-panel" data-view="downloads" hidden>
    <div class="utility-heading">
      <div>
        <h2>Downloads</h2>
        <p class="muted">Recent download activity and completed history.</p>
      </div>
      <a class="ghost" href="/" data-route>Done</a>
    </div>
    <p id="downloads-empty" class="empty muted">No download activity yet.</p>
    <div id="download-results" class="download-list"></div>
  </section>

  <div id="home-view" data-view="home" hidden>
    <form id="search-form" class="search-form">
      <input id="query" name="q" type="search" placeholder="Search for a show or movie" autocomplete="off" required>
      <button id="search-button" type="submit">Search</button>
    </form>

    <section id="tracked-section">
      <div class="tracked-heading">
        <h2>Tracked</h2>
        <div class="view-toggle" role="group" aria-label="Tracked media view">
          <button type="button" data-tracked-view="cards" aria-pressed="true">Cards</button>
          <button type="button" data-tracked-view="list" aria-pressed="false">List</button>
        </div>
      </div>
      <p id="tracked-empty" class="empty muted">Nothing tracked yet.</p>
      <div id="tracked-results" class="results tracked-results"></div>
    </section>

    <section id="search-section" hidden>
      <div class="search-heading">
        <h2>Matches</h2>
        <div class="view-toggle" role="group" aria-label="Filter search results">
          <button type="button" data-search-filter="all" aria-pressed="true">All</button>
          <button type="button" data-search-filter="tv" aria-pressed="false">TV</button>
          <button type="button" data-search-filter="movies" aria-pressed="false">Movies</button>
        </div>
      </div>
      <p id="search-empty" class="empty muted" hidden></p>
      <div id="results" class="results"></div>
    </section>

    <section id="movie-release-section" hidden>
      <h2 id="selected-movie-title">Movie matches</h2>
      <div class="download-settings">
        <div class="download-settings-copy">
          <strong>Preferred match</strong>
          <span class="field-note">Preferences reorder the complete result list.</span>
        </div>
        <div class="download-preferences">
          <label class="field">Resolution
            <select id="movie-resolution">
              <option value="any">Any</option>
              <option value="2160p">2160p</option>
              <option value="1080p">1080p</option>
              <option value="720p">720p</option>
              <option value="480p">480p</option>
            </select>
          </label>
          <label class="field">Video codec
            <select id="movie-codec">
              <option value="any">Any</option>
              <option value="HEVC">HEVC</option>
              <option value="AVC">AVC</option>
              <option value="AV1">AV1</option>
              <option value="MPEG-2">MPEG-2</option>
            </select>
          </label>
        </div>
      </div>
      <p id="movie-release-summary" class="release-summary"></p>
      <div id="movie-release-results" class="candidates"></div>
    </section>

    <section id="lineup-section" hidden>
      <h2 id="selected-title">Lineup</h2>
      <p id="lineup-description" class="muted"></p>
      <div id="seasons"></div>
    </section>
  </div>
</main>
<script>
const form = document.querySelector('#search-form');
const routeLinks = document.querySelectorAll('[data-route]');
const views = document.querySelectorAll('[data-view]');
const indexerForm = document.querySelector('#indexer-form');
const indexerName = document.querySelector('#indexer-name');
const indexerEndpoint = document.querySelector('#indexer-endpoint');
const indexerKey = document.querySelector('#indexer-key');
const indexerSave = document.querySelector('#indexer-save');
const indexerRemove = document.querySelector('#indexer-remove');
const indexerStatus = document.querySelector('#indexer-status');
const downloadClientForm = document.querySelector('#download-client-form');
const downloadClientKind = document.querySelector('#download-client-kind');
const downloadClientEndpoint = document.querySelector('#download-client-endpoint');
const downloadClientUsernameField = document.querySelector('#download-client-username-field');
const downloadClientUsername = document.querySelector('#download-client-username');
const downloadClientSecretLabel = document.querySelector('#download-client-secret-label');
const downloadClientSecret = document.querySelector('#download-client-secret');
const downloadClientSave = document.querySelector('#download-client-save');
const downloadClientRemove = document.querySelector('#download-client-remove');
const downloadClientStatus = document.querySelector('#download-client-status');
const runtime = document.querySelector('#runtime');
const query = document.querySelector('#query');
const searchButton = document.querySelector('#search-button');
const status = document.querySelector('#status');
const trackedEmpty = document.querySelector('#tracked-empty');
const trackedResults = document.querySelector('#tracked-results');
const trackedViewButtons = document.querySelectorAll('[data-tracked-view]');
const downloadsSection = document.querySelector('#downloads-section');
const downloadsEmpty = document.querySelector('#downloads-empty');
const downloadResults = document.querySelector('#download-results');
const searchSection = document.querySelector('#search-section');
const searchEmpty = document.querySelector('#search-empty');
const searchFilterButtons = document.querySelectorAll('[data-search-filter]');
const results = document.querySelector('#results');
const movieReleaseSection = document.querySelector('#movie-release-section');
const selectedMovieTitle = document.querySelector('#selected-movie-title');
const movieResolution = document.querySelector('#movie-resolution');
const movieCodec = document.querySelector('#movie-codec');
const movieReleaseSummary = document.querySelector('#movie-release-summary');
const movieReleaseResults = document.querySelector('#movie-release-results');
const lineupSection = document.querySelector('#lineup-section');
const selectedTitle = document.querySelector('#selected-title');
const lineupDescription = document.querySelector('#lineup-description');
const seasons = document.querySelector('#seasons');
const trackedSeries = new Map();
const trackedMovies = new Map();
let lastSearchResults = [];
let activeSearchFilter = 'all';
const displayedSeasons = [];
let episodeMonitoring = 'all';
let futureCutoffDate = null;
let excludedSeasons = new Set();
let excludedEpisodes = new Set();
let includedEpisodes = new Set();
let displayedSeriesKey = null;
let displayedMovie = null;
let activeDownloadClientKind = null;
const downloadSubmissions = new Map();
let onDiskEpisodeKeys = new Set();

setTrackedView(loadTrackedView());
renderRoute();
loadRuntime();
loadTrackedMedia();
loadConnections();
loadDownloads();
setInterval(loadDownloads, 15_000);

for (const button of trackedViewButtons) {
  button.addEventListener('click', () => setTrackedView(button.dataset.trackedView));
}

for (const button of searchFilterButtons) {
  button.addEventListener('click', () => setSearchFilter(button.dataset.searchFilter));
}

function loadTrackedView() {
  try {
    return localStorage.getItem('callup.trackedView') || 'cards';
  } catch {
    return 'cards';
  }
}

function setTrackedView(view) {
  const selectedView = view === 'list' ? 'list' : 'cards';
  trackedResults.classList.toggle('list-view', selectedView === 'list');
  for (const button of trackedViewButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.trackedView === selectedView));
  }
  try {
    localStorage.setItem('callup.trackedView', selectedView);
  } catch {}
}

function setSearchFilter(filter) {
  activeSearchFilter = ['tv', 'movies'].includes(filter) ? filter : 'all';
  for (const button of searchFilterButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.searchFilter === activeSearchFilter));
  }
  renderResults(lastSearchResults);
}

for (const link of routeLinks) {
  link.addEventListener('click', event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    navigate(link.pathname);
  });
}
window.addEventListener('popstate', renderRoute);

function navigate(path) {
  if (window.location.pathname !== path) history.pushState({}, '', path);
  renderRoute();
  window.scrollTo({top: 0});
}

function renderRoute() {
  const route = window.location.pathname === '/settings'
    ? 'settings'
    : window.location.pathname === '/downloads' ? 'downloads' : 'home';
  for (const view of views) view.hidden = view.dataset.view !== route;
  for (const link of routeLinks) {
    if (link.closest('.topbar-actions')) {
      const selected = link.pathname === window.location.pathname;
      if (selected) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    }
  }
  document.title = route === 'home'
    ? 'Callup'
    : `${route[0].toUpperCase()}${route.slice(1)} · Callup`;
  status.textContent = '';
}

downloadClientKind.addEventListener('change', applyDownloadClientKind);

function applyDownloadClientKind() {
  const isNZBGet = downloadClientKind.value === 'nzbget';
  downloadClientUsernameField.hidden = !isNZBGet;
  downloadClientSecretLabel.textContent = isNZBGet ? 'Password' : 'API key';
  downloadClientEndpoint.placeholder = isNZBGet ? 'http://server:6789' : 'http://server:8080';
  downloadClientSave.textContent = `Connect ${isNZBGet ? 'NZBGet' : 'SABnzbd'}`;
}

async function loadConnections() {
  try {
    renderConnections(await requestJSON('/api/settings/connections'));
  } catch (error) {
    status.textContent = error.message;
  }
}

function renderConnections(data) {
  if (data.indexer) {
    indexerName.value = data.indexer.name;
    indexerEndpoint.value = data.indexer.endpoint;
    indexerStatus.textContent = data.indexer.source === 'environment' ? 'Connected for this run' : 'Connected';
    indexerStatus.classList.add('connected');
    indexerRemove.hidden = data.indexer.source === 'environment';
  } else {
    indexerStatus.textContent = 'Not connected';
    indexerStatus.classList.remove('connected');
    indexerRemove.hidden = true;
  }
  if (data.downloadClient) {
    activeDownloadClientKind = data.downloadClient.kind;
    downloadClientKind.value = data.downloadClient.kind;
    downloadClientEndpoint.value = data.downloadClient.endpoint;
    downloadClientUsername.value = data.downloadClient.username || '';
    downloadClientStatus.textContent = `Connected · ${data.downloadClient.name}`;
    downloadClientStatus.classList.add('connected');
    downloadClientRemove.hidden = false;
  } else {
    activeDownloadClientKind = null;
    downloadClientStatus.textContent = 'Not connected';
    downloadClientStatus.classList.remove('connected');
    downloadClientRemove.hidden = true;
  }
  applyDownloadClientKind();
}

async function loadDownloads() {
  try {
    const data = await requestJSON('/api/downloads');
    downloadSubmissions.clear();
    for (const submission of data.results) {
      downloadSubmissions.set(providerKey(submission.candidateID), submission);
    }
    renderDownloads(data.results);
  } catch (error) {
    status.textContent = error.message;
  }
}

function renderDownloads(items) {
  downloadResults.replaceChildren();
  downloadsEmpty.hidden = items.length !== 0;
  for (const submission of items) {
    const row = document.createElement('article');
    row.className = 'download-row';
    const title = document.createElement('strong');
    title.className = 'download-title';
    title.textContent = submission.title;
    const state = document.createElement('span');
    state.className = `download-state download-state-${submission.state}`;
    state.textContent = downloadStateLabel(submission.state);
    row.append(title, state);
    downloadResults.append(row);
  }
  for (const button of document.querySelectorAll('[data-download-key]')) {
    applyDownloadButtonState(button, downloadSubmissions.get(button.dataset.downloadKey));
  }
  applyEpisodeDownloadStates(items);
  renderTrackedMedia();
}

function applyEpisodeDownloadStates(items) {
  const stateRank = {blocked: 0, sending: 1, snatched: 2, downloading: 3, downloaded: 4};
  const episodeStates = new Map();
  for (const submission of items) {
    const episodeIDs = (submission.acquisitionContext?.targets || [])
      .filter(target => target.media.kind === 'televisionEpisode')
      .map(target => target.media.id);
    for (const episodeID of episodeIDs) {
      const key = providerKey(episodeID);
      const current = episodeStates.get(key);
      if (!current || (stateRank[submission.state] ?? 0) > (stateRank[current] ?? 0)) {
        episodeStates.set(key, submission.state);
      }
    }
  }
  for (const row of document.querySelectorAll('[data-download-episode-key]')) {
    row.classList.remove('has-download');
    row.querySelector('.episode-download-state')?.remove();
    const episodeState = episodeStates.get(row.dataset.downloadEpisodeKey);
    if (!episodeState) continue;
    row.classList.add('has-download');
    if (episodeState === 'downloaded') {
      const checkbox = row.querySelector('[data-episode-key]');
      if (checkbox) checkbox.checked = false;
    }
    const badge = document.createElement('span');
    badge.className = 'episode-download-state';
    badge.textContent = downloadStateLabel(episodeState);
    row.querySelector('.episode-title').append(badge);
  }
  for (const section of document.querySelectorAll('.season')) {
    const seasonCheckbox = section.querySelector('[data-season-choice]');
    if (!seasonCheckbox) continue;
    const episodeCheckboxes = [...section.querySelectorAll('[data-episode-key]')];
    const checkedCount = episodeCheckboxes.filter(input => input.checked).length;
    seasonCheckbox.checked = episodeCheckboxes.length > 0
      && checkedCount === episodeCheckboxes.length;
    seasonCheckbox.indeterminate = checkedCount > 0 && checkedCount < episodeCheckboxes.length;
  }
  applyEpisodeLibraryStates();
}

function applyEpisodeLibraryStates() {
  for (const row of document.querySelectorAll('[data-download-episode-key]')) {
    row.querySelector('.episode-library-state')?.remove();
    if (!onDiskEpisodeKeys.has(row.dataset.downloadEpisodeKey)) continue;
    row.classList.add('has-download');
    const checkbox = row.querySelector('[data-episode-key]');
    if (checkbox) checkbox.checked = false;
    const badge = document.createElement('span');
    badge.className = 'episode-download-state episode-library-state';
    badge.textContent = 'On disk';
    row.querySelector('.episode-title').append(badge);
  }
  for (const section of document.querySelectorAll('.season')) {
    const seasonCheckbox = section.querySelector('[data-season-choice]');
    if (!seasonCheckbox) continue;
    const episodeCheckboxes = [...section.querySelectorAll('[data-episode-key]')];
    const checkedCount = episodeCheckboxes.filter(input => input.checked).length;
    seasonCheckbox.checked = episodeCheckboxes.length > 0
      && checkedCount === episodeCheckboxes.length;
    seasonCheckbox.indeterminate = checkedCount > 0 && checkedCount < episodeCheckboxes.length;
  }
}

function downloadStateLabel(state) {
  return ({
    sending: 'Sending',
    snatched: 'Snatched',
    downloading: 'Downloading',
    downloaded: 'Downloaded',
    blocked: 'Blocked'
  })[state] || state;
}

function movieDownloadState(movie) {
  const stateRank = {blocked: 0, sending: 1, snatched: 2, downloading: 3, downloaded: 4};
  let strongest = null;
  for (const submission of downloadSubmissions.values()) {
    const matchesMovie = (submission.acquisitionContext?.targets || []).some(target =>
      target.media.kind === 'movie' && providerKey(target.media.id) === providerKey(movie.id)
    );
    if (!matchesMovie) continue;
    if (strongest === null || (stateRank[submission.state] ?? 0) > (stateRank[strongest] ?? 0)) {
      strongest = submission.state;
    }
  }
  return strongest;
}

indexerForm.addEventListener('submit', async event => {
  event.preventDefault();
  setBusy(indexerSave, true, 'Saving…');
  status.textContent = '';
  try {
    const data = await requestJSON('/api/settings/connections/indexer', {
      method: 'PUT',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({name: indexerName.value, endpoint: indexerEndpoint.value, apiKey: indexerKey.value || null})
    });
    indexerKey.value = '';
    renderConnections(data);
    await loadRuntime();
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(indexerSave, false, 'Save indexer');
  }
});

downloadClientForm.addEventListener('submit', async event => {
  event.preventDefault();
  setBusy(downloadClientSave, true, 'Testing…');
  status.textContent = '';
  try {
    const data = await requestJSON('/api/settings/connections/download-client', {
      method: 'PUT',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({
        kind: downloadClientKind.value,
        endpoint: downloadClientEndpoint.value,
        username: downloadClientUsername.value || null,
        secret: downloadClientSecret.value || null
      })
    });
    downloadClientSecret.value = '';
    renderConnections(data);
    await loadRuntime();
  } catch (error) {
    status.textContent = error.message;
  } finally {
    applyDownloadClientKind();
    downloadClientSave.disabled = false;
  }
});

indexerRemove.addEventListener('click', async () => {
  await removeConnection('/api/settings/connections/indexer');
});
downloadClientRemove.addEventListener('click', async () => {
  await removeConnection('/api/settings/connections/download-client');
});

async function removeConnection(url) {
  status.textContent = '';
  try {
    await requestJSON(url, {method: 'DELETE'});
    await Promise.all([loadConnections(), loadRuntime()]);
  } catch (error) {
    status.textContent = error.message;
  }
}

async function loadRuntime() {
  try {
    const health = await requestJSON('/health');
    const connected = health.indexer !== 'not-configured';
    const details = [
      `Metadata: ${health.metadata.join(', ')}`,
      connected ? `Releases: ${health.indexer} connected` : 'Releases: not configured',
      health.downloader !== 'not-configured' ? `Downloads: ${health.downloader} connected` : 'Downloads: not configured',
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
  movieReleaseSection.hidden = true;
  displayedMovie = null;
  try {
    const data = await requestJSON(`/api/search?q=${encodeURIComponent(query.value)}`);
    activeSearchFilter = 'all';
    renderResults(data.results);
    status.textContent = data.metadataIssues.length
      ? data.metadataIssues.map(issue => issue.message).join(' ')
      : data.results.length ? '' : 'No matching titles found.';
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(searchButton, false, 'Search');
  }
});

function renderResults(items) {
  lastSearchResults = items;
  results.replaceChildren();
  searchSection.hidden = items.length === 0;
  for (const button of searchFilterButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.searchFilter === activeSearchFilter));
  }
  const visibleItems = items.filter(item =>
    activeSearchFilter === 'all'
      || (activeSearchFilter === 'tv' && item.kind === 'televisionSeries')
      || (activeSearchFilter === 'movies' && item.kind === 'movie')
  );
  searchEmpty.hidden = visibleItems.length !== 0;
  searchEmpty.textContent = activeSearchFilter === 'tv'
    ? 'No TV matches.'
    : activeSearchFilter === 'movies' ? 'No movie matches.' : '';
  for (const item of visibleItems) {
    const media = item.media;
    const isTelevision = item.kind === 'televisionSeries';
    const card = document.createElement('article');
    card.className = 'series';

    const image = document.createElement('img');
    image.className = 'poster';
    image.alt = '';
    if (media.imageURL) image.src = media.imageURL;

    const copy = document.createElement('div');
    copy.className = 'series-copy';
    const heading = document.createElement('div');
    heading.className = 'media-heading';
    const title = document.createElement('h3');
    title.textContent = media.title;
    const kind = document.createElement('span');
    kind.className = 'media-kind';
    kind.textContent = isTelevision ? 'Show' : 'Movie';
    heading.append(title, kind);
    const meta = document.createElement('p');
    meta.className = 'meta';
    meta.textContent = isTelevision
      ? [media.premieredYear, media.network, media.status].filter(Boolean).join(' · ')
      : [media.releaseYear].filter(Boolean).join(' · ');
    copy.append(heading, meta);
    const actions = document.createElement('div');
    actions.className = 'series-actions';
    const isTracked = isTelevision
      ? trackedSeries.has(seriesKey(media))
      : trackedMovies.has(providerKey(media.id));
    if (isTelevision) {
      const select = document.createElement('button');
      select.className = 'secondary';
      select.textContent = 'Show seasons';
      select.addEventListener('click', () => loadSeries(media, select));
      actions.append(select);
    } else if (isTracked) {
      const matches = document.createElement('button');
      matches.className = 'secondary';
      matches.textContent = 'Find releases';
      matches.addEventListener('click', () => openMovieReleases(media, matches));
      actions.append(matches);
    }
    const track = document.createElement('button');
    track.textContent = isTracked ? 'Remove' : 'Add';
    if (isTracked) track.className = 'secondary';
    track.addEventListener('click', () => isTelevision
      ? toggleTrackedSeries(media, track)
      : toggleTrackedMovie(media, track)
    );
    actions.append(track);
    copy.append(actions);
    card.append(image, copy);
    results.append(card);
  }
}

async function loadTrackedMedia() {
  try {
    const [seriesData, movieData] = await Promise.all([
      requestJSON('/api/tv/tracked'),
      requestJSON('/api/movies/tracked')
    ]);
    trackedSeries.clear();
    trackedMovies.clear();
    for (const item of seriesData.results) trackedSeries.set(seriesKey(item.series), item);
    for (const item of movieData.results) trackedMovies.set(providerKey(item.movie.id), item);
    renderTrackedMedia();
  } catch (error) {
    status.textContent = error.message;
  }
}

function renderTrackedMedia() {
  trackedResults.replaceChildren();
  const items = [
    ...[...trackedSeries.values()].map(item => ({kind: 'televisionSeries', item})),
    ...[...trackedMovies.values()].map(item => ({kind: 'movie', item}))
  ];
  trackedEmpty.hidden = items.length !== 0;
  for (const tracked of items) {
    const isTelevision = tracked.kind === 'televisionSeries';
    const item = tracked.item;
    const media = isTelevision ? item.series : item.movie;
    const card = document.createElement('article');
    card.className = 'series';
    const image = document.createElement('img');
    image.className = 'poster';
    image.alt = '';
    if (media.imageURL) image.src = media.imageURL;
    const copy = document.createElement('div');
    copy.className = 'series-copy';
    const heading = document.createElement('div');
    heading.className = 'media-heading';
    const title = document.createElement('h3');
    title.textContent = media.title;
    const kind = document.createElement('span');
    kind.className = 'media-kind';
    kind.textContent = isTelevision ? 'Show' : 'Movie';
    heading.append(title, kind);
    const meta = document.createElement('p');
    meta.className = 'meta';
    meta.textContent = isTelevision
      ? [media.premieredYear, media.network].filter(Boolean).join(' · ')
      : [media.releaseYear].filter(Boolean).join(' · ');
    const state = document.createElement('p');
    state.className = 'airing-status';
    if (isTelevision) {
      const hasEnded = media.status?.toLowerCase() === 'ended';
      if (hasEnded) state.classList.add('ended');
      state.textContent = hasEnded
        ? 'Ended'
        : `Next airing · ${item.nextAirDate ? formatAirDate(item.nextAirDate) : 'TBA'}`;
    } else if (item.onDisk) {
      state.textContent = 'On disk';
    } else {
      const downloadState = movieDownloadState(media);
      const upcoming = isFutureDate(media.releaseDate);
      if (downloadState) {
        if (downloadState === 'blocked') state.classList.add('missing');
        state.textContent = downloadStateLabel(downloadState);
      } else {
        if (!upcoming) state.classList.add('missing');
        state.textContent = upcoming
          ? `Releases · ${formatAirDate(media.releaseDate)}`
          : 'Missing';
      }
    }
    const actions = document.createElement('div');
    actions.className = 'series-actions';
    if (isTelevision) {
      const select = document.createElement('button');
      select.className = 'secondary';
      select.textContent = 'Show seasons';
      select.addEventListener('click', () => loadSeries(media, select));
      actions.append(select);
    } else {
      const matches = document.createElement('button');
      matches.className = 'secondary';
      matches.textContent = 'Find releases';
      matches.addEventListener('click', () => openMovieReleases(media, matches));
      actions.append(matches);
    }
    const remove = document.createElement('button');
    remove.className = 'secondary';
    remove.textContent = 'Remove';
    remove.addEventListener('click', () => isTelevision
      ? toggleTrackedSeries(media, remove)
      : toggleTrackedMovie(media, remove)
    );
    actions.append(remove);
    copy.append(heading, meta, state, actions);
    card.append(image, copy);
    trackedResults.append(card);
  }
}

async function toggleTrackedSeries(series, button) {
  const key = seriesKey(series);
  const isTracked = trackedSeries.has(key);
  setBusy(button, true, isTracked ? 'Removing…' : 'Adding…');
  status.textContent = '';
  try {
    if (isTracked) {
      await requestJSON(
        `/api/tv/tracked/${encodeURIComponent(series.id.provider)}/${encodeURIComponent(series.id.value)}`,
        {method: 'DELETE'}
      );
      trackedSeries.delete(key);
      if (displayedSeriesKey === key) {
        lineupSection.hidden = true;
        displayedSeriesKey = null;
      }
    } else {
      await requestJSON('/api/tv/tracked', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({series})
      });
      await loadTrackedMedia();
    }
    renderTrackedMedia();
    renderResults(lastSearchResults);
  } catch (error) {
    status.textContent = error.message;
    setBusy(button, false, isTracked ? 'Remove' : 'Add');
  }
}

async function toggleTrackedMovie(movie, button) {
  const key = providerKey(movie.id);
  const isTracked = trackedMovies.has(key);
  setBusy(button, true, isTracked ? 'Removing…' : 'Adding…');
  status.textContent = '';
  try {
    if (isTracked) {
      await requestJSON(
        `/api/movies/tracked/${encodeURIComponent(movie.id.provider)}/${encodeURIComponent(movie.id.value)}`,
        {method: 'DELETE'}
      );
      trackedMovies.delete(key);
      if (displayedMovie && providerKey(displayedMovie.id) === key) {
        displayedMovie = null;
        movieReleaseSection.hidden = true;
      }
    } else {
      const tracked = await requestJSON('/api/movies/tracked', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({movie})
      });
      trackedMovies.set(key, tracked);
    }
    renderTrackedMedia();
    renderResults(lastSearchResults);
  } catch (error) {
    status.textContent = error.message;
    setBusy(button, false, isTracked ? 'Remove' : 'Add');
  }
}

function trackedMovieURL(movie) {
  return `/api/movies/tracked/${encodeURIComponent(movie.id.provider)}/${encodeURIComponent(movie.id.value)}`;
}

async function openMovieReleases(movie, button) {
  displayedMovie = movie;
  lineupSection.hidden = true;
  selectedMovieTitle.textContent = `${movie.title} matches`;
  const tracked = trackedMovies.get(providerKey(movie.id));
  movieResolution.value = tracked?.downloadSettings?.preferredResolution || '1080p';
  movieCodec.value = tracked?.downloadSettings?.preferredVideoCodec || 'HEVC';
  movieReleaseSection.hidden = false;
  setBusy(button, true, 'Searching…');
  status.textContent = '';
  try {
    await loadMovieReleases(movie);
    movieReleaseSection.scrollIntoView({behavior: 'smooth', block: 'start'});
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Find releases');
  }
}

async function loadMovieReleases(movie) {
  const data = await requestJSON(`${trackedMovieURL(movie)}/releases`);
  movieReleaseResults.replaceChildren();
  movieReleaseSummary.textContent = data.results.length
    ? `${data.results.length} results, with preferred matches first.`
    : 'No releases were reported for this movie.';
  for (const candidate of data.results) {
    movieReleaseResults.append(renderCandidate(candidate, null, [], movie));
  }
}

async function saveMoviePreferences() {
  if (!displayedMovie) return;
  movieResolution.disabled = true;
  movieCodec.disabled = true;
  status.textContent = '';
  try {
    const settings = await requestJSON(`${trackedMovieURL(displayedMovie)}/download-settings`, {
      method: 'PUT',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({
        preferredResolution: movieResolution.value,
        preferredVideoCodec: movieCodec.value
      })
    });
    const tracked = trackedMovies.get(providerKey(displayedMovie.id));
    if (tracked) tracked.downloadSettings = settings;
    await loadMovieReleases(displayedMovie);
  } catch (error) {
    status.textContent = error.message;
  } finally {
    movieResolution.disabled = false;
    movieCodec.disabled = false;
  }
}

movieResolution.addEventListener('change', saveMoviePreferences);
movieCodec.addEventListener('change', saveMoviePreferences);

function seriesKey(series) {
    return `${series.id.provider}:${series.id.value}`;
}

function formatAirDate(value) {
  const [year, month, day] = value.split('-').map(Number);
  return new Intl.DateTimeFormat(undefined, {dateStyle: 'medium'}).format(
    new Date(year, month - 1, day)
  );
}

function isFutureDate(value) {
  if (!value) return false;
  const [year, month, day] = value.split('-').map(Number);
  if (!year || !month || !day) return false;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return new Date(year, month - 1, day) > today;
}

async function loadSeries(series, button) {
  setBusy(button, true, 'Loading…');
  status.textContent = '';
  movieReleaseSection.hidden = true;
  displayedMovie = null;
  try {
    const canChoose = trackedSeries.has(seriesKey(series));
    const [data, lineup] = await Promise.all([
      requestJSON(`/api/tv/series/${encodeURIComponent(series.id.value)}/seasons`),
      canChoose ? requestJSON(lineupURL(series)) : Promise.resolve({episodeIDs: []})
    ]);
    setLineup(lineup);
    onDiskEpisodeKeys = new Set((data.onDiskEpisodeIDs || []).map(providerKey));
    renderSeasons(series, data.seasons, canChoose);
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Show seasons');
  }
}

function renderSeasons(series, items, canChoose) {
  displayedSeasons.splice(0, displayedSeasons.length, ...items);
  displayedSeriesKey = seriesKey(series);
  selectedTitle.textContent = `${series.title} lineup`;
  lineupDescription.textContent = canChoose
    ? 'Episode monitoring supplies the default. Individual checkboxes are the final lineup.'
    : 'Add this show to choose the episodes you want.';
  seasons.replaceChildren();
  if (canChoose) seasons.append(renderDownloadSettings(series));
  for (const season of items) {
    const section = document.createElement('section');
    section.className = 'season';
    section.dataset.seasonNumber = String(season.number);
    const header = document.createElement('div');
    header.className = 'season-header';
    const heading = document.createElement('h3');
    heading.textContent = `Season ${season.number} · ${season.episodes.length} episodes`;
    let seasonCheckbox;
    let headerTitle = heading;
    if (canChoose) {
      const choice = document.createElement('label');
      choice.className = 'season-choice';
      seasonCheckbox = document.createElement('input');
      seasonCheckbox.type = 'checkbox';
      seasonCheckbox.dataset.seasonChoice = '';
      seasonCheckbox.setAttribute('aria-label', `Choose all of season ${season.number}`);
      choice.append(seasonCheckbox, heading);
      headerTitle = choice;
    }
    const findReleases = document.createElement('button');
    findReleases.className = 'secondary';
    findReleases.textContent = 'Find releases';
    const sendSelected = document.createElement('button');
    sendSelected.type = 'button';
    sendSelected.dataset.bulkSend = '';
    sendSelected.hidden = true;
    const releaseResults = document.createElement('div');
    releaseResults.className = 'release-results';
    releaseResults.hidden = true;
    findReleases.addEventListener('click', () =>
      loadReleases(series, season, section, findReleases, releaseResults, sendSelected)
    );
    const actions = document.createElement('div');
    actions.className = 'season-actions';
    actions.append(sendSelected, findReleases);
    header.append(headerTitle, actions);
    section.append(header, releaseResults);
    for (const episode of season.episodes) {
      const row = document.createElement('div');
      row.className = 'episode';
      row.dataset.downloadEpisodeKey = providerKey(episode.id);
      if (canChoose) {
        row.classList.add('selectable');
        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.dataset.episodeKey = providerKey(episode.id);
        checkbox.setAttribute('aria-label', `Choose ${episode.title}`);
        checkbox.addEventListener('change', () =>
          setEpisodeDesired(series, season, section, episode, checkbox)
        );
        row.append(checkbox);
      }
      const code = document.createElement('span');
      code.className = 'episode-code';
      code.textContent = episode.episodeNumber == null
        ? `S${pad(episode.seasonNumber)} special`
        : `S${pad(episode.seasonNumber)}E${pad(episode.episodeNumber)}`;
      const title = document.createElement('span');
      title.className = 'episode-title';
      title.textContent = episode.title;
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = [episode.airDate, episode.runtimeMinutes && `${episode.runtimeMinutes} min`].filter(Boolean).join(' · ');
      const episodeReleases = document.createElement('div');
      episodeReleases.className = 'episode-releases';
      episodeReleases.dataset.releaseEpisodeNumber = episode.episodeNumber == null ? '' : String(episode.episodeNumber);
      episodeReleases.hidden = true;
      row.append(code, title, meta);
      if (episode.episodeNumber != null) {
        const searchEpisode = document.createElement('button');
        searchEpisode.type = 'button';
        searchEpisode.className = 'secondary episode-search';
        searchEpisode.textContent = 'Search';
        searchEpisode.setAttribute('aria-label', `Find releases for ${episode.title}`);
        searchEpisode.addEventListener('click', () =>
          loadEpisodeReleases(series, season, section, episode, searchEpisode, releaseResults)
        );
        row.append(searchEpisode);
      }
      section.append(row);
      section.append(episodeReleases);
    }
    if (canChoose) {
      seasonCheckbox.addEventListener('change', () =>
        setSeasonDesired(series, season, section, seasonCheckbox)
      );
      applyLineupState(section, season);
    }
    seasons.append(section);
  }
  applyEpisodeDownloadStates([...downloadSubmissions.values()]);
  lineupSection.hidden = false;
  lineupSection.scrollIntoView({behavior: 'smooth', block: 'start'});
}

function renderDownloadSettings(series) {
  const tracked = trackedSeries.get(seriesKey(series));
  const panel = document.createElement('div');
  panel.className = 'download-settings';
  const copy = document.createElement('div');
  copy.className = 'download-settings-copy';
  const choice = document.createElement('label');
  choice.className = 'download-settings-choice';
  const checkbox = document.createElement('input');
  checkbox.type = 'checkbox';
  const preferences = document.createElement('div');
  preferences.className = 'download-preferences';
  const resolution = preferenceSelect('Resolution', [
    ['any', 'Any'], ['2160p', '2160p'], ['1080p', '1080p'], ['720p', '720p'], ['480p', '480p']
  ]);
  const codec = preferenceSelect('Video codec', [
    ['any', 'Any'], ['HEVC', 'HEVC'], ['AVC', 'AVC'], ['AV1', 'AV1'], ['MPEG-2', 'MPEG-2']
  ]);
  const monitoring = preferenceSelect('Episodes', [
    ['future', 'Future'], ['all', 'All'], ['none', 'None']
  ]);
  preferences.append(monitoring.field, resolution.field, codec.field);
  const label = document.createElement('span');
  label.textContent = 'Use season folders';
  choice.append(checkbox, label);
  const note = document.createElement('span');
  note.className = 'field-note';
  const updateNote = () => {
    note.textContent = checkbox.checked
      ? `Each download goes into ${series.title}'s matching season folder.`
      : `Downloads are placed directly in ${series.title}.`;
  };
  const applySettings = settings => {
    checkbox.checked = settings?.seasonFolders !== false;
    resolution.select.value = settings?.preferredResolution || '1080p';
    codec.select.value = settings?.preferredVideoCodec || 'HEVC';
    monitoring.select.value = episodeMonitoring;
    updateNote();
  };
  applySettings(tracked?.downloadSettings);
  const saveSettings = async () => {
    const controls = [checkbox, resolution.select, codec.select];
    for (const control of controls) control.disabled = true;
    status.textContent = '';
    updateNote();
    try {
      const settings = await requestJSON(`${trackedSeriesURL(series)}/download-settings`, {
        method: 'PUT',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({
          seasonFolders: checkbox.checked,
          preferredResolution: resolution.select.value,
          preferredVideoCodec: codec.select.value
        })
      });
      const item = trackedSeries.get(seriesKey(series));
      if (item) item.downloadSettings = settings;
    } catch (error) {
      applySettings(trackedSeries.get(seriesKey(series))?.downloadSettings);
      status.textContent = error.message;
    } finally {
      for (const control of controls) control.disabled = false;
    }
  };
  checkbox.addEventListener('change', saveSettings);
  resolution.select.addEventListener('change', saveSettings);
  codec.select.addEventListener('change', saveSettings);
  monitoring.select.addEventListener('change', async () => {
    monitoring.select.disabled = true;
    status.textContent = '';
    try {
      await updateLineup(series, {monitoring: monitoring.select.value});
      applyAllLineupStates();
      applyEpisodeDownloadStates([...downloadSubmissions.values()]);
    } catch (error) {
      monitoring.select.value = episodeMonitoring;
      status.textContent = error.message;
    } finally {
      monitoring.select.disabled = false;
    }
  });
  copy.append(choice, note);
  panel.append(copy, preferences);
  return panel;
}

function preferenceSelect(labelText, options) {
  const field = document.createElement('label');
  field.className = 'field';
  field.append(labelText);
  const select = document.createElement('select');
  for (const [value, label] of options) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    select.append(option);
  }
  field.append(select);
  return {field, select};
}

async function setSeasonDesired(series, season, section, checkbox) {
  const desired = checkbox.checked;
  hideBulkSend(section);
  const episodeInputs = [...section.querySelectorAll('[data-episode-key]')];
  checkbox.disabled = true;
  for (const input of episodeInputs) input.disabled = true;
  status.textContent = '';
  try {
    await updateLineup(series, {
      seasonNumber: season.number,
      episodeIDs: season.episodes.map(episode => episode.id),
      included: desired
    });
  } catch (error) {
    status.textContent = error.message;
  } finally {
    checkbox.disabled = false;
    for (const input of episodeInputs) input.disabled = false;
    applyLineupState(section, season);
    applyEpisodeDownloadStates([...downloadSubmissions.values()]);
  }
}

async function setEpisodeDesired(series, season, section, episode, checkbox) {
  const desired = checkbox.checked;
  hideBulkSend(section);
  checkbox.disabled = true;
  status.textContent = '';
  try {
    await updateLineup(series, {
      seasonNumber: season.number,
      episodeID: episode.id,
      episodeIDs: season.episodes.map(item => item.id),
      included: desired
    });
  } catch (error) {
    status.textContent = error.message;
  } finally {
    checkbox.disabled = false;
    applyLineupState(section, season);
    applyEpisodeDownloadStates([...downloadSubmissions.values()]);
  }
}

async function updateLineup(series, change) {
  const data = await requestJSON(lineupURL(series), {
    method: 'PUT',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify(change)
  });
  setLineup(data);
}

function applyLineupState(section, season) {
  const episodeInputs = [...section.querySelectorAll('[data-episode-key]')];
  for (const input of episodeInputs) {
    const episode = season.episodes.find(item => providerKey(item.id) === input.dataset.episodeKey);
    input.checked = episode ? lineupIncludes(episode) : false;
  }
  const seasonCheckbox = section.querySelector('[data-season-choice]');
  const selectedCount = season.episodes.filter(lineupIncludes).length;
  seasonCheckbox.checked = season.episodes.length > 0 && selectedCount === season.episodes.length;
  seasonCheckbox.indeterminate = selectedCount > 0 && selectedCount < season.episodes.length;
}

function hideBulkSend(section) {
  const button = section.querySelector('[data-bulk-send]');
  if (button) button.hidden = true;
}

function setLineup(data) {
  episodeMonitoring = data.monitoring || 'all';
  futureCutoffDate = data.futureCutoffDate || null;
  excludedSeasons = new Set(data.excludedSeasons || []);
  excludedEpisodes = new Set((data.excludedEpisodes || []).map(providerKey));
  includedEpisodes = new Set((data.includedEpisodes || []).map(providerKey));
}

function lineupIncludes(episode) {
  const key = providerKey(episode.id);
  if (includedEpisodes.has(key)) return true;
  if (excludedSeasons.has(episode.seasonNumber) || excludedEpisodes.has(key)) return false;
  if (episodeMonitoring === 'all') return true;
  if (episodeMonitoring === 'none') return false;
  return Boolean(episode.airDate && futureCutoffDate && episode.airDate >= futureCutoffDate);
}

function applyAllLineupStates() {
  for (const season of displayedSeasons) {
    const section = seasons.querySelector(`[data-season-number="${season.number}"]`);
    if (section) applyLineupState(section, season);
  }
}

function lineupURL(series) {
  return `${trackedSeriesURL(series)}/lineup`;
}

function trackedSeriesURL(series) {
  return `/api/tv/tracked/${encodeURIComponent(series.id.provider)}/${encodeURIComponent(series.id.value)}`;
}

function providerKey(reference) {
  return `${reference.provider}:${reference.value}`;
}

async function loadReleases(series, season, section, button, container, sendSelected) {
  status.textContent = '';
  sendSelected.hidden = true;
  const checkedEpisodeKeys = new Set(
    [...section.querySelectorAll('[data-episode-key]:checked')]
      .map(input => input.dataset.episodeKey)
  );
  const selectedEpisodes = season.episodes.filter(episode =>
    checkedEpisodeKeys.has(providerKey(episode.id))
  );
  if (!selectedEpisodes.length) {
    renderReleaseMessage(container, section, 'Choose at least one episode before searching.');
    return;
  }
  const searchableEpisodes = selectedEpisodes.filter(episode => episode.episodeNumber != null);
  if (!searchableEpisodes.length) {
    renderReleaseMessage(container, section, 'The selected specials do not have searchable episode numbers.');
    return;
  }

  setBusy(button, true, 'Searching…');
  try {
    const {candidates, matchedEpisodes} = await searchEpisodeReleases(
      series,
      season,
      searchableEpisodes
    );
    renderReleases(
      candidates,
      matchedEpisodes,
      searchableEpisodes.length,
      selectedEpisodes.length - searchableEpisodes.length,
      container,
      series,
      season,
      section,
      sendSelected
    );
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Find releases');
  }
}

async function loadEpisodeReleases(series, season, section, episode, button, container) {
  status.textContent = '';
  setBusy(button, true, 'Searching…');
  try {
    const {candidates, matchedEpisodes} = await searchEpisodeReleases(
      series,
      season,
      [episode]
    );
    renderReleases(
      candidates,
      matchedEpisodes,
      1,
      0,
      container,
      series,
      season,
      section
    );
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Search');
  }
}

async function searchEpisodeReleases(series, season, episodes) {
  const searches = await Promise.all(episodes.map(async episode => {
    const parameters = new URLSearchParams({
      q: series.title,
      tvmazeID: series.id.value,
      season: String(season.number),
      episode: String(episode.episodeNumber)
    });
    return {
      episode,
      data: await requestJSON(`/api/tv/releases?${parameters}`)
    };
  }));
  const candidates = new Map();
  const matchedEpisodes = new Map();
  for (const search of searches) {
    for (const candidate of search.data.results) {
      const key = providerKey(candidate.id);
      candidates.set(key, candidate);
      if (!matchedEpisodes.has(key)) matchedEpisodes.set(key, new Set());
      matchedEpisodes.get(key).add(search.episode.episodeNumber);
    }
  }
  return {candidates: [...candidates.values()], matchedEpisodes};
}

function resetReleaseResults(container, section) {
  container.replaceChildren();
  for (const episodeContainer of section.querySelectorAll('[data-release-episode-number]')) {
    episodeContainer.replaceChildren();
    episodeContainer.hidden = true;
  }
}

function renderReleaseMessage(container, section, message) {
  resetReleaseResults(container, section);
  const summary = document.createElement('p');
  summary.className = 'release-summary';
  summary.textContent = message;
  container.append(summary);
  container.hidden = false;
}

function renderReleases(
  candidates,
  matchedEpisodes,
  searchedEpisodeCount,
  skippedSpecialCount,
  container,
  series,
  season,
  section,
  sendSelected = null
) {
  resetReleaseResults(container, section);
  const summary = document.createElement('p');
  summary.className = 'release-summary';
  const episodeLabel = `${searchedEpisodeCount} ${searchedEpisodeCount === 1 ? 'episode' : 'episodes'}`;
  summary.textContent = candidates.length
    ? `${candidates.length} unique results for ${episodeLabel}, with preferred matches first.`
    : `No releases were reported for ${episodeLabel}.`;
  if (skippedSpecialCount) summary.textContent += ` ${skippedSpecialCount} unnumbered special skipped.`;
  container.append(summary);

  const candidatesByEpisode = new Map();
  for (const candidate of candidates) {
    const episodeNumbers = matchedEpisodes.get(providerKey(candidate.id)) ?? new Set();
    const episodeIDs = season.episodes
      .filter(episode => episodeNumbers.has(episode.episodeNumber))
      .map(episode => episode.id);
    for (const episodeNumber of episodeNumbers) {
      if (!candidatesByEpisode.has(episodeNumber)) candidatesByEpisode.set(episodeNumber, []);
      candidatesByEpisode.get(episodeNumber).push({candidate, episodeIDs});
    }
    rememberDownloadContext(candidate, series, episodeIDs);
  }
  for (const [episodeNumber, matches] of candidatesByEpisode) {
    const target = section.querySelector(`[data-release-episode-number="${episodeNumber}"]`);
    if (!target || !matches.length) continue;
    renderCompactReleaseGroup(target, matches, series);
    target.hidden = false;
  }
  if (sendSelected) configureBulkSend(sendSelected, candidatesByEpisode, series);
  container.hidden = false;
}

function configureBulkSend(button, candidatesByEpisode, series) {
  const releases = new Map();
  for (const matches of candidatesByEpisode.values()) {
    const primary = matches[0];
    if (!primary) continue;
    const key = providerKey(primary.candidate.id);
    const current = releases.get(key) || {candidate: primary.candidate, episodeIDs: new Map()};
    for (const episodeID of primary.episodeIDs) current.episodeIDs.set(providerKey(episodeID), episodeID);
    releases.set(key, current);
  }
  const selected = [...releases.values()].map(release => ({
    candidate: release.candidate,
    episodeIDs: [...release.episodeIDs.values()]
  })).filter(release => {
    const submission = downloadSubmissions.get(providerKey(release.candidate.id));
    return !submission || submission.state === 'blocked';
  });
  const episodeCount = new Set(selected.flatMap(release =>
    release.episodeIDs.map(providerKey)
  )).size;
  button.hidden = selected.length === 0 || activeDownloadClientKind !== 'sabnzbd';
  button.disabled = false;
  button.textContent = `Send ${episodeCount} selected to SABnzbd`;
  button.onclick = () => sendSelectedToSABnzbd(selected, button, series);
}

function renderCompactReleaseGroup(container, matches, series) {
  const primary = matches[0];
  const primaryCandidate = renderCandidate(primary.candidate, series, primary.episodeIDs);
  const alternatives = matches.slice(1);
  if (alternatives.length) {
    let actions = primaryCandidate.querySelector('.candidate-actions');
    if (!actions) {
      actions = document.createElement('div');
      actions.className = 'candidate-actions';
      primaryCandidate.append(actions);
    }
    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'release-options-toggle';
    toggle.dataset.releaseOptionsToggle = '';
    toggle.setAttribute('aria-expanded', 'false');
    toggle.textContent = `${alternatives.length} ${alternatives.length === 1 ? 'alternative' : 'alternatives'}`;
    const options = document.createElement('div');
    options.className = 'release-options';
    options.dataset.releaseOptions = '';
    options.hidden = true;
    for (const alternative of alternatives) {
      options.append(renderCandidate(alternative.candidate, series, alternative.episodeIDs));
    }
    toggle.addEventListener('click', () => {
      const shouldOpen = options.hidden;
      for (const openOptions of document.querySelectorAll('[data-release-options]')) {
        openOptions.hidden = true;
      }
      for (const openToggle of document.querySelectorAll('[data-release-options-toggle]')) {
        openToggle.setAttribute('aria-expanded', 'false');
      }
      options.hidden = !shouldOpen;
      toggle.setAttribute('aria-expanded', String(shouldOpen));
    });
    actions.append(toggle);
    container.append(primaryCandidate, options);
  } else {
    container.append(primaryCandidate);
  }
}

function renderCandidate(candidate, series, episodeIDs, movie = null) {
  const item = document.createElement('article');
  item.className = 'candidate';
  const title = document.createElement('strong');
  title.className = 'candidate-title';
  title.textContent = candidate.title;
  const details = [
    candidate.coverage.length ? null : 'Coverage not reported',
    formatBytes(candidate.sizeBytes),
    formatDate(candidate.publishedAt)
  ].filter(Boolean);
  const meta = document.createElement('div');
  meta.className = 'candidate-meta';
  for (const [name, value] of Object.entries(candidate.reportedTraits)) {
    appendTraitPill(meta, name === 'videoCodec' ? 'codec' : name, value);
  }
  for (const coverage of candidate.coverage) {
    appendTraitPill(meta, 'coverage', formatCoverage(coverage), coverage.scope);
  }
  if (details.length) {
    const detail = document.createElement('span');
    detail.className = 'candidate-details';
    detail.textContent = details.join(' · ');
    meta.append(detail);
  }
  item.append(title, meta);
  if ((series || movie) && activeDownloadClientKind === 'sabnzbd') {
    const actions = document.createElement('div');
    actions.className = 'candidate-actions';
    const send = document.createElement('button');
    send.type = 'button';
    send.dataset.downloadKey = providerKey(candidate.id);
    applyDownloadButtonState(send, downloadSubmissions.get(send.dataset.downloadKey));
    send.addEventListener('click', () => movie
      ? sendMovieToSABnzbd(candidate, send, movie)
      : sendToSABnzbd(candidate, send, series, episodeIDs));
    actions.append(send);
    item.append(actions);
  }
  return item;
}

async function rememberDownloadContext(candidate, series, episodeIDs) {
  if (!episodeIDs.length) return;
  const key = providerKey(candidate.id);
  const existing = downloadSubmissions.get(key);
  if (!existing) return;
  const targets = existing.acquisitionContext?.targets || [];
  const known = new Set(
    targets
      .filter(target => target.media.kind === 'televisionEpisode')
      .map(target => providerKey(target.media.id))
  );
  const hasSeries = targets.some(target =>
    (target.ancestors || []).some(ancestor =>
      ancestor.kind === 'televisionSeries' && providerKey(ancestor.id) === providerKey(series.id)
    )
  );
  if (hasSeries && episodeIDs.every(id => known.has(providerKey(id)))) return;
  try {
    const submission = await requestJSON(
      `/api/downloads/${encodeURIComponent(candidate.id.provider)}/${encodeURIComponent(candidate.id.value)}/context`,
      {
        method: 'PUT',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({seriesID: series.id, episodeIDs})
      }
    );
    downloadSubmissions.set(key, submission);
    renderDownloads([...downloadSubmissions.values()]);
  } catch (error) {
    status.textContent = error.message;
  }
}

function applyDownloadButtonState(button, submission) {
  if (!submission) {
    button.textContent = 'Send to SABnzbd';
    button.disabled = false;
    return;
  }
  button.textContent = submission.state === 'blocked'
    ? 'Retry SABnzbd'
    : downloadStateLabel(submission.state);
  button.disabled = submission.state !== 'blocked';
}

async function sendToSABnzbd(candidate, button, series, episodeIDs) {
  const existing = downloadSubmissions.get(providerKey(candidate.id));
  const action = existing?.state === 'blocked' ? 'Retry' : 'Send';
  if (!window.confirm(`${action} “${candidate.title}” to SABnzbd now?`)) return;
  setBusy(button, true, 'Sending…');
  status.textContent = '';
  try {
    const submission = await submitToSABnzbd(candidate, series, episodeIDs);
    applyDownloadButtonState(button, submission);
    await loadDownloads();
  } catch (error) {
    status.textContent = error.message;
    await loadDownloads();
    applyDownloadButtonState(button, downloadSubmissions.get(providerKey(candidate.id)));
  }
}

async function sendSelectedToSABnzbd(releases, button, series) {
  const episodeCount = new Set(releases.flatMap(release =>
    release.episodeIDs.map(providerKey)
  )).size;
  if (!window.confirm(
    `Send ${releases.length} release${releases.length === 1 ? '' : 's'} for ${episodeCount} selected episode${episodeCount === 1 ? '' : 's'} to SABnzbd now?`
  )) return;
  setBusy(button, true, 'Sending…');
  status.textContent = '';
  const failures = [];
  for (const release of releases) {
    try {
      await submitToSABnzbd(release.candidate, series, release.episodeIDs);
    } catch (error) {
      failures.push(error.message);
    }
  }
  await loadDownloads();
  if (failures.length) {
    status.textContent = failures.length === releases.length
      ? failures[0]
      : `${releases.length - failures.length} sent to SABnzbd; ${failures.length} could not be sent.`;
  } else {
    status.textContent = `${releases.length} sent to SABnzbd.`;
  }
  button.hidden = true;
}

async function submitToSABnzbd(candidate, series, episodeIDs) {
  const data = await requestJSON('/api/downloads', {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({
      candidateID: candidate.id,
      seriesID: series.id,
      episodeIDs
    })
  });
  downloadSubmissions.set(providerKey(candidate.id), data.submission);
  await rememberDownloadContext(candidate, series, episodeIDs);
  return data.submission;
}

async function sendMovieToSABnzbd(candidate, button, movie) {
  const existing = downloadSubmissions.get(providerKey(candidate.id));
  const action = existing?.state === 'blocked' ? 'Retry' : 'Send';
  if (!window.confirm(`${action} “${candidate.title}” to SABnzbd now?`)) return;
  setBusy(button, true, 'Sending…');
  status.textContent = '';
  try {
    const data = await requestJSON(`${trackedMovieURL(movie)}/downloads`, {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({candidateID: candidate.id})
    });
    downloadSubmissions.set(providerKey(candidate.id), data.submission);
    applyDownloadButtonState(button, data.submission);
    await loadDownloads();
  } catch (error) {
    status.textContent = error.message;
    await loadDownloads();
    applyDownloadButtonState(button, downloadSubmissions.get(providerKey(candidate.id)));
  }
}

function appendTraitPill(container, kind, value, classValue = value) {
  if (!value) return;
  const pill = document.createElement('span');
  const kindClass = classToken(kind);
  const valueClass = classToken(classValue);
  pill.className = `trait-pill trait-${kindClass} trait-${kindClass}-${valueClass}`;
  pill.textContent = value;
  container.append(pill);
}

function classToken(value) {
  return String(value).replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function formatCoverage(coverage) {
  if (coverage.scope === 'televisionSeason') return `Season ${coverage.seasonNumber}`;
  return coverage.episodeNumbers.map(number =>
    `S${pad(coverage.seasonNumber)}E${pad(number)}`
  ).join(', ');
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

async function requestJSON(url, options) {
  const response = await fetch(url, options);
  if (response.status === 204) return null;
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
