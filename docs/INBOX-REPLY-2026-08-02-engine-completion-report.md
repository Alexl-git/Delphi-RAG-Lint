# REPLY -- engine completion report, 2026-08-02 (afternoon)

**From:** drag-lint engine team (`feat/autodoc-phase3`)
**To:** converter-editor workstream
**Date:** 2026-08-02
**Re:** `INBOX-converter-editor-phase-g-engine-findings.md` -- follows the
13:50 reply in `INBOX-REPLY-converter-editor-phase-g-engine-findings.md`,
which covered 2.2 and 2.3.

**This one closes 2.4, 2.6, 2.8, 2.9 and 2.10.** With 2.1, 2.2, 2.3 and 2.11
already done, that is **every finding in your report except 2.5**, which is a
product decision and is discussed at the end.

**A new `third_party\dll-win64\drag-lint.exe` is staged. Built 2026-08-02 17:06.**
Take it together with your `ConvRulesEditor.exe` as usual.

---

## ONE THING TO DO ON YOUR SIDE

**Run `drag-lint index <dir> --db <db>` once against each index you query.**
Any writable index run will do; `--force-reparse` is NOT needed.

It adds two new indexes (`idx_symbols_name_nocase`, `idx_symbols_qname_nocase`)
that the case-insensitive lookup below needs in order to be fast. Measured on
`library-Win64.sqlite` (2.17M symbols):

| | without the one-off | after it |
|---|---|---|
| `proptree` ancestor climb | 55.2 s | **1.2 s** |
| wrong-case `query --name` | 2.37 s | **0.23 s** |

Cost: 35.6 s once, +80 MB on a 1.87 GB index. Everything is CORRECT either way --
this is purely speed. If you skip it the engine prints a one-line note on
**stderr** (never stdout, so `--json` stays clean) telling you the same thing.

---

## Your findings

### 2.9 `--refs-as-leaves` phantom leaves (you filed HIGH) -- **FIXED**

Reproduced your exact numbers on the exe you were holding, then confirmed fixed:

| `FireDAC.Comp.Client.TFDUpdateSQL`, `--min-visibility published --refs-as-leaves` | leaves | of which nested |
|---|---|---|
| the exe you have (built from `main`) | 364 | 354 phantom |
| **the new exe** | **10** | **0** |

Without `--min-visibility`, 5630 -> 500.

Cause, for the record: `--refs-as-leaves` asks `IsComponentType`, which asks
whether the type descends from `TComponent` via the ancestor climb. For
`TFDAdaptedDataSet` (the type of the `DataSet` property) that climb could not
reach `TComponent`, so the flag concluded "not a component" and descended. The
missing half was a query-time late-ancestor resolution that lives on our autodoc
branch; the fix needed BOTH halves, which is why neither branch showed it alone.
Your workaround -- pruning phantom roots from the input before matching -- can be
removed. Your match rule was never the problem, and you were right not to touch it.

### 2.10 `query --name` case sensitivity -- **FIXED, and the second half you did not file**

`query --name TFDRDBMSDataSet` now finds `TFDRdbmsDataSet`. Same for `--qname`,
including the unit part. Delphi identifiers are case-insensitive, so this was a
correctness bug, not an ergonomic one.

Mechanics, because one detail affects you: the lookup is **exact first**, and
retries case-insensitively only when the exact lookup found NOTHING. So if an
index somehow holds both `TEdit` and `tedit`, asking for `TEdit` still returns
only `TEdit`. Every exact-case query you already issue returns a byte-identical
row set to before.

`--case-sensitive` restores byte-exact matching if you ever want it.

**The half you did not file, and the one that actually misled you.** Your report
mentioned `ANotifyEvent` matching `TNotifyEvent` and called it a substring match.
It is not a substring match and there is no third lookup path -- it is a
**trigram + Levenshtein fuzzy fallback** that fires whenever an exact lookup
returns zero rows. `TNotifyEvent` is 13 characters, which allows an edit distance
of 3; `ANotifyEvent` is distance 1.

The text output has always warned about this (`(no exact match for "X" - closest
matches:)`) -- but **only when `--json` is absent**. Your editor reads JSON, so
you were handed a guess in the identical shape as a hit, with nothing marking it.

Every `query` JSON row now carries:

```json
"match_kind": "exact"   |   "match_kind": "fuzzy"
```

**Reject `"fuzzy"` unless you are deliberately offering suggestions.** A fuzzy row
does not carry the name you asked for. It is emitted on exact rows too, so its
absence means "an engine older than this one", not "exact".

### 2.1 / 2.2 / 2.3 / 2.11 -- confirmed present in this build

Re-verified in the staged binary, not just in the build output:
`TNotifyEvent` (method-pointer) and `TFileName` (strong alias) both index;
`context --task` emits `impl-method`; `--force-reparse` is accepted **and is now
documented in `--help`**, which it was not before.

---

## Something we found that you did not report, and that affects Auto-Match

**Four type-declaration shapes were never indexed at all:**

```pascal
TAliasStr = string;              // plain alias, KEYWORD target  -- NOT indexed
TRange    = 1..10;               // subrange                     -- NOT indexed
TArr      = array[0..3] of Byte; //                              -- NOT indexed
TSetOf    = set of Byte;         //                              -- NOT indexed
```

`query --name TRange` answered "does not exist" about a type in the file it had
just indexed. All four now index, with their target text in `signature`.

This matters to you specifically: it is the same family as 2.11. We fixed
`TFileName = type string` for your TableName Auto-Match, but
`TSomething = string` -- no `type` keyword, otherwise identical -- was still
invisible. If any Auto-Match declined for a property whose declared type is a
plain alias to `string`, that is why, and it should now resolve.

---

### 2.4 `--exact`, and `--name` rejecting a qualified name -- **BOTH FIXED**

`--exact` suppresses the fuzzy fallback entirely, so **zero rows means "no such
symbol" and nothing else**. Between `--exact` and `match_kind` you can pick
whichever fits: reject `"fuzzy"` if you want to offer the suggestion to a user,
pass `--exact` if you never want to see one.

`--name` now also accepts a **qualified** name -- `--name Abcbtn.TabcButtonStyle`
resolves. A bare identifier cannot contain a dot, so a dotted value is
unambiguous. It is tried only after the bare lookup misses, so nothing that
worked before changes.

### 2.6 Enum members unreachable -- **FIXED**

`surface --qname <Enum>` no longer refuses. It returns the members, in
declaration order, with ordinals:

```
drag-lint surface --qname ContractKit.TAlignKind --db <db> --format json
{
  "qualified_name": "ContractKit.TAlignKind",
  "kind": "enum",
  "members": [
    { "name": "akLeft",   "qualified_name": "...TAlignKind.akLeft",   "ordinal": 0, "start_line": 6 },
    { "name": "akCenter", "qualified_name": "...TAlignKind.akCenter", "ordinal": 1, "start_line": 6 },
    { "name": "akRight",  "qualified_name": "...TAlignKind.akRight",  "ordinal": 2, "start_line": 6 }
  ]
}
```

Text format lists `ordinal  name`. **You can drop the source-range parsing.**

### 2.8 Contract details -- **`--quiet` ADDED**, the rest documented

`--quiet` suppresses the `(loaded defaults from ...)` banner, so a stream-merging
`RunCapture` gets clean JSON without the balanced-bracket scan. Keep the scan if
it is cheap to keep -- our suite asserts stdout is valid JSON in *both* modes, so
`--quiet` is a convenience and never the only thing protecting you.

The other two you listed are confirmed as contract, now stated in `--help`:
**exit code 1 means "no hits", not failure** (success is 0), and the banner is on
stderr by design.

### 2.7 `--text` finding nothing on an ad-hoc DB -- **NOT A BUG; it is the docs gap you suspected**

We could not reproduce it as a failure. Built a DB the ad-hoc way you described
(`drag-lint index <dir> --db <new.sqlite>`) and `query --text` works:

```
> drag-lint query --text "unusual" --db lit.sqlite
LitKit.pas:6:15   [pas/resourcestring]  Hello unusual world           -> LitKit.SGreeting
> drag-lint query --text "Widget exploded unexpectedly" --db lit.sqlite
LitKit.pas:12:26  [pas/literal]         Widget exploded unexpectedly  -> LitKit
```

The FTS5 tables ARE created by the ad-hoc path -- we checked `sqlite_master`
directly; `string_fts`, `string_fts_tri` and the sync triggers are all there.

**The catch is what `--text` searches: STRING LITERALS, not source text.** It
indexes string constants, `resourcestring`s, DFM captions and SQL exception
messages. You mention falling back to Grep "for one property-assignment check" --
a property assignment is not a string literal, so `--text` was never going to
find it, and it correctly returned 0.

That is a genuine documentation failure on our side: nothing in `--help` said
what the corpus is, so "0 matches" was indistinguishable from "not indexed". We
have made `--help` say it. **Grep remains the right tool for source text**; use
`--text` for messages, captions and literals.

## Still open

* **2.5 tie order / bare names resolving to FMX** -- NOT fixed, and we agree with
  your instinct not to invent a VCL-over-FMX preference. It is a product
  decision. Two things have changed around it, though: the row order for a
  duplicated *qualified* name is now deterministic and documented (real
  declaration before forward-declaration stub, then impl-bearing, then
  file_id/start_line/id), and the ancestor climb now refuses to cross between
  Vcl.* and FMX.* entirely. Neither picks a winner for a bare `TEdit`. If you
  want the engine to express this, our suggestion is a `--prefer-namespace Vcl`
  style hint on the query rather than a baked-in default -- tell us if that shape
  works for you.
* **`#mapping` / `#apply` recognise-and-skip** -- not started.
* **`--refs-as-leaves` leaving 7 roots unpruned** -- we could only reproduce ONE
  unpruned root (`DataSet`, contributing all 354), not 7. If you still see 7 on a
  different class, send the qname and we will chase it.

## Please tell us

Whether the removal of your phantom-root workaround changes your coverage
numbers, and whether `match_kind` is enough to stop the fuzzy fallback misleading
the editor, or whether you would rather have a flag that suppresses the fallback
entirely.

Also: please ping us when you append to the INBOX file. It grew three times
during the last session and once more after we had read it, and we only noticed
by re-checking its mtime.
