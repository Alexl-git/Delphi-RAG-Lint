---
id: explain
title: explain
summary: "Explains one lint rule in plain words: what it means, why it matters, a bad and a good example, its default, whether it can be fixed, and how to suppress it"
product: DL
group: linting
order: 30012
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# explain

Explains one lint rule in plain words: what it means, why it matters, a bad and a good example, its default, whether it can be fixed, and how to suppress it.

Read this when a finding names a rule id and you want to know what it is for before you fix it or suppress it: explain prints the meaning, the reason, an example, the default, fixability and the exact suppress line, as text or JSON.

## How to run it

```text
drag-lint explain <rule-id> [--json] [--rules-dir <dir>]   (what one lint rule means, why it matters, bad / good example, default, fixable, and how to suppress it; an unknown id lists the nearest ids and exits 2)
```

Full flag list: [explain in the CLI reference](../cli.md#explain).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

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

### Running it

```text
drag-lint explain <rule-id> [--json] [--rules-dir <dir>]
```

* Exit 0: the id is known. Exit 2: the id is unknown or missing. An unknown id
  prints the nearest ids (stderr; the `nearest` array in `--json`).
* `--json` prints one object: `id`, `category`, `source`, `meaning`, `why`,
  `example_bad`, `example_good`, `default_severity`, `default_enabled`, `fixable`,
  `fix_manual_only`, `wiki_page`, `params`, `suppress`.
* Needs no index and no `--db`.
* `drag-lint rules` lists every id.

### Multi-word concept search

`drag-lint query --concept "<words>" --db <file.sqlite>` now ranks partial
matches for a multi-word question. See the `query` page.

### Known limit

A rule that has neither sidecar examples nor a wiki row gets the generic
category sentence and no example. Adding `why`, `example_bad` and `example_good`
to a rule's sidecar json improves its answer without changing the engine.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
