// Unit tests for assets/releases.js -- run: node --test WWW/tests/releases.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { refresh } = require('../assets/releases.js');

const REPO = 'owner/drag-lint';

function fakeNode() { return { textContent: '' }; }

// A minimal document: one [data-repo] block per entry, each with one .rel-tag / .rel-date.
function fakeDoc(repos) {
  const blocks = repos.map(function (repo) {
    const tag = fakeNode(); tag.textContent = 'v0-static';
    const date = fakeNode(); date.textContent = '2000-01-01';
    return {
      tag: tag, date: date,
      getAttribute: function (n) { return n === 'data-repo' ? repo : null; },
      querySelectorAll: function (sel) {
        if (sel === '.rel-tag') return [tag];
        if (sel === '.rel-date') return [date];
        return [];
      }
    };
  });
  return {
    blocks: blocks,
    querySelectorAll: function (sel) { return sel === '[data-repo]' ? blocks : []; }
  };
}

function memStorage() {
  const m = {};
  return {
    data: m,
    getItem: function (k) { return Object.prototype.hasOwnProperty.call(m, k) ? m[k] : null; },
    setItem: function (k, v) { m[k] = String(v); }
  };
}

function respond(status, body) {
  const calls = [];
  const fn = function (url) {
    calls.push(url);
    return Promise.resolve({ status: status, ok: status === 200, json: function () { return Promise.resolve(body); } });
  };
  fn.calls = calls;
  return fn;
}

test('updates tag and date on 200', async function () {
  const doc = fakeDoc([REPO, REPO]);
  const st = memStorage();
  const f = respond(200, { tag_name: 'v1.31.5-alpha', published_at: '2026-10-18T09:00:00Z' });
  await refresh(doc, f, st);
  assert.deepStrictEqual(f.calls, ['https://api.github.com/repos/' + REPO + '/releases/latest']);
  for (const b of doc.blocks) {
    assert.strictEqual(b.tag.textContent, 'v1.31.5-alpha');
    assert.strictEqual(b.date.textContent, '2026-10-18');
  }
  assert.deepStrictEqual(JSON.parse(st.data['rel:' + REPO]), { tag: 'v1.31.5-alpha', date: '2026-10-18' });
});

test('keeps static text on failure', async function () {
  const failing = [
    function () { return Promise.reject(new Error('offline')); },
    respond(403, { message: 'API rate limit exceeded' }),
    respond(200, { published_at: '2026-10-18T09:00:00Z' })
  ];
  for (const f of failing) {
    const doc = fakeDoc([REPO]);
    const st = memStorage();
    await refresh(doc, f, st);
    assert.strictEqual(doc.blocks[0].tag.textContent, 'v0-static');
    assert.strictEqual(doc.blocks[0].date.textContent, '2000-01-01');
    assert.strictEqual(st.data['rel:' + REPO], undefined);
  }
});

test('uses cache without fetching', async function () {
  const doc = fakeDoc([REPO]);
  const st = memStorage();
  st.setItem('rel:' + REPO, JSON.stringify({ tag: 'v9-cached', date: '2026-10-01' }));
  const f = respond(200, { tag_name: 'v-net', published_at: '2026-10-18T09:00:00Z' });
  await refresh(doc, f, st);
  assert.strictEqual(f.calls.length, 0);
  assert.strictEqual(doc.blocks[0].tag.textContent, 'v9-cached');
  assert.strictEqual(doc.blocks[0].date.textContent, '2026-10-01');
});

test('storage that throws is ignored', async function () {
  const doc = fakeDoc([REPO]);
  const st = {
    getItem: function () { throw new Error('SecurityError'); },
    setItem: function () { throw new Error('SecurityError'); }
  };
  const f = respond(200, { tag_name: 'v1.31.5-alpha', published_at: '2026-10-18T09:00:00Z' });
  await refresh(doc, f, st);
  assert.strictEqual(f.calls.length, 1);
  assert.strictEqual(doc.blocks[0].tag.textContent, 'v1.31.5-alpha');
});
