> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED (21ef119): the root cause was ONE TRAILING NEWLINE -- TTextEditApplier split an insert on newlines, so a trailing break produced an empty trailing part and every replace wrote one blank line more than it deleted, pushing the block past AllowGap. Guarded by tests/autodoc/run_doc_p3_stale_anchor.ps1.
>
> Original note follows unchanged.

# `document --qname --apply` run twice on one class nests the second block inside the first

Found 2026-08-06 while building the fixture for INBOX-datacopy section 7. Not reported by the
DataCopy reporter -- their runs were `--project`, which is a single pass.

## Reproduction

`ctorunit.pas` (indexed into a fresh DB, then two applies in a row):

```pascal
unit ctorunit;

interface

type
  TZeiss = class
  public
    constructor Create(const AText: string);
    procedure Ping(const AValue: Integer);
  end;
```

```
drag-lint index <dir> --db <db>
drag-lint document --qname ctorunit.TZeiss.Create --db <db> --apply --no-backup
drag-lint document --qname ctorunit.TZeiss.Ping   --db <db> --apply --no-backup
```

## Actual

```pascal
  TZeiss = class
  public
    /// <remarks>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: farunit.Fake (farunit.pas), nearunit.Poke (nearunit.pas)   <-- Ping's facts
    /// Calls: Create
    /// Pure
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: farunit.RunOnStartup (farunit.pas), nearunit.Build (...)   <-- Create's facts
    /// Pure
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AText: string);
    procedure Ping(const AValue: Integer);       <-- undocumented
  end;
```

Two `<remarks>` opens, two `</remarks>` closes, both blocks stacked above `constructor Create`,
and `Ping` -- the symbol the second command was asked about -- ends up with no comment at all.
The emitted XML is malformed, so a Help Insight tooltip renders whatever the IDE makes of it.

## Expected

Each block above its own declaration, or the second run refusing to write against coordinates it
cannot trust.

## Diagnosis (same family as the naming-autofix corruption, 2026-08-05)

The first `--apply` inserts 8 lines above `constructor Create`. Every declaration below it moves
down by 8. The DB is not reindexed, so `TZeiss.Ping`'s `start_line` is still the pre-edit value --
which after the insert points into the middle of the block just written. The second apply anchors
there and writes inside the first region.

This is the third instance of one root cause: **a writer that trusts index coordinates without
verifying what is actually at them.** `unused-local`'s fixer destroyed 72 lines, the naming autofix
wrote onto `then`/`else` keywords and still exited 0, and both were fixed by making
`TTextEditApplier.ExpectText` verify structurally. The doc applier evidently does not go through
that check, or does not assert the declaration text at the anchor.

## Ask

1. Before inserting, verify the anchor line still holds the declaration being documented -- reuse
   `TTextEditApplier.ExpectText` rather than adding a second verification path.
2. On mismatch, either re-resolve the declaration in the current file text or fail loudly. Writing
   at an unverified coordinate is what makes this class of bug destructive rather than merely wrong.
3. Consider self-freshening the way `document --project --reindex` already can, so a sequence of
   `--qname` applies stays coherent.

## Workaround

Use one `document --unit <file.pas> --apply` pass instead of several `--qname` applies against the
same file; the batch path computes all edits from one snapshot and is correct.
