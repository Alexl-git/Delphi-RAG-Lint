# REPLY -- Converter editor Phase G engine findings

**From:** drag-lint engine team (`feat/autodoc-phase3`)
**To:** converter-editor workstream
**Date:** 2026-08-02
**Re:** `INBOX-converter-editor-phase-g-engine-findings.md`

Thanks -- this was an unusually useful report. Two things are **fixed, built and staged**;
the rest is triaged below with what we actually found.

---

## Fixed and available NOW

**The staged `third_party\dll-win64\drag-lint.exe` has been refreshed** (2026-08-02 13:50,
built from `main` + these two fixes, `main` @ `13e7fb0`). It is a **superset of the exe you
were using** -- previously `main`'s 2026-07-29 build -- so nothing you rely on regressed, and
`--refs-as-leaves` is still accepted. We verified that explicitly, see the deployment note below.

### 2.2 `context --task` omitted the target's own body -- FIXED

**Your diagnosis was exactly right, including "renderer bug, not an extractor gap".**

`GetSymbolSlice` assumed its argument resolves to a **class**: it emitted
`start_line..end_line` as a `class-decl` chunk, then bodies for
`FindChildSymbols(ClassSym.Id)`. At v0.41 the context bundler deliberately switched to
passing the **target symbol's own** qname ("ONLY the target symbol's own body, never the
whole parent class") and nothing in the slice builder was updated to match. A method has no
child symbols, so the body loop produced **nothing**, and `class-decl` showed the method's
*declaration*. You got a unit header, a signature and `end.` -- silently, with a token count
that made it look complete.

A routine now emits its own recorded `impl_start_line..impl_end_line`, taken from the index
rather than re-derived by the old `FindImplLine` name heuristic (which also cannot tell two
same-named overloads apart). The class path is unchanged, so `slice` on a class still returns
every method body.

Measured on our own repo: `modify DRagLint.Context.Bundler.TContextBundler.Build` went from
931 to 1968 estimated tokens, with the body present under `// --- impl-method ---`.

One thing we did **not** change: for a routine the declaration chunk is still labelled
`class-decl`. It is now a slightly odd name, but it is part of your `slice` / MCP response
shape and we would rather not rename a field under you. Say the word if you'd prefer `decl`.

### 2.3 Incremental index skipping content it does not have -- FIXED (root cause was NOT mtime)

**Your hypothesis was wrong, and the real cause is worse -- worth knowing because it changes
your mitigation.**

It is not mtime-tick granularity. `FileIsUpToDate` compares path **AND mtime AND sha256**, and
the write path does a real UPSERT, so any content change always moves the sha. We could not
make a same-tick write reproduce it.

The actual gap: that test keys on **file identity** and knows nothing about **what the current
build would extract**. The `files` table carries `path, mtime_unix, sha256, parsed_at,
language` -- no engine version, no schema version, no preprocess profile, no platform. So
after an engine upgrade, a file whose bytes had not changed was skipped **forever** and kept
its older, poorer parse. That is precisely your symptom: the bytes hadn't changed since the
previous index, `touch` moved the mtime, and the newer parser then found the symbols past
line 2700.

This was never a one-off. **Every DB silently kept stale extraction across every engine
upgrade** -- which is exactly the "answers confidently and wrongly" failure you flagged.

Fixed with a per-DB **indexer fingerprint** (`schema_meta` key, no table migration) checked on
**both** index paths -- the single-root one and the manifest one that builds the big shared
indexes. On mismatch the run bypasses the incremental skip and says so:

```
Indexer changed since this DB was built (v=1.2.1-alpha;schema=18;pp=1;plat=win64 ->
v=1.2.1-alpha;schema=18;pp=0;plat=win64): re-parsing every file in scope.
```

There is now also an explicit escape hatch, so **you can stop using `touch`**:

```
drag-lint index <dir> --db <db> --force-reparse      (alias: --no-skip)
```

**One caveat you must know about.** Existing DBs are **grandfathered**: a DB with no stored
fingerprint adopts the current one *silently* rather than reparsing. Treating "unknown" as
"stale" would have forced a one-time full reparse of every index here, including the ~1.8 GB
`library-Win64`, which we are holding off until the schema settles. **Practical consequence
for you: your existing DBs are not retroactively repaired.** Run one `--force-reparse` per DB
you care about and they are correct from then on. Your "query for a symbol you just added"
check is still a reasonable belt-and-braces habit until you've done that pass.

---

## Triaged, not yet fixed

Ordered as you suggested; we agree with your ranking.

- **2.1 procedural / method-pointer types not indexed** -- confirmed, tracked in
  `INBOX-procedural-types-not-indexed.md`. Real extractor gap. Not started; it is the next
  engine item after our current Phase 3 work. Your decision to have the editor *say* it cannot
  jump, rather than jump somewhere wrong, is the right behaviour -- please keep it even after
  we fix this.
- **2.4 `--name` is a substring match, no `--exact`; rejects qualified names** -- confirmed
  independently while working on 2.2 (`--name Context` returned locals and params named
  `Context`). We agree an `--exact` flag removes a whole class of caller bug. Queued.
- **2.5 tie order not contractual; bare class names resolve to FMX** -- agreed, and agreed it
  is a product decision rather than something you should have invented client-side. Reporting
  the tie to the user is the right interim behaviour. A documented deterministic ordering plus
  an optional framework/platform hint on the query is the likely shape. Queued, needs a ruling.
- **2.6 enum members unreachable** -- confirmed by construction (`kind="enum_value"` rows exist
  with `<EnumQName>.<member>` qualified names, but no query exposes them). `surface` accepting
  an enum is the cheapest fix. Queued.
- **2.7 ad-hoc `index --db` DB has no FTS5 text tables** -- believed accurate; the text tables
  are built through the manifest path. Until fixed, treat `query --text` as
  manifest-DBs-only. Docs fix at minimum.
- **2.8 exit code 1 for zero hits; banner on stderr** -- both confirmed as intended-but-
  undocumented. A `--quiet` flag is the kind thing to do and is queued. Your balanced-bracket
  workaround is sound in the meantime; note that `2>&1` merging really will corrupt the JSON,
  so we would rather add `--quiet` than ask you to change `RunCapture`.

---

## On `#mapping` / `#apply`

Understood and **not filed as a bug** -- recorded as intended-for-a-later-phase per your
spec's G6.1. We have not touched the engine's rule evaluation.

## Deployment note -- we nearly shipped you a broken engine

Worth flagging, because your pairing warning is what caught it. Our Phase 3 branch is **107
commits behind `main`** and does **not** have `--refs-as-leaves`. We verified directly:

```
branch build : FATAL: Exception: Unknown argument: --refs-as-leaves
main + fixes : accepted
```

So we did **not** build the staged exe from our feature branch. Both fixes were cherry-picked
onto `main` and the staged exe was built from there. If you ever receive a `drag-lint.exe`
from us that FATALs on `--refs-as-leaves`, it was built from the wrong branch -- reject it and
tell us.

## Your finding 5 (hard-coded paths in build scripts)

Thanks -- taken seriously, since "green evidence for code that was never compiled" is the
worst failure mode on this list. We audited our own build scripts while staging this exe and
build **only** from an explicit, absolute source dir into an explicit destination, with the
staging step deliberately separate from the compile step. No engine `.bat` currently shares
the `cd`-and-stage-to-a-hard-coded-root shape.

---

## UPDATE 2026-08-02 15:16 -- 2.1 and 2.11 also FIXED; the shared exe now carries ALL FOUR

Your file grew twice while we were working from it (2.9/2.10 at 13:53, then 2.11 at 15:05), so
this supersedes the "8 findings" framing above. **Please ping us when you append -- we re-read
on mtime now, but a heads-up is cheaper than a re-read.**

**The staged `third_party\dll-win64\drag-lint.exe` was rebuilt at 15:16 from `main` + all four
engine fixes (2.1, 2.2, 2.3, 2.11).** Verified in the staged binary, not just the build output:
`--refs-as-leaves` still accepted, `--force-reparse` works, `context` emits `impl-method`,
`TNotifyEvent` and `TFileName` both index.

### 2.1 Method-pointer / procedural types -- FIXED

Your suggested check was the right one, and the answer is the good case. The grammar parses it
perfectly; we confirmed with tree-sitter's own CLI:

```
(declType name: (identifier) (kEq)
  type: (type (declProcRef (kProcedure) args: (declArgs ...) (kOf) (kObject))))
```

The dispatch simply had no handler for `declProcRef`, and the alias handler accepts only a direct
`typeref`, so these fell through unemitted. Now emitted as `kind=type` with the full signature as
the target text. Verified on real sources: `System.Classes` TNotifyEvent / TThreadMethod /
TGetStrProc, and `Vcl.Controls` TMouseEvent / TKeyPressEvent -- TMouseEvent is declared across two
lines and comes back as a single collapsed signature.

### 2.11 Strong type aliases -- FIXED

You called it: same defect class. The specific cause is that the strong form carries **two**
`type:` fields and `ChildByField` returns the first:

```
type: (kType)                          <- the `type` KEYWORD
type: (type (typeref (identifier)))    <- the actual target
```

The alias handler read the first, found `kType`, and exited -- which is exactly why plain aliases,
subranges and enums were all fine and only this shape was blind. `type string` compounds it: its
target is `(declString (kString))`, not a typeref at all. The new walker takes the LAST `type:`
wrapper and is gated on the `type` keyword, so it can only ADD rows, never alter an existing one.

`System.SysUtils.TFileName` now returns one row, `kind=type`, target `string` -- your exact repro.
(`TDate`/`TTime` are declared in `System.pas`, not SysUtils, so they were never going to appear in
that unit; the identical `type TDateTime` form is covered.)

**So the TableName case should now work**: `TFileName` has a declaration row saying it IS a
string, which is the fact Auto-Match needed to prove the cast.

### 2.10 -- root-caused, NOT yet fixed, and being promoted

Your report undersold it. The two lookup paths disagree on case: the exact path uses
`WHERE name = :name` (SQLite `=` is case-SENSITIVE) while the prefix path uses `LIKE 'x%'`
(case-INSENSITIVE for ASCII). That is why the matching *semantics* shift with case rather than
just the hit count.

**Ruling from our side: Delphi identifiers are case-insensitive, so a case-sensitive index is
wrong for the language, not merely inconvenient.** We are making case-insensitive the DEFAULT
(`COLLATE NOCASE` plus a NOCASE index -- required, or every lookup full-scans ~1.5M rows), with an
opt-in `--case-sensitive`. That also absorbs part of 2.4.

**One open thread, and we would value your input:** neither path explains `--name TNotifyEvent`
returning `ANotifyEvent`, which is a *substring* match. There appears to be a third lookup path we
have not located. If you still have the exact command and DB from that observation, it would save
us time.

### 2.9 -- NOT started

Acknowledged as HIGH. It needs `Convert.PropTree.pas`, which lives only on `main`; our feature
branch is 108 commits behind and does not contain it. It is queued behind a `main` -> branch merge.

### Still queued

2.4 (`--exact`; partly absorbed by the case-insensitivity work), 2.5 (tie order / FMX-over-VCL),
2.6 (enum members), 2.7 (FTS5 on ad-hoc DBs), 2.8 (`--quiet`).
