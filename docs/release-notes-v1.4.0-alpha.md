A performance and correctness release. **`lint-all` on a 566-file project goes
572 s -> 277 s across v1.3.0 and this release, with the report byte-identical at
every step.**

**No schema change.** `SCHEMA_VERSION` is 21 before and after.

> ### ONE-TIME COST: every index re-parses once on its first run under v1.4.0.
> The indexer fingerprint embeds the product version, so a release bump
> invalidates every stored parse whether or not extraction changed -- and this
> release did **not** change what the parser extracts. For the ~7,000-file
> library index that is a long walk. Two things make it survivable: **per-file
> resume** (an interrupted walk continues instead of restarting) and the new
> **whole-database announce** (a long pass now says so, instead of looking
> hung). The underlying design issue is filed as
> `docs/INBOX-extraction-fingerprint-uses-the-product-version.md`.

### Performance

* **`seealso` doc-source: 18.57 s -> 2.29 s.** Memoised on the PARENT symbol id,
  caching the filtered routine list rather than every child row. 913,357 sibling
  rows materialised -> 17,559.
* **`class-metrics`: 58.04 s -> 19.24 s.** `ResolveTypeCategory` was 40.99 s over
  266,715 calls with only 7,568 distinct `(name, file)` keys; memoised per call,
  local to the run because file ids are per-database.

### Correctness

* **`lint-all` output is now stable across a reindex.** `class-metrics` emitted
  in `TDictionary` order keyed by symbol id, so reindexing the same sources moved
  61 findings -- same count, same byte total, different file. Now sorted on
  source coordinates. This mattered because byte-identity of `lint-all` is the
  project's own verification gate, and it was silently valid only within one
  index state.
* **The two index entry points now agree about a database's fingerprint.**
  `index --all --only <Section>` recorded `plat=` while `index <dir> --db`
  recorded `plat=win64`, so alternating them re-parsed every file for no engine
  change -- and silently disabled per-file resume on the manifest path, which is
  the path the long library walk uses. Both now record the effective preprocess
  platform.

### Diagnostics

* **The call-target resolve announces WHOLE-DB and its REASON before it runs**,
  not after. A documented ~37-minute pass previously printed nothing until it
  finished, which is how a healthy run was once killed at 8 minutes and filed as
  a hang. The reason is recorded at the latch, so it names the actual condition.
* **`lint-all --profile` attribution** for the per-file scan (per check, with file
  counts), `class-metrics`, and the `seealso` block.

### Tooling

* `tools/perf/scoped-resolve-ab.ps1` -- A/B equivalence harness for the scoped
  call-target resolve. Baseline: scoped 46.7 s vs whole-database 195.5 s with
  identical `call_edges` digests.
* `tools/lsp-diag/bpl-inventory.ps1` -- design-time package inventory (registry +
  on-disk sizes), the headless half of the IDE RAM audit.

### Notes for maintainers

Two long-standing performance suspects were **measured and refuted**: the
quadratic `Findings := Findings + X` accumulation costs **0.00 s**, and the
`.scm` double parse is real but worth **1.38 s of 271 s**. Neither should be
revived. What remains is `.scm` rule execution at 54 s -- time individual rules
before changing anything.
