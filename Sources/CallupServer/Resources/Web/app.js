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
const tmdbForm = document.querySelector('#tmdb-form');
const tmdbSecret = document.querySelector('#tmdb-secret');
const tmdbSave = document.querySelector('#tmdb-save');
const tmdbRemove = document.querySelector('#tmdb-remove');
const tmdbStatus = document.querySelector('#tmdb-status');
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
const backupIncludeConnections = document.querySelector('#backup-include-connections');
const backupExport = document.querySelector('#backup-export');
const backupFile = document.querySelector('#backup-file');
const backupRestore = document.querySelector('#backup-restore');
const backupStatus = document.querySelector('#backup-status');
const updateStatus = document.querySelector('#update-status');
const updateDetail = document.querySelector('#update-detail');
const updateCheck = document.querySelector('#update-check');
const updateInstall = document.querySelector('#update-install');
const updateNotes = document.querySelector('#update-notes');
const settingsTabButtons = document.querySelectorAll('[data-settings-tab]');
const settingsPanels = document.querySelectorAll('[data-settings-panel]');
const runtime = document.querySelector('#runtime');
const query = document.querySelector('#query');
const searchButton = document.querySelector('#search-button');
const status = document.querySelector('#status');
const buildBadge = document.querySelector('#build-badge');
const trackedEmpty = document.querySelector('#tracked-empty');
const trackedResults = document.querySelector('#tracked-results');
const trackedViewButtons = document.querySelectorAll('[data-tracked-view]');
const lineupFilterButtons = document.querySelectorAll('[data-lineup-filter]');
const lineupSort = document.querySelector('#lineup-sort');
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
const movieQualityInherit = document.querySelector('#movie-quality-inherit');
const movieReleaseSummary = document.querySelector('#movie-release-summary');
const movieReleaseResults = document.querySelector('#movie-release-results');
const qualityForms = document.querySelectorAll('[data-quality-default]');
const lineupSection = document.querySelector('#lineup-section');
const lineupPage = document.querySelector('#lineup-page');
const selectedTitle = document.querySelector('#selected-title');
const lineupDescription = document.querySelector('#lineup-description');
const seasons = document.querySelector('#seasons');
const trackedSeries = new Map();
const trackedMovies = new Map();
let lineupOrder = [];
let activeLineupFilter = 'all';
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
let availableUpdate = null;
let updatePoll = null;
let waitingForUpdate = false;
let updatePollAttempts = 0;
const downloadSubmissions = new Map();
let onDiskEpisodeKeys = new Set();
const onDiskEpisodeFiles = new Map();
let qualityDefaults = null;

setTrackedView(loadTrackedView());
renderRoute();
loadRuntime();
loadTrackedMedia();
loadConnections();
loadUpdates();
loadDownloads();
loadQuality();

lineupSort.addEventListener('change', () => {
  const url = new URL(window.location.href);
  url.searchParams.set('sort', lineupSort.value);
  history.replaceState({}, '', `${url.pathname}${url.search}`);
  loadTrackedMedia();
});

for (const button of trackedViewButtons) {
  button.addEventListener('click', () => setTrackedView(button.dataset.trackedView));
}

for (const button of lineupFilterButtons) {
  button.addEventListener('click', () => setLineupFilter(button.dataset.lineupFilter));
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

function setLineupFilter(filter, updateURL = true) {
  activeLineupFilter = ['movies', 'shows'].includes(filter) ? filter : 'all';
  for (const button of lineupFilterButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.lineupFilter === activeLineupFilter));
  }
  if (updateURL) {
    const url = new URL(window.location.href);
    if (activeLineupFilter === 'all') url.searchParams.delete('kind');
    else url.searchParams.set('kind', activeLineupFilter);
    history.replaceState({}, '', `${url.pathname}${url.search}`);
    lineupSection.hidden = true;
  }
  renderTrackedMedia();
}

for (const button of settingsTabButtons) {
  button.addEventListener('click', () => setSettingsTab(button.dataset.settingsTab));
}

function setSearchFilter(filter) {
  activeSearchFilter = ['tv', 'movies'].includes(filter) ? filter : 'all';
  for (const button of searchFilterButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.searchFilter === activeSearchFilter));
  }
  renderResults(lastSearchResults);
}

function setSettingsTab(tab) {
  const selectedTab = ['updates', 'data'].includes(tab) ? tab : 'configuration';
  for (const button of settingsTabButtons) {
    const selected = button.dataset.settingsTab === selectedTab;
    button.setAttribute('aria-selected', String(selected));
  }
  for (const panel of settingsPanels) {
    panel.hidden = panel.dataset.settingsPanel !== selectedTab;
  }
}

updateCheck.addEventListener('click', () => loadUpdates(true));
updateInstall.addEventListener('click', requestUpdate);

async function loadUpdates(refresh = false) {
  if (refresh) setBusy(updateCheck, true, 'Checking…');
  try {
    const data = await requestJSON(`/api/settings/update${refresh ? '?refresh=true' : ''}`);
    renderUpdateStatus(data);
  } catch (error) {
    updateStatus.textContent = 'Unavailable';
    updateStatus.className = 'update-status failed';
    updateDetail.textContent = error.message;
    if (waitingForUpdate) scheduleUpdatePoll();
  } finally {
    if (refresh) setBusy(updateCheck, false, 'Check again');
  }
}

function renderUpdateStatus(data) {
  availableUpdate = data.availableRelease || null;
  updateStatus.className = 'update-status';
  updateNotes.hidden = !availableUpdate;
  if (availableUpdate) updateNotes.href = availableUpdate.releaseURL;
  const active = ['requested', 'installing'].includes(data.progress?.state);
  waitingForUpdate = active;
  if (!active) updatePollAttempts = 0;
  updateInstall.hidden = !availableUpdate || !data.updaterReady || active;
  updateInstall.textContent = availableUpdate ? `Update to ${availableUpdate.version}` : 'Update now';

  if (active) {
    updateStatus.textContent = data.progress.state === 'installing' ? 'Installing…' : 'Queued…';
    updateDetail.textContent = data.progress.message;
    scheduleUpdatePoll();
  } else if (data.progress?.state === 'rolledBack' || data.progress?.state === 'failed') {
    updateStatus.textContent = data.progress.state === 'rolledBack' ? 'Rolled back' : 'Update failed';
    updateStatus.classList.add('failed');
    updateDetail.textContent = data.progress.message;
  } else if (availableUpdate) {
    updateStatus.textContent = 'Update available';
    updateStatus.classList.add('available');
    updateDetail.textContent = `${availableUpdate.name} is available. You are running ${data.currentVersion}.`;
  } else if (data.checkError) {
    updateStatus.textContent = 'Check unavailable';
    updateStatus.classList.add('failed');
    updateDetail.textContent = data.checkError;
  } else {
    updateStatus.textContent = 'Up to date';
    updateStatus.classList.add('succeeded');
    updateDetail.textContent = data.progress?.state === 'succeeded'
      ? data.progress.message
      : `You are running the newest release${data.currentVersion ? `, ${data.currentVersion}` : ''}.`;
  }

  if (!data.updaterReady && availableUpdate) {
    updateInstall.hidden = true;
    updateDetail.textContent += ' Install one current release through the existing system installer to enable in-app updates.';
  }
}

async function requestUpdate() {
  if (!availableUpdate) return;
  const version = availableUpdate.version;
  if (!window.confirm(`Update Callup to ${version}? The service will restart briefly.`)) return;
  waitingForUpdate = true;
  updatePollAttempts = 0;
  setBusy(updateInstall, true, 'Queueing…');
  try {
    const data = await requestJSON('/api/settings/update', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({version, confirm: true})
    });
    renderUpdateStatus(data);
  } catch (error) {
    updateStatus.textContent = 'Could not update';
    updateStatus.className = 'update-status failed';
    updateDetail.textContent = error.message;
    scheduleUpdatePoll();
  } finally {
    setBusy(updateInstall, false, `Update to ${version}`);
  }
}

function scheduleUpdatePoll() {
  if (updatePoll || !waitingForUpdate || updatePollAttempts >= 90) return;
  updatePollAttempts += 1;
  updatePoll = window.setTimeout(async () => {
    updatePoll = null;
    await loadUpdates();
    await loadRuntime();
  }, 2_000);
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
    : window.location.pathname === '/downloads' ? 'downloads'
    : window.location.pathname === '/quality' ? 'quality'
    : window.location.pathname === '/lineup' ? 'lineup' : 'home';
  const requestedSort = new URLSearchParams(window.location.search).get('sort');
  const requestedKind = new URLSearchParams(window.location.search).get('kind');
  lineupSort.value = ['title', 'nextAiring', 'lastDownloaded'].includes(requestedSort)
    ? requestedSort
    : 'nextAiring';
  setLineupFilter(requestedKind, false);
  for (const view of views) view.hidden = view.dataset.view !== route;
  for (const link of routeLinks) {
    if (link.closest('.topbar-actions')) {
      const selected = link.pathname === window.location.pathname;
      if (selected) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    }
  }
  document.title = route === 'home' ? 'Callup' : `${route[0].toUpperCase()}${route.slice(1)} · Callup`;
  status.textContent = '';
}

function qualitySummary(preference) {
  const resolution = preference.preferredResolution === 'any'
    ? 'any resolution'
    : preference.preferredResolution;
  const codec = preference.preferredVideoCodec === 'any'
    ? 'any video codec'
    : preference.preferredVideoCodec;
  return `Prefer ${resolution} and ${codec}.`;
}

function renderQualityDefaults() {
  if (!qualityDefaults) return;
  for (const form of qualityForms) {
    const preference = qualityDefaults[form.dataset.qualityDefault];
    form.querySelector('[data-quality-resolution]').value = preference.preferredResolution;
    form.querySelector('[data-quality-codec]').value = preference.preferredVideoCodec;
    form.querySelector('.quality-summary').textContent = qualitySummary(preference);
  }
}

async function loadQuality() {
  try {
    qualityDefaults = await requestJSON('/api/quality');
    renderQualityDefaults();
  } catch (error) {
    status.textContent = error.message;
  }
}

for (const form of qualityForms) {
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const button = form.querySelector('button[type="submit"]');
    const key = form.dataset.qualityDefault;
    setBusy(button, true, 'Saving…');
    status.textContent = '';
    try {
      qualityDefaults[key] = {
        preferredResolution: form.querySelector('[data-quality-resolution]').value,
        preferredVideoCodec: form.querySelector('[data-quality-codec]').value
      };
      qualityDefaults = await requestJSON('/api/quality', {
        method: 'PUT',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify(qualityDefaults)
      });
      renderQualityDefaults();
    } catch (error) {
      status.textContent = error.message;
      await loadQuality();
    } finally {
      setBusy(button, false, key === 'television' ? 'Save TV default' : 'Save movie default');
    }
  });
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
  const tmdb = (data.metadata || []).find(connection => connection.provider === 'tmdb');
  if (tmdb) {
    tmdbStatus.textContent = tmdb.source === 'saved' ? 'Connected' : 'Built in';
    tmdbStatus.classList.add('connected');
    tmdbRemove.hidden = tmdb.source !== 'saved';
  } else {
    tmdbStatus.textContent = 'Not connected';
    tmdbStatus.classList.remove('connected');
    tmdbRemove.hidden = true;
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
    renderDownloads(data.results, data.groups);
  } catch (error) {
    status.textContent = error.message;
  }
}

function renderDownloads(items, groups = null) {
  downloadResults.replaceChildren();
  downloadsEmpty.hidden = items.length !== 0;
  const activityGroups = groups?.length ? groups : [{title: 'Downloads', detail: null, results: items}];
  for (const group of activityGroups) {
    const section = document.createElement('details');
    section.className = 'download-group';
    const summary = document.createElement('summary');
    const heading = document.createElement('div');
    heading.className = 'download-group-heading';
    const title = document.createElement('strong');
    title.textContent = group.title;
    heading.append(title);
    if (group.detail) {
      const detail = document.createElement('span');
      detail.className = 'download-group-detail';
      detail.textContent = group.detail;
      heading.append(detail);
    }
    const count = document.createElement('span');
    count.className = 'download-group-count';
    count.textContent = `${group.results.length} download${group.results.length === 1 ? '' : 's'}`;
    summary.append(heading, count);
    const rows = document.createElement('div');
    rows.className = 'download-group-items';
    for (const submission of group.results) {
    const row = document.createElement('article');
    row.className = 'download-row';
    const releaseTitle = document.createElement('strong');
    releaseTitle.className = 'download-title';
    releaseTitle.textContent = submission.title;
    const state = document.createElement('span');
    state.className = `download-state download-state-${submission.state}`;
    state.textContent = downloadStateLabel(submission.state);
    row.append(releaseTitle, state);
    rows.append(row);
    }
    section.append(summary, rows);
    downloadResults.append(section);
  }
  for (const button of document.querySelectorAll('[data-download-key]')) {
    applyDownloadButtonState(button, downloadSubmissions.get(button.dataset.downloadKey));
  }
  applyEpisodeDownloadStates(items);
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
    row.querySelector('.episode-state').append(badge);
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
    row.querySelector('.episode-library-details')?.remove();
    if (!onDiskEpisodeKeys.has(row.dataset.downloadEpisodeKey)) continue;
    row.classList.add('has-download');
    const checkbox = row.querySelector('[data-episode-key]');
    if (checkbox) checkbox.checked = false;
    const files = onDiskEpisodeFiles.get(row.dataset.downloadEpisodeKey) || [];
    const traitContainer = row.querySelector('.episode-library-traits');
    traitContainer.replaceChildren();
    renderLibraryTraits(traitContainer, files);
    if (files.length) {
      const details = document.createElement('span');
      details.className = 'episode-library-details';
      details.textContent = `${row.querySelector('.meta').textContent ? ' · ' : ''}${libraryFileLabel(files)}`;
      details.title = files.map(file => file.relativePath).join('\n');
      row.querySelector('.meta').append(details);
    }
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

tmdbForm.addEventListener('submit', async event => {
  event.preventDefault();
  setBusy(tmdbSave, true, 'Testing…');
  status.textContent = '';
  try {
    const data = await requestJSON('/api/settings/connections/metadata/tmdb', {
      method: 'PUT',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({secret: tmdbSecret.value || null})
    });
    tmdbSecret.value = '';
    renderConnections(data);
    await loadRuntime();
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(tmdbSave, false, 'Connect TMDB');
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
tmdbRemove.addEventListener('click', async () => {
  await removeConnection('/api/settings/connections/metadata/tmdb');
});
downloadClientRemove.addEventListener('click', async () => {
  await removeConnection('/api/settings/connections/download-client');
});

backupFile.addEventListener('change', () => {
  backupRestore.disabled = backupFile.files.length === 0;
  backupStatus.textContent = backupFile.files.length
    ? `Ready to restore ${backupFile.files[0].name}.`
    : '';
});

backupExport.addEventListener('click', async () => {
  setBusy(backupExport, true, 'Exporting…');
  backupStatus.textContent = '';
  try {
    const includeConnections = backupIncludeConnections.checked ? 'true' : 'false';
    const response = await fetch(`/api/settings/backup?includeConnections=${includeConnections}`);
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.reason || 'Callup could not create the backup.');
    }
    const blobURL = URL.createObjectURL(await response.blob());
    const link = document.createElement('a');
    link.href = blobURL;
    link.download = `callup-backup-${new Date().toISOString().slice(0, 10)}.json`;
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(blobURL);
    backupStatus.textContent = backupIncludeConnections.checked
      ? 'Backup exported with saved connections.'
      : 'Backup exported without saved connections.';
  } catch (error) {
    backupStatus.textContent = error.message;
  } finally {
    setBusy(backupExport, false, 'Export backup');
  }
});

backupRestore.addEventListener('click', async () => {
  const file = backupFile.files[0];
  if (!file) return;
  backupStatus.textContent = '';
  let text;
  let backup;
  try {
    text = await file.text();
    backup = JSON.parse(text);
    if (backup.formatVersion !== 1 || !Array.isArray(backup.television)
        || !Array.isArray(backup.movies) || !Array.isArray(backup.downloads)) {
      throw new Error('That file is not a valid Callup backup.');
    }
  } catch (error) {
    backupStatus.textContent = error.message === 'That file is not a valid Callup backup.'
      ? error.message
      : 'That file is not valid JSON.';
    return;
  }

  const contents = [
    `${backup.television.length} shows`,
    `${backup.movies.length} movies`,
    `${backup.downloads.length} download records`
  ].join(', ');
  const connectionNote = backup.connections
    ? ' It will also replace saved connections and credentials.'
    : ' Saved connections on this instance will stay unchanged.';
  if (!window.confirm(
    `Replace this instance’s Lineup and download history with ${contents}?${connectionNote}`
  )) return;

  setBusy(backupRestore, true, 'Restoring…');
  try {
    const summary = await requestJSON('/api/settings/backup/restore?confirm=true', {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: text
    });
    backupFile.value = '';
    backupRestore.disabled = true;
    await Promise.all([loadTrackedMedia(), loadDownloads(), loadConnections(), loadRuntime()]);
    backupStatus.textContent = `Restored ${summary.televisionCount} shows, ${summary.movieCount} movies, and ${summary.downloadCount} download records.`;
  } catch (error) {
    backupStatus.textContent = error.message;
  } finally {
    if (backupFile.files.length) setBusy(backupRestore, false, 'Restore backup');
    else backupRestore.textContent = 'Restore backup';
  }
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
    const build = formatBuild(health.revision);
    buildBadge.textContent = build.label;
    buildBadge.title = build.title;
    const connected = health.indexer !== 'not-configured';
    const details = [
      `Metadata: ${health.metadata.join(', ')}`,
      connected ? `Releases: ${health.indexer} connected` : 'Releases: not configured',
      health.downloader !== 'not-configured' ? `Downloads: ${health.downloader} connected` : 'Downloads: not configured',
      health.database === 'sqlite' ? 'Store: SQLite' : null,
      health.revision && health.revision !== 'unknown' ? `Release: ${health.revision}` : null
    ].filter(Boolean);
    runtime.textContent = details.join(' · ');
  } catch {
    buildBadge.textContent = 'Build unavailable';
    buildBadge.title = 'Running build could not be determined';
    runtime.textContent = 'Provider status unavailable';
  }
}

function formatBuild(revision) {
  if (!revision || revision === 'unknown') {
    return {label: 'Build unknown', title: 'The running build did not report its release identity'};
  }
  const separator = revision.lastIndexOf('@');
  if (separator === -1) {
    return {label: revision, title: `Running build: ${revision}`};
  }
  const branch = revision.slice(0, separator);
  const commit = revision.slice(separator + 1).replace(/-dirty$/, ' dirty');
  return {
    label: `${branch} · ${commit}`,
    title: `Running build: ${revision}`
  };
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
    actions.append(qualityOverrideControl(
      isTelevision ? 'Show quality' : 'Movie quality',
      {kind: isTelevision ? 'televisionSeries' : 'movie', id: media.id},
      []
    ));
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
    const sort = lineupSort.value || 'nextAiring';
    const data = await requestJSON(`/api/lineup?sort=${encodeURIComponent(sort)}`);
    trackedSeries.clear();
    trackedMovies.clear();
    lineupOrder.splice(0, lineupOrder.length, ...data.order);
    for (const item of data.series) trackedSeries.set(seriesKey(item.series), item);
    for (const item of data.movies) trackedMovies.set(providerKey(item.movie.id), item);
    renderTrackedMedia(data.order);
  } catch (error) {
    status.textContent = error.message;
  }
}

function renderTrackedMedia(order = lineupOrder) {
  trackedResults.replaceChildren();
  const items = (order || []).map(entry => entry.kind === 'televisionSeries'
    ? {kind: entry.kind, item: trackedSeries.get(providerKey(entry.id))}
    : {kind: entry.kind, item: trackedMovies.get(providerKey(entry.id))}
  ).filter(entry => entry.item).filter(entry => activeLineupFilter === 'all'
    || (activeLineupFilter === 'shows' && entry.kind === 'televisionSeries')
    || (activeLineupFilter === 'movies' && entry.kind === 'movie'));
  trackedEmpty.textContent = activeLineupFilter === 'movies'
    ? 'No movies in your Lineup yet.'
    : activeLineupFilter === 'shows'
      ? 'No shows in your Lineup yet.'
      : 'Nothing in your Lineup yet.';
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
      state.textContent = libraryStateLabel(item.libraryFiles);
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
    const libraryFile = document.createElement('p');
    libraryFile.className = 'library-file';
    if (!isTelevision && item.libraryFiles?.length) {
      libraryFile.textContent = libraryFileLabel(item.libraryFiles);
      libraryFile.title = item.libraryFiles.map(file => file.relativePath).join('\n');
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
    const mediaState = document.createElement('div');
    mediaState.className = 'media-state';
    mediaState.append(state);
    if (libraryFile.textContent) mediaState.append(libraryFile);
    copy.append(heading, meta, mediaState);
    copy.append(actions);
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
  if (window.location.pathname === '/lineup') {
    await openInlineMovieReleases(movie, button);
    return;
  }
  displayedMovie = movie;
  lineupSection.hidden = true;
  selectedMovieTitle.textContent = `${movie.title} matches`;
  movieReleaseSection.hidden = false;
  setBusy(button, true, 'Searching…');
  status.textContent = '';
  try {
    const resolved = await resolveQuality({kind: 'movie', id: movie.id}, []);
    movieResolution.value = resolved.preference.preferredResolution;
    movieCodec.value = resolved.preference.preferredVideoCodec;
    movieQualityInherit.hidden = !resolved.source;
    await loadMovieReleases(movie);
    movieReleaseSection.scrollIntoView({behavior: 'smooth', block: 'start'});
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Find releases');
  }
}

async function openInlineMovieReleases(movie, button) {
  const card = button.closest('.series');
  if (!card) return;
  let panel = card.querySelector('.inline-movie-releases');
  if (!panel) {
    panel = document.createElement('div');
    panel.className = 'inline-movie-releases';
    const summary = document.createElement('p');
    summary.className = 'release-summary';
    const results = document.createElement('div');
    results.className = 'candidates';
    panel.append(summary, results);
    card.append(panel);
  }
  const summary = panel.querySelector('.release-summary');
  const results = panel.querySelector('.candidates');
  setBusy(button, true, 'Searching…');
  status.textContent = '';
  try {
    await loadMovieReleases(movie, summary, results);
  } catch (error) {
    panel.remove();
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Find releases');
  }
}

async function loadMovieReleases(movie, summary = movieReleaseSummary, results = movieReleaseResults) {
  const data = await requestJSON(`${trackedMovieURL(movie)}/releases`);
  results.replaceChildren();
  summary.textContent = data.results.length
    ? `${data.results.length} results, with preferred matches first.`
    : 'No releases were reported for this movie.';
  for (const candidate of data.results) {
    results.append(renderCandidate(candidate, null, [], movie));
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

movieQualityInherit.addEventListener('click', async () => {
  if (!displayedMovie) return;
  setBusy(movieQualityInherit, true, 'Restoring…');
  status.textContent = '';
  try {
    await setQualityOverride({kind: 'movie', id: displayedMovie.id}, null);
    const resolved = await resolveQuality({kind: 'movie', id: displayedMovie.id}, []);
    movieResolution.value = resolved.preference.preferredResolution;
    movieCodec.value = resolved.preference.preferredVideoCodec;
    movieQualityInherit.hidden = true;
    await loadMovieReleases(displayedMovie);
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(movieQualityInherit, false, 'Use movie default');
  }
});

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
  const inline = window.location.pathname === '/lineup';
  if (!inline) {
    navigate('/lineup');
    lineupPage.append(lineupSection);
    lineupSection.classList.remove('inline-series-seasons');
  }
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
    onDiskEpisodeFiles.clear();
    for (const match of data.onDiskEpisodes || []) {
      onDiskEpisodeFiles.set(providerKey(match.episodeID), match.libraryFiles || []);
    }
    renderSeasons(series, data.seasons, canChoose, !inline);
    if (inline) {
      const card = button.closest('.series');
      if (card) {
        lineupSection.classList.add('inline-series-seasons');
        card.append(lineupSection);
      }
    }
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setBusy(button, false, 'Show seasons');
  }
}

function renderSeasons(series, items, canChoose, scrollToPanel = true) {
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
    const seriesReference = {kind: 'televisionSeries', id: series.id};
    const seasonReference = {
      kind: 'televisionSeason', id: series.id, ordinal: season.number
    };
    actions.append(
      qualityOverrideControl('Season quality', seasonReference, [seriesReference]),
      sendSelected,
      findReleases
    );
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
      const titleText = document.createElement('span');
      titleText.className = 'episode-title-text';
      titleText.textContent = episode.title;
      title.append(titleText);
      title.append(qualityOverrideControl(
        'Episode quality',
        {kind: 'televisionEpisode', id: episode.id},
        [
          {kind: 'televisionSeason', id: series.id, ordinal: season.number},
          {kind: 'televisionSeries', id: series.id}
        ]
      ));
      const episodeState = document.createElement('span');
      episodeState.className = 'episode-state';
      const libraryTraits = document.createElement('div');
      libraryTraits.className = 'episode-library-traits';
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = [episode.airDate, episode.runtimeMinutes && `${episode.runtimeMinutes} min`].filter(Boolean).join(' · ');
      const episodeReleases = document.createElement('div');
      episodeReleases.className = 'episode-releases';
      episodeReleases.dataset.releaseEpisodeNumber = episode.episodeNumber == null ? '' : String(episode.episodeNumber);
      episodeReleases.hidden = true;
      row.append(code, title, episodeState, libraryTraits, meta);
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
  if (scrollToPanel) lineupSection.scrollIntoView({behavior: 'smooth', block: 'start'});
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
  const monitoring = preferenceSelect('Episodes', [
    ['future', 'Future'], ['all', 'All'], ['none', 'None']
  ]);
  preferences.append(monitoring.field);
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
    monitoring.select.value = episodeMonitoring;
    updateNote();
  };
  applySettings(tracked?.downloadSettings);
  const saveSettings = async () => {
    const controls = [checkbox];
    for (const control of controls) control.disabled = true;
    status.textContent = '';
    updateNote();
    try {
      const settings = await requestJSON(`${trackedSeriesURL(series)}/download-settings`, {
        method: 'PUT',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({
          seasonFolders: checkbox.checked,
          preferredResolution: tracked?.downloadSettings?.preferredResolution || '1080p',
          preferredVideoCodec: tracked?.downloadSettings?.preferredVideoCodec || 'HEVC'
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

function sameMediaReference(left, right) {
  return Boolean(left && right)
    && left.kind === right.kind
    && left.id.provider === right.id.provider
    && left.id.value === right.id.value
    && (left.ordinal ?? null) === (right.ordinal ?? null);
}

function qualitySourceLabel(source) {
  if (!source) return 'global default';
  if (source.kind === 'televisionSeries') return 'show';
  if (source.kind === 'televisionSeason') return 'season';
  if (source.kind === 'televisionEpisode') return 'episode';
  return 'title';
}

async function resolveQuality(target, ancestors) {
  return requestJSON('/api/quality/resolve', {
    method: 'POST',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({target, ancestors})
  });
}

async function setQualityOverride(media, preference) {
  await requestJSON('/api/quality/override', {
    method: 'PUT',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({media, preference})
  });
}

function qualityOverrideControl(label, media, ancestors) {
  const details = document.createElement('details');
  details.className = 'quality-override';
  const summary = document.createElement('summary');
  summary.textContent = label;
  const panel = document.createElement('div');
  panel.className = 'quality-override-panel';
  const note = document.createElement('span');
  note.className = 'field-note';
  note.textContent = 'Loading…';
  const fields = document.createElement('div');
  fields.className = 'quality-override-fields';
  const resolution = preferenceSelect('Resolution', [
    ['2160p', '2160p'], ['1080p', '1080p'], ['720p', '720p'], ['480p', '480p'], ['any', 'Any']
  ]);
  const codec = preferenceSelect('Video codec', [
    ['HEVC', 'HEVC'], ['AVC', 'AVC'], ['AV1', 'AV1'], ['MPEG-2', 'MPEG-2'], ['any', 'Any']
  ]);
  fields.append(resolution.field, codec.field);
  const actions = document.createElement('div');
  actions.className = 'quality-override-actions';
  const inherit = document.createElement('button');
  inherit.type = 'button';
  inherit.className = 'ghost';
  inherit.textContent = 'Use inherited';
  const save = document.createElement('button');
  save.type = 'button';
  save.textContent = 'Save override';
  actions.append(inherit, save);
  panel.append(note, fields, actions);
  details.append(summary, panel);
  let loaded = false;

  const load = async () => {
    const resolved = await resolveQuality(media, ancestors);
    resolution.select.value = resolved.preference.preferredResolution;
    codec.select.value = resolved.preference.preferredVideoCodec;
    const custom = sameMediaReference(resolved.source, media);
    summary.textContent = `${label} · ${custom ? 'custom' : 'inherited'}`;
    note.textContent = custom
      ? qualitySummary(resolved.preference)
      : `${qualitySummary(resolved.preference)} Inherited from ${qualitySourceLabel(resolved.source)}.`;
    inherit.hidden = !custom;
    loaded = true;
  };
  details.addEventListener('toggle', async () => {
    if (!details.open || loaded) return;
    try { await load(); } catch (error) { status.textContent = error.message; }
  });
  save.addEventListener('click', async () => {
    setBusy(save, true, 'Saving…');
    try {
      await setQualityOverride(media, {
        preferredResolution: resolution.select.value,
        preferredVideoCodec: codec.select.value
      });
      await load();
    } catch (error) {
      status.textContent = error.message;
    } finally {
      setBusy(save, false, 'Save override');
    }
  });
  inherit.addEventListener('click', async () => {
    setBusy(inherit, true, 'Restoring…');
    try {
      await setQualityOverride(media, null);
      await load();
    } catch (error) {
      status.textContent = error.message;
    } finally {
      setBusy(inherit, false, 'Use inherited');
    }
  });
  return details;
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
  const parameters = new URLSearchParams({
    q: series.title,
    tvmazeID: series.id.value,
    season: String(season.number)
  });
  if (episodes.length === 1 && episodes[0].episodeNumber != null) {
    parameters.set('episode', String(episodes[0].episodeNumber));
    parameters.set('episodeProvider', episodes[0].id.provider);
    parameters.set('episodeID', episodes[0].id.value);
  }
  const data = await requestJSON(`/api/tv/releases?${parameters}`);
  const selectedEpisodeNumbers = new Set(episodes.map(episode => episode.episodeNumber));
  const matchedEpisodes = new Map();
  for (const candidate of data.results) {
    const coveredEpisodes = new Set();
    for (const coverage of candidate.coverage) {
      if (coverage.seasonNumber !== season.number) continue;
      if (coverage.scope === 'televisionSeason') {
        for (const episodeNumber of selectedEpisodeNumbers) coveredEpisodes.add(episodeNumber);
      } else {
        for (const episodeNumber of coverage.episodeNumbers || []) {
          if (selectedEpisodeNumbers.has(episodeNumber)) coveredEpisodes.add(episodeNumber);
        }
      }
    }
    if (coveredEpisodes.size) matchedEpisodes.set(providerKey(candidate.id), coveredEpisodes);
  }
  return {
    candidates: data.results.filter(candidate => matchedEpisodes.has(providerKey(candidate.id))),
    matchedEpisodes
  };
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

function libraryStateLabel(files) {
  const file = files?.[0];
  if (!file) return 'On disk';
  const traits = file.inferredTraits || {};
  return [
    'On disk',
    traits.resolution,
    traits.videoCodec,
    traits.source,
    formatBytes(file.sizeBytes)
  ].filter(Boolean).join(' · ');
}

function renderLibraryTraits(container, files) {
  const file = files?.[0];
  if (!file) return;
  const traits = file.inferredTraits || {};
  appendTraitPill(container, 'availability', 'On disk');
  appendTraitPill(container, 'resolution', traits.resolution);
  appendTraitPill(container, 'codec', traits.videoCodec);
  appendTraitPill(container, 'source', traits.source);
  appendTraitPill(container, 'size', formatBytes(file.sizeBytes));
  container.title = files.map(file => file.relativePath).join('\n');
}

function libraryFileLabel(files) {
  if (!files?.length) return '';
  return files.length === 1 ? files[0].name : `${files[0].name} +${files.length - 1} more`;
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
