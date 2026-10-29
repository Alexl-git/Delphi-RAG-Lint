---
id: concept-search
title: query --concept
summary: Ranked BM25 concept search over identifier words and doc-comment prose
product: DL
group: search-navigation
order: 20004
since: 1.38.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# query --concept

Ranked BM25 concept search over identifier words and doc-comment prose.

Read this when you know what the code does but not what it is called. It ranks symbols by how well their camelCase-split name and their doc-comment summary and remarks match your words, best first, with no re-parse needed to enable it.

## How to run it

```text
drag-lint query --concept "<words>" [--limit N] [--kind k,...] [--json] --db <db>
```

Example:

```text
drag-lint query --concept "apply row changes" --db <db>
```

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--concept` | `<words>` |  |  |
| `--limit` | `N` |  |  |
| `--kind` | `<k,...>` |  |  |
| `--json` |  |  |  |
| `--db` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Pitfalls

* approximate matched column: first 5 letters of a word stand in for porter stemming.
* no synonyms and no embeddings: remove does not find delete.
* exit 3 = this index has no concept-search table yet; run index once (backfills from existing rows, no re-parse).

## Details

`drag-lint query --concept "<words>" [--limit N] [--kind k,...] [--json] --db <db>`

Find code by MEANING when you do not know the name. Type a few words
("apply row changes", "delta pipe", "backpressure") and get a ranked list of
symbols whose identifier words or doc-comment prose match, best first.

### What it answers

* "Which routine streams row changes into a table?" when the routine is called
  `ApplyRowDelta` and its summary says "Streams pending row changes".
* "Where is the thing that deals with X?" for a word that appears only in a
  `<remarks>` block.
* A name you half remember: `ApplyRowDelta` finds `TDeltaPipe.ApplyRowDelta`
  because identifiers are split into words.

For an exact name use `query --name`; for an exact phrase in a doc comment or
string use `query --text` or `query find --doc-contains`.

### How ranking works

Every searchable symbol has one row in `symbol_search` with three columns,
searched by an SQLite FTS5 index (`symbol_search_fts`, tokenizer
`porter unicode61`):

| column | holds | BM25 weight |
|---|---|---|
| `tokens` | the symbol name split into words, the parent type's name split into words, and the lower-cased name | 3 |
| `summary` | the `<summary>` text (or, if the symbol has none, its `///` doc comment, markup stripped) | 2 |
| `remarks` | the `<remarks>` text, markup stripped | 1 |

Porter stemming means "changes" matches "change" and "streams" matches "stream".
camelCase and underscores split into words: `ApplyRowDelta` becomes
`apply row delta`, `TDeltaPipe` becomes `t delta pipe`, `Sql_Cache` becomes
`sql cache`. Stop words (a, an, the, of, how, what, ...) and one-letter words
in the query are ignored.

The query runs in two passes. Pass 1 requires EVERY word (AND). When it returns
fewer than `--limit` hits, pass 2 fills the rest with symbols that match ANY
word (OR), ranked below the pass 1 hits. The text header says how many hits
matched every word.

### Which symbols are included

Included: unit, class, interface, record, type, enum, method, function,
procedure, constructor, destructor, property, field, const, var, component,
form. Excluded on purpose (noise): param, local_var, enum_value,
initialization, finalization. `--kind class,method` narrows to the kinds you
name.

### Output

```text
concept "apply row changes": 4 hit(s) (1 match every word)
  1  12.34  method     Unit.TDeltaPipe.ApplyRowDelta   C:\...\DeltaPipe.pas:12   [tokens,summary]
```

`--json` gives `{"query","count","allTermsCount","hits":[{"rank","qname","kind",
"file","line","score","matched":[..],"allTerms"}]}`.

Exit codes: 0 = hits, 1 = no hits, 3 = this index has no concept-search table
yet (one stderr line says so; nothing crashes).

### Getting it on an existing index: backfill without a re-parse

`symbol_search` is a DERIVED table. The extractor does not write it; a separate
`search` stage runs after the `purity` stage of every index run and builds rows
for symbols that have none, from rows already in the database (symbols,
symbol_docs, doc-comment literals). So an index built by an older engine gets
concept search by running `drag-lint index` on it once: zero files are
re-parsed, the schema version and extractor version do not change. On an index that has not had
that run yet, `query --concept` exits 3 with the hint. Later incremental runs keep it current:
rows follow their symbol (a deleted or re-parsed symbol's row cascades away and
is rebuilt by the next stage run).

Doc prose is attributed by POSITION, not by `string_literals.symbol_id`: that
column names the ENCLOSING scope (unit or class), so grouping by it would pile
every member's comment onto its class. A run of consecutive `///` lines belongs
to the declaration on the first symbol line at most 2 lines below it (an
attribute line may sit between); `symbol_docs.summary` wins when present.

Cost (measured 2026-10-28 on a copy of drag-lint's own index, 49,834 symbols):
first backfill 15,720 rows in 8.4 s; an up-to-date run adds 0.1 s.

### Limits

* The `matched` column list is approximate. It reports a column when its text
  contains the first five letters of a query word, which stands in for porter
  stemming; it can name a column the ranker did not actually score on.
* No synonyms and no embeddings: "remove" does not find "delete". Only stemming
  and identifier splitting bridge wording.
* Needs an SQLite build with FTS5; without it the stage is a no-op and the query
  exits 3.
* Ranks symbols, not call paths. For a path question use the
  `drag-lint-reports` verbs.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
