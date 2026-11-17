# explain

Answers "what is this rule and what do I do about it?" for ONE lint rule id.

A finding names a rule (`bare-except`, `tls-verification-disabled`). `explain`
takes that id and prints, in this order:

| Section | Source |
|---|---|
| Rule | the id, its category and whether it is built in or a `.scm` rule |
| Meaning | the rule's sidecar message (`rules\<id>.json`), else the catalog title |
| Why it matters | the sidecar key `why`; else the row of the wiki table that lists the rule (`docs\wiki`, found by walking up from the rules folder); else one sentence per category |
| Bad / Good | the sidecar keys `example_bad` / `example_good`; a rule without them prints a one-line note instead |
| Default | ON or OFF, and the default severity |
| Fixable | whether `drag-lint fix` can repair it, and whether the fix is manual-only |
| Suppress | the `dl:ok` line marker, the `allow` verb, and `lint --disable` |

## Running it

```
drag-lint explain <rule-id> [--json] [--rules-dir <dir>]
```

* Exit 0: the id is known. Exit 2: the id is unknown or missing. An unknown id
  prints the nearest ids (stderr; the `nearest` array in `--json`).
* `--json` prints one object: `id`, `category`, `source`, `meaning`, `why`,
  `example_bad`, `example_good`, `default_severity`, `default_enabled`, `fixable`,
  `fix_manual_only`, `wiki_page`, `params`, `suppress`.
* Needs no index and no `--db`.
* `drag-lint rules` lists every id.

## Multi-word concept search

`drag-lint query --concept "<words>" --db <file.sqlite>` now ranks partial
matches for a multi-word question. See the `query` page.

## Known limit

A rule that has neither sidecar examples nor a wiki row gets the generic
category sentence and no example. Adding `why`, `example_bad` and `example_good`
to a rule's sidecar json improves its answer without changing the engine.
