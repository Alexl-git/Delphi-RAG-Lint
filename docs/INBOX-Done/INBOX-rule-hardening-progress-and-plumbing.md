> **RETIRED to INBOX-Done/ on 2026-08-15.** PROGRESS LOG for the rule-hardening pass, superseded by the plan note and by the per-rule notes that outlived it.
>
> Original note follows unchanged.

# Rule hardening -- what landed, what it yielded, and the exact work left

Continues `INBOX-rule-hardening-plan-2026-08-13.md`. Written after implementing
the first tranche, with MEASURED yields rather than estimates -- two of my own
estimates in that plan were wrong and are corrected here.

## Landed

| Rule | Estimated | **Measured** | Commit |
|---|---:|---:|---|
| `sql-injection-concat` | 1+ | **1** | `56ba36c` |
| `try-except-swallowed` (reporting handlers) | part of 38 | **2** | this tranche |

## Two corrections to my own analysis

### 1. `object-leak` cause A does NOT exist

The plan claimed ~15 findings from "the guard is the next statement". **Wrong.**
A probe (`scratchpad\leakprobe.pas`) exercising five shapes shows the flow
analysis already handles them:

| shape | result |
|---|---|
| `X := T.Create; try..finally X.Free; end` | correctly SILENT |
| `Result := T.Create; try..except Result.Free; raise; end` | correctly SILENT |
| two Creates before one shared `try..finally` | correctly SILENT |
| `X := T.Create;` never freed | correctly FIRES |
| `T := TTimer.Create(AOwner);` | **incorrectly FIRES** |

So the earlier "8 of 8 sampled false" was read off the source shape without
testing the analyser, and it was too quick. Only the OWNERSHIP case is broken.
The real-code sites that looked like cause A (`YADF.Tokens.pas:266`,
`uFileUtils.pas:1691`) are nested try/finally inside an outer try/except and
need re-examination on their own; they are NOT the simple shape.

### 2. `empty-except` is comment-sensitive BY ACCIDENT, not by design

The plan argued `try-except-swallowed` should honour an explanatory comment
"consistent with `empty-except`". That precedent does not exist. `empty-except`
is a `.scm` query with an adjacency anchor:

    ((try (kExcept) @warn . (kEnd)))

The `.` requires kExcept to be IMMEDIATELY followed by kEnd. A comment breaks
adjacency, so the rule stops firing -- an artifact of tree-sitter's anchor
semantics. `COMMENT_SENSITIVE` in `DRagLint.CLI.pas` documents that artifact so
markers are not nagged about; it does not endorse "a comment is the remedy" as
policy.

**So making `try-except-swallowed` comment-sensitive remains a genuine owner
ruling and was NOT done.** It is worth ~43 findings (DataCopy 18, YADFOT 18,
YADFSetup 7), all of the shape:

    except
      // Deliberately swallowed. This destructor runs during Spring
      // GlobalContainer finalization; a read-only INI directory ... would
      // otherwise let an exception escape a destructor -- far worse than a
      // lost settings write ...
    end;

## The work left, with the plumbing spelled out

### A. `object-leak` ownership needs the LIBRARY store (~14, VCL-heavy projects)

`ConstructorTransfersOwnership` (`DRagLint.Diagnostics.FlowChecks.pas:205`) does

    if (TypeName = '') or (not AStore.IsDescendantOf(TypeName, 'TComponent', AFileId)) then Exit;

`AStore` is the PROJECT store. `TTimer`, `TButton` and every other VCL component
lives in the LIBRARY index, so `IsDescendantOf` returns False and ownership is
never detected. This is the owner's two-DB model in miniature: the question needs
both databases and the call site only has one.

**Plumbing (all pieces already exist):**

1. `OpenLibraryStores` already exists in `DRagLint.CLI.pas` -- reuse it; do not
   write a new opener.
2. Add an optional `ALibStore: ISymbolStore = nil` parameter to
   `TFlowChecker.Check` (`FlowChecks.pas:502`). Three call sites:
   `CLI.pas:7105` (bare `lint`, pass nil), `CLI.pas:9956` (lint-all, pass the
   library store), `CLI.pas:12696`.
3. Thread it to `ConstructorTransfersOwnership` and try the project store first,
   then the library store.
4. Open the library store ONCE per `lint-all` run, not per file -- it is ~2.2 GB.
   `DoLintAll` already resolves `LibDb` for `CheckUsedUnitResolvable`, so the
   path is in hand.

Guard: extend `scratchpad\leakprobe.pas` into a real fixture -- it already has
the owned-component case and a genuine leak as the control.

### B. `used-before-assignment` -- an `out` argument is a WRITE (7)

`FlowChecks.pas:561-619`. A call argument is added to BOTH `Reads` (checked at
line 571) and `CallDefs` (applied at line 619, i.e. AFTER the read check). So
`SafeDelete(LFile, LSweepErr)` with

    function SafeDelete(const APath: string; out ErrCode: DWord): Boolean;

flags `LSweepErr` as read-before-assignment, then marks it assigned.

Fix: resolve the callee's parameter modifiers and, for an `out` parameter, put
the argument in `CallDefs` ONLY -- never in `Reads`. `var` stays read+write;
value/`const` stays a read. The callee lookup already exists in this file --
`OwnsOracle` (`FlowChecks.pas:1048`) resolves a callee by name and walks its
parameters, so the same machinery answers this.

### C. `unused-parameter` -- signatures that are not ours (7)

`DeadCodeChecks.pas:509-539` already skips a method whose FIRST parameter is
named `Sender`, and `ContractMethods` skips known contract names. Two shapes get
through:

* `TfrmZeissCopy.FormHelp(Command: Word; Data: NativeInt; var CallHelp: Boolean)`
  -- a VCL form event with no `Sender`. A method on a form/frame class whose name
  begins with `Form` is a form event handler by long-standing convention
  (FormCreate/FormShow/FormCloseQuery/FormHelp...). Cheap and safe.
* `DescribeExceptionInfo(const ACustom: Pointer; ...)` -- a EurekaLog callback.
  General detection: a routine whose name is referenced somewhere as a BARE
  identifier (taken as a procedural value, not called) has a signature fixed by
  the procedural type it is assigned to. Needs cross-file reference data, which
  the index has.

Better than either: `SymbolFacts` already carries a `DfmEvent` field, and
ancestry is resolved at index time -- so "is this an override / an interface
implementation / DFM-wired" is answerable from the store today.

### D. The type-blind pair (~16)

`length-zero-compare` and `concat-in-loop`. Both are `.scm` queries reasoning
about syntax where the answer needs a declared type. Precedent already wired:
`string-equality-comparison` is superseded by a store-backed built-in when an
index is present -- `DoLintAll` drops the `.scm` findings for that id. Copy it.

### E. `unused-public-symbol` (~5) and `field-name-prefix` (6)

E needs cross-project reachability (see
`INBOX-cross-project-symbol-use-defeats-single-project-rules.md`). F needs an
owner ruling on whether `F` is a backing-field convention (private only) or a
requirement on all fields -- see `INBOX-rule-hardening-plan-2026-08-13.md` item 10.

## Realistic remaining yield

| Item | Findings | Blocked on |
|---|---:|---|
| A `object-leak` ownership | ~14 | plumbing only |
| B `used-before-assignment` | 7 | plumbing only |
| C `unused-parameter` | 7 | plumbing only |
| D type-blind pair | ~16 | plumbing only |
| E `unused-public-symbol` | ~5 | design (multi-DB reachability) |
| F `field-name-prefix` | 6 | **owner ruling** |
| G `try-except-swallowed` comment policy | ~43 | **owner ruling** |

**~44 from plumbing, ~49 more behind two owner rulings.** The 70-90 target is
reachable, but roughly half of it is a policy decision rather than code.

---

# OUTCOME (2026-08-13, later the same day)

Both owner rulings were given, and A / B / C / F / G were worked. What follows
is what LANDED, measured, with the estimates above corrected where they were
wrong. **D is the only item still open.**

## Owner rulings

1. **`try-except-swallowed` -- a documented deliberate swallow is ACCEPTED.**
   Implemented as: an except body that runs NO code and carries a non-marker
   comment. Both halves matter. A handler that runs code and merely carries a
   trailing `// retry backoff` still fires -- that is the more dangerous shape,
   and it is not what was ruled on. A `dl:ok` marker does NOT count as
   documentation, which is precisely what keeps this rule OUT of
   COMMENT_SENSITIVE: the marker leaves the rule firing, so it suppresses
   normally and is accounted for instead of being reported unused.
   Guard: `tests\autotest\run_swallow_documented.ps1`.

2. **`field-name-prefix` -- `F` is a BACKING-FIELD convention: private and
   strict-private only.** This replaced a type-based heuristic that was wrong
   from both ends -- it asked "is the type T-something?" to detect the IDE's DFM
   component dump, and honoured that skip only in the implicit-first section, so
   on a hand-written class it exempted `Name: TStringList` and `Ready: Boolean`
   while flagging `Count: Integer`. The declared TYPE never had any bearing on
   whether a field backs a property; visibility does. The DFM dump is still
   exempt, now for the right reason: it is written into the implicit-first
   section, which is not private.
   Guard: `tests\lint\field-name-prefix-visibility.pas`, plus the three
   pre-existing fixtures, which all still pass unchanged.

## A -- landed, but the commit needed fixing before it was fit to keep

A resumed background session (the episodic-memory `--resume` agents; see the
auto-memory note) committed the plumbing as `46d66ac` while this work was in
flight. The mechanism was right and is kept. Three defects in it were not:

* **A hardcoded `C:\Projects\.drag-lint` fallback path, preferring Win64
  unconditionally.** That is a machine-level setting that lives in the manifest,
  and a fixed platform preference is the same class of mis-selection that made
  `used-unit-not-resolvable` fire 99 times on DataCopy. Replaced with
  `ResolveLibraryDb`, which resolves through the manifest using the SAME platform
  precedence as `ResolveConsumerDbs` (CLI `--platform` > the project's own folder
  > cwd > manifest default).
* **`LibStore.Migrate` on a ~2.2 GB shared index.** Running schema migrations as
  a side effect of linting takes a write lock on other people's data. Dropped, to
  match `OpenLibraryStores`, which opens without migrating.
* **The args/nil-check block copy-pasted into both branches.** Folded into one
  descends-from-TComponent test.

Guard: `tests\autotest\run_flow_store_precision.ps1` section A. It builds its own
two-database world (a fake VCL indexed as `library-Test.sqlite`) rather than
leaning on the real library index, so it is hermetic. `TTimer.Create(nil)` is the
control -- one argument away from the owned case, and it must still fire.

## B -- THE PREMISE WAS FALSE. Reverted.

A bare identifier argument goes to `CallDefs` ONLY; it is never added to `Reads`.
So the described defect cannot occur, and a parameter-modifier oracle changes
nothing. It was written, measured at **zero**, and removed. The real shape is an
intra-item ordering problem around short-circuit `and`.

Full write-up, with the reproducers and the disproof:
`INBOX-used-before-assignment-real-shape-is-intra-item-ordering.md`.

**This is the second estimate in this document to die the same way** (the first
was `object-leak` cause A). Both were read off source shape or a doc comment
rather than run against a built engine.

## C -- landed, narrower than proposed

Only the form-event half. `unused-parameter` now exempts a QUALIFIED method whose
bare name is in the VCL's own list of `TForm`/`TFrame` published events, which
covers the measured case (`TfrmZeissCopy.FormHelp`, no `Sender`, so the existing
guard missed it). Deliberately an exact list, not a `Form*` prefix -- a prefix
would also exempt every `TFoo.Format`.

The procedural-value half (a routine referenced as a bare identifier has its
signature fixed by the procedural type it is assigned to) was NOT done: it needs
cross-file reference data, and `TDeadCodeChecker.Check` takes no symbol store.
The better fix named in the plan -- `SymbolFacts.DfmEvent` -- has the same
blocker. Both are plumbing, not analysis.

## D -- still open, and now the largest single item left

`concat-in-loop` is **15 findings on DataCopy alone**, the biggest remaining rule
there. Superseding the two `.scm` queries with store-backed built-ins (the
`string-equality-comparison` precedent) is unchanged as the plan.
