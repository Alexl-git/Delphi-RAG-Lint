/* Refreshes the build-time release tags/dates in [data-repo] blocks from the GitHub API.
   Any failure leaves the static text alone. Cached per tab in sessionStorage. */
(function () {
  'use strict';

  function readCache(storage, repo) {
    try {
      var v = JSON.parse(storage.getItem('rel:' + repo));
      return v && typeof v.tag === 'string' && typeof v.date === 'string' ? v : null;
    } catch (e) { return null; }
  }

  function writeCache(storage, repo, rel) {
    try { storage.setItem('rel:' + repo, JSON.stringify(rel)); } catch (e) { /* ignored */ }
  }

  function apply(blocks, rel) {
    blocks.forEach(function (b) {
      b.querySelectorAll('.rel-tag').forEach(function (n) { n.textContent = rel.tag; });
      b.querySelectorAll('.rel-date').forEach(function (n) { n.textContent = rel.date; });
    });
  }

  function fetchLatest(fetchFn, repo) {
    return Promise.resolve()
      .then(function () { return fetchFn('https://api.github.com/repos/' + repo + '/releases/latest'); })
      .then(function (r) { return r.status === 200 ? r.json() : null; })
      .then(function (j) {
        return j && typeof j.tag_name === 'string' && typeof j.published_at === 'string'
          ? { tag: j.tag_name, date: j.published_at.slice(0, 10) } : null;
      })
      .catch(function () { return null; });
  }

  function refresh(doc, fetchFn, storage) {
    var byRepo = {};
    Array.prototype.forEach.call(doc.querySelectorAll('[data-repo]'), function (b) {
      var repo = b.getAttribute('data-repo');
      if (repo) (byRepo[repo] = byRepo[repo] || []).push(b);
    });
    return Promise.all(Object.keys(byRepo).map(function (repo) {
      var cached = readCache(storage, repo);
      if (cached) { apply(byRepo[repo], cached); return null; }
      return fetchLatest(fetchFn, repo).then(function (rel) {
        if (rel) { apply(byRepo[repo], rel); writeCache(storage, repo, rel); }
      });
    }));
  }

  if (typeof module !== 'undefined') module.exports = { refresh: refresh };

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function () {
      var storage = null;
      try { storage = window.sessionStorage; } catch (e) { /* blocked */ }
      if (!storage) storage = { getItem: function () { return null; }, setItem: function () {} };
      refresh(document, window.fetch.bind(window), storage);
    });
  }
})();
