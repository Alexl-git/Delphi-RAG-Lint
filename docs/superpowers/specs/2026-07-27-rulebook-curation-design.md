# Rule-book and Catalog Curation (spec E)

- Date: 2026-07-27
- Branch: `feat/converter-editor` (worktree `C:\Projects\Delphi-RAG-lint-converter`)
- Status: DRAFT -- awaiting user approval
- Precedes: spec A+B+C (compatibility tiers / target ranking / enum maps).

## 1. Problem

A single component pair already fills a rule-book. `docs/examples/convrules/sample.rules`
holds three `#convert` blocks in 230 lines, of which `TabcToggleBtn -> tcxButton`
alone contributes about 210 `#link` lines. Real books will be far larger --
BDE to FireDAC, ABC to DevExpress, Orpheus to DevExpress -- and several will be in
play for one conversion at once, because they depend on each other.

There is today no way to move a block between files, drop a block, fold one book
into another, or use more than one book for a single conversion.

The same pressure applies to the cast catalog. `casts.castlib` is a singleton by
decision (section 3) and is about to grow enum-map blocks from spec C.

## 2. Scope

In scope:

- A modal curation form, opened on request, otherwise not shown.
- A WORKING SET: several rule-book files loaded together, since one conversion may
  need several interdependent books.
- A selectable grid of block headers across the working set, with a file column.
- Operations on the selected blocks: split out, copy out, delete.
- Merging another file's blocks into a loaded one, including reFind-format files.
- Composing the working set into a single file for the engine (section 7).
- Both file kinds: `.rules` (DSL) and `.castlib` (catalog).

Out of scope for this spec:

- Compatibility tiers, alias resolution, target ranking, enum-map authoring
  (spec A+B+C, next).
- DSL merge/split of property VALUES -- combining `HintUp` + `HintDown` into one
  `Hint`, or splitting a multi-frame glyph strip into N images. That is a DSL
  grammar change owned by the engine team; see section 9.
- Any change to the drag-lint SQLite schema. This spec touches no database.

## 3. Architecture decision: catalog separate from DSL

The catalog (`casts.castlib`) records what CAN bridge what: class casts, and from
spec C, enum member maps. It is keyed by type pair and states no preference.

The DSL (`.rules`) records what WAS CHOSEN for one conversion: this `F1` goes to
`T1` here. Because the two are separate, `F1 -> T1` in one project and `F1 -> T2`
in another both draw on the same catalog without duplicating it.

The catalog stays a singleton file for now. The format is line-oriented, so
splitting it later is mechanical if read time ever becomes a problem.

## 4. Load-bearing principle: verbatim slices

A file is parsed into an ordered list of blocks, each holding its raw text. Every
operation moves raw text. Nothing is re-emitted from a parsed model.

This is forced, not preferred:

- `sample.rules` lines 10-11 assert that `//` and `;` hand comments survive
  round-trip. Round-trip fidelity is an existing guarantee of the format.
- `ConvRules.CastLib.LoadCastLibText` deliberately tolerates unknown keys so newer
  files stay readable by older builds. Re-emitting from the parsed model would
  silently delete every key the current build does not understand.

Constraint to observe: the existing save path in `ConvRules.MainForm` re-emits
canonical DSL (see its unit header comment). Curation writes MUST NOT route through
that re-emitter, or a block that was merely moved would come back reformatted.

## 5. Components

Following the pure-core / thin-VCL split already used by `ConvRules.Casts` and
`ConvRules.CastLib`, so the logic is unit-testable headlessly.

### 5.1 `ConvRules.BlockFile.pas` (pure)

Splits file text into blocks and rejoins them.

```
TRuleBlockKind = (rbkPreamble, rbkConvert, rbkCast, rbkEnum);

TRuleBlock = record
  Kind      : TRuleBlockKind;
  Header    : string;   // the header line, verbatim
  RawText   : string;   // the whole block including its header, verbatim
  StartLine : Integer;
  EndLine   : Integer;
end;
```

Grammars:

- `.rules` -- a block starts at a line whose first token is `#convert` and runs to
  the line before the next `#convert`, or to end of file. Any content before the
  first `#convert` is a single `rbkPreamble` block.
- `.castlib` -- a block starts at a line whose first token is `cast` or `enum` and
  runs through its matching `end`. Content before the first block, and between
  blocks, attaches to the preceding block so nothing is orphaned.

### 5.2 `ConvRules.BlockOps.pas` (pure)

`SplitOut`, `CopyOut`, `DeleteBlocks`, `MergeFrom`, `Compose`. All take and return
block lists plus text; none touch the file system, so all are directly testable.

`MergeFrom` and `Compose` report conflicts rather than resolving them. Resolution is
a UI decision; the logic stays deterministic and testable.

### 5.3 `ConvRules.WorkingSet.pas` (pure)

An ordered list of loaded files with their block lists. Order is the composition
precedence (section 7). Knows nothing about VCL.

### 5.4 `ConvRules.CurationForm.pas` (VCL)

Modal. Grid of block headers across the working set with a file column and checkbox
multi-select; toolbar (Split..., Copy..., Delete, Merge from..., Compose...);
conflict resolution dialog. Opened from a menu command on the main form; not
present otherwise.

## 6. Merge semantics

Blocks are matched by header. An incoming block whose header has no counterpart in
the target is appended verbatim.

When two blocks share a header, their `#link` directives are merged. The DSL writes
`#link To <- From`, so the TARGET is the left-hand side, and a target may be
assigned only once:

| Incoming link | Target state | Result |
| --- | --- | --- |
| `T.A <- F.A` | `T.A <- F.A` already present | skip (duplicate) |
| `T.A <- F.B` | `T.A <- F.A` already present | CONFLICT -- ask which to keep |
| `T.B <- F.A` | `T.A <- F.A` already present | merge (fan-out is legal) |
| `T.C <- F.C` | target not linked | merge (missing) |

One source feeding several targets is legitimate fan-out and is never a conflict.
Two sources feeding one target is always a conflict, because the generated
assignment would be ambiguous.

This same target-collision test is reusable outside merge: `convert-scaffold` can
itself emit colliding targets, so the curation form can surface them in a file that
was never merged.

## 7. Working set and composition

`convert-apply` and `convert-validate` accept exactly ONE rules file --
`DRagLint.CLI.pas:721` assigns `--rules` to a single string, unlike `--db` which
repeats. Using several books at once therefore needs either an engine change or
editor-side composition.

This spec chooses composition, so no engine change is required and the work does
not have to wait on the engine team:

- The working set is an ordered list of rule-book files.
- `Compose` folds the set into one file, top to bottom, using exactly the section 6
  merge semantics. Composition and merge share one code path.
- The composed file is what gets passed to `--rules`. It is a normal `.rules`
  file -- readable, diffable, and hand-editable if something is wrong. The Compose
  command prompts for its path, defaulting to `<first-file>.composed.rules`
  beside the first file in the set.
- Earlier files in the set win. A later file whose link collides with an earlier
  one is reported, not silently dropped.

Composing three large books must not mean answering hundreds of prompts, so
composition auto-resolves by precedence and produces a report listing every
collision it resolved, plus every block it appended. Interactive per-conflict
resolution stays available on the explicit `Merge from...` command, where the
user has chosen to fold one file into another deliberately.

reFind rule files may be used as merge or working-set input: the DSL is documented
as a reFind superset (see the `convert-validate` usage line), so a reFind file is
simply another parseable source.

## 8. Backup and error handling

Writes reuse the existing rotation in `ConvRules.MainForm.BackupPath`:
`<file>.bak`, then `.bak.2`, `.bak.3`, and so on. Nothing is overwritten.

A failed backup aborts the operation and leaves every file untouched. A write that
fails after a successful backup leaves the backup in place and reports its path.

## 9. Dependencies and coordination

This spec requires no engine change and no schema change, so it can proceed while
the engine team continues on `feat/autodoc-phase3`.

Standing rule adopted for this workstream: the converter persists everything in
text files it owns (`.rules`, `.castlib`). It never changes the drag-lint SQLite
schema. Anything needed FROM the index is requested as an additive, read-only
engine feature through a `docs/INBOX-*.md` note.

Outstanding INBOX items, none blocking this spec:

- `--refs-as-leaves` cherry-pick (`f65fb9c`), still absent. Proptree recursion is
  what fills `sample.rules` with junk such as
  `#link Action.Owner.Observers.OnCanObserve <- Action.Owner.Observers.OnCanObserve`.
- Enum-map consumption in `convert-apply` (needed by spec C, not by this one).
- Repeatable `--rules`. Composition makes this optional rather than blocking, but
  native multi-book support would remove the composed intermediate file.
- DSL merge/split grammar. Motivating real case: ABC5's `TNumGlyphs = 1..4` means
  `Glyph` is a multi-frame strip in one bitmap, so ABC to cx glyph transfer is
  inherently a split, not a copy.

## 10. Acceptance criteria (EARS)

Each becomes exactly one failing test in `ConvRulesModelTests.dpr`.

1. THE block splitter SHALL reproduce the original file byte-for-byte when its
   blocks are rejoined in order.
2. THE curation writer SHALL preserve `//` and `;` hand comments, blank lines, and
   unrecognised directives inside any moved block.
3. WHEN blocks are split out THE editor SHALL remove them from the source file and
   write them to the target file in their original relative order.
4. WHEN blocks are copied out THE editor SHALL write them to the target file and
   leave the source file unchanged.
5. WHEN a merge meets an incoming `#link` whose target path is already linked from
   the same source THE merger SHALL skip it.
6. WHEN a merge meets an incoming `#link` whose target path is already linked from
   a different source THE merger SHALL report a conflict AND SHALL NOT write either
   link until it is resolved.
7. IF an incoming `#link` maps an already-used source path to a new target path
   THEN the merger SHALL treat it as missing and merge it.
8. WHEN an incoming block header has no counterpart in the target THE merger SHALL
   append the whole block verbatim.
9. WHEN a working set is composed THE composer SHALL resolve link collisions in
   favour of the earlier file AND SHALL list every resolved collision in its report.
10. THE composed output SHALL be a valid `.rules` file that `convert-validate`
    accepts.
11. THE curation writer SHALL write a rotating backup before modifying any file,
    and SHALL NOT overwrite an existing backup.
12. WHILE no blocks are selected THE Split, Copy and Delete commands SHALL be
    disabled.
13. WHERE the open file is a `.castlib` THE grid SHALL show `cast` and `enum` block
    names in place of `#convert` type pairs.
14. IF a backup cannot be written THEN the operation SHALL abort and leave every
    file unmodified.

## 11. Testing

Headless unit tests against inline fixtures, matching how `ConvRules.Casts` and
`ConvRules.CastLib` are already tested. No VCL, no engine spawn, no file system for
the pure units. The round-trip criterion (1) is tested against the real
`sample.rules` and `casts.castlib` as fixtures, not only synthetic input.
Criterion 10 is the one integration test: compose, then shell out to
`convert-validate` and require exit 0.

## 12. Encoding

All `.pas` files strict 7-bit ASCII, CRLF. `.rules` and `.castlib` files are written
back with the line endings they were read with, so a curation operation never
rewrites a whole file's line endings as a side effect.
