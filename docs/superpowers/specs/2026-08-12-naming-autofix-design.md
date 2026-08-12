# Design -- naming autofix: underscore/case synthesis, prefix repair, shadow rules

**Date:** 2026-08-12
**Status:** approved design, not yet planned or implemented
**Owner ruling that started this:** PascalCase names do not contain underscores.
The fix belongs in the code, not in a relaxed rule.

## Problem

`drag-lint` already has a naming autofix (`DRagLint.Refactor.NamingFix`, opt-in
per rule via the config `"autofix": [...]` list, covering `method-pascalcase`,
`local-var-casing`, `const-casing`, `field-name-prefix`, `param-name-prefix`,
`type-name-prefix`). It has four defects that make it unable to fix the findings
we actually have.

1. **It cannot fix an underscore name at all.** `SynthesizeCasedName` for
   PascalCase is `UpperCase(S[1]) + Copy(S, 2, MaxInt)`. For `Out_` that returns
   `Out_`, which equals the old name, so `BuildNamingFixEdits` hits
   `if NewName = OldName then Continue` and silently skips. Every underscore
   finding is unfixable today.
2. **No reserved-word check in the synthesis path.** `TRenameRefactoring.
   IsReservedWord` exists but is consulted only by the manual `rename` command
   and `ExtractMethod`. A synthesized name can collide with a keyword.
3. **Collisions skip rather than disambiguate.** `LocalNameCollides` returns
   True and the caller does `Continue`, so the finding is reported forever.
4. **The lowercase-prefix case does not converge.** `SynthesizePrefixedName`
   tests "already prefixed" case-INSENSITIVELY, so `fCount` is treated as
   already carrying the `F` prefix and returned unchanged -- while the RULE
   (`HasPrefix`, case-SENSITIVE) flags it. The finding is emitted on every run
   and the autofix does nothing about it, forever.

Measured motivation: YADF held 79 `local-var-casing` findings; 18 were `Out_`,
i.e. class (1) above.

Note for a future reader: those 18 were already fixed BY HAND on 2026-08-12 as
`Out_` -> `OutVal`, so YADF no longer reproduces the case. The automated
pipeline below would produce `OutVar` (strip underscore -> `Out` -> reserved ->
append `Var`). `OutVal` is itself valid PascalCase, unreserved and uncolliding,
so no rule fires on it and the autofix will not churn it back.

## Delivery order

Two independent phases; each can be planned and shipped on its own.

* **Phase 1 -- the autofix.** `NamePlan`, the scope wiring, `record_prefix`, and
  compile-verified application. This is what unblocks the existing findings.
* **Phase 2 -- the shadow rules.** `local-name-shadows-type` and
  `type-shadows-library-type`. Additive, no autofix, and they depend on Phase 1
  only for the `AKnownTypes` set, which Phase 1 must build anyway.

## Approach: a pure name planner, then extend the existing engine

Rejected alternatives:

* **Extend `NamingFix` in place.** Smallest diff, but the tricky logic stays
  welded to a unit needing a store, real files and a compiler, so edge cases can
  only be exercised end-to-end. This repo already paid for a synthesis bug that
  isolated tests would have caught: the `fi` -> `Fi` fix invented a fake field
  prefix.
* **Compiler-driven iteration** (apply, build, read errors, adjust). Needs no
  scope knowledge, but one build per attempt is unusable at 79 findings and
  Delphi diagnostics are not a stable API.

### 1. New unit `DRagLint.Refactor.NamePlan` -- PURE

No store, no file I/O, no compiler. All context is passed in.

```pascal
type
  TNameKind = (nkLocal, nkParam, nkField, nkConst, nkMethod,
               nkClass, nkInterface, nkRecord, nkException, nkPointer);

  TNamePlan = record
    NewName : string          ;
    Changed : Boolean         ;
    Unfixable: Boolean        ; // pipeline did not stabilise -- report, do not guess
    Steps   : TArray<string>  ; // ordered audit trail; feeds --dry-run and tests
  end;

function PlanName(const AOld: string; AKind: TNameKind; const ACfg: TNamingConfig;
                  const ATaken, AKnownTypes: TNameSet): TNamePlan;
```

**Pipeline.**

1. **Split on underscores.** Per word: uppercase the first character, and
   lowercase the tail ONLY if the whole word was uppercase. Join.
   `My_Var_` -> `MyVar`; `MAX_SIZE` -> `MaxSize`; `origLine` -> `OrigLine`;
   `iVal` -> `IVal`. A camelCase target lowercases the first word's initial.
   Underscore-only input reduces to '' and is `Unfixable`.
2. **Prefix** (prefix rules only). If the name already starts with the prefix
   letter case-INSENSITIVELY followed by an uppercase character, repair only
   that letter's case: `fCount` -> `FCount`. Otherwise prepend the prefix and
   uppercase what follows. This is the fix for defect (4).
3. **Shape guard.** For a NON-type kind, if the result starts with a type prefix
   (`ClassPrefix`/`ExceptionPrefix`/`InterfacePrefix`/`PointerPrefix`/
   `RecordPrefix`) followed by an uppercase character, OR equals a member of
   `AKnownTypes` case-insensitively, prepend `X`. `TList` -> `XTList`.
   Rationale (owner): a local named `TListVar` reads as a type.
4. **Reserved word.** If reserved (case-insensitive), disambiguate via step 5.
5. **Collision.** Generate candidates in order -- `Name`, `NameVar`, `NameVar2`,
   `NameVar3`, ... -- and accept the FIRST that satisfies all three of: not
   reserved (step 4), not in `ATaken` case-insensitively, and not rejected by the
   shape guard (step 3). The suffix is the fixed literal `Var`; there is no
   configurable suffix (YAGNI).
6. Steps 3-5 are one accept-test applied to a candidate sequence, so the loop is
   bounded by construction. Cap it at 100 candidates; if none is accepted, set
   `Unfixable` and change nothing -- never emit a guessed name.

`ATaken` and `AKnownTypes` are supplied by the caller, keeping scope resolution
out of the pure layer.

### 2. Scope supplied by `NamingFix` (per kind, natural scope)

| Kind | `ATaken` is drawn from |
|---|---|
| local, param | the enclosing routine (AST walk -- `LocalNameCollides` already does this) |
| field | the declaring class **and its ancestors** |
| const, method, type | the declaring unit, plus every unit that `uses` it |

`AKnownTypes` = type-kind symbols from the project index, plus the platform
library index when one is configured.

### 3. Two new lint rules

* **`local-name-shadows-type`** -- severity **warning**. A local or parameter
  whose name equals a known type name, compared case-insensitively (Delphi is
  case-insensitive, so both `TList` and `tlist` fire).
* **`type-shadows-library-type`** -- severity **hint**. A type declared in the
  project whose name equals a type in the platform library index. This is often
  a deliberate workaround, so it is a hint to double-check, never an error.
  Degrades silently to no findings when no library DB is configured.
  **Known limitation:** the Win64 library index is recorded as INCOMPLETE, so
  this rule under-reports on Win64 until that index is rebuilt.

Both rules are additive; neither has an autofix.

### 4. Config

One new key, `record_prefix`, default **`''` (off)** -- matching `param_prefix`.
Defaulting it to `R` would light up every existing project at once, against the
standing rule that a finding count in the thousands is itself the defect. The
autofix for it, and for the other prefix rules, remains opt-in through the
existing `"autofix": [...]` list.

### 5. Application and verification

Owner ruling: **compile-verify, roll back on failure.** Follows the existing
compiler-verified `uses-fix` command, which already takes `--project <dproj>`
and `--platform win32|win64`.

1. Plan every rename (pure, fast, no writes). `--dry-run` prints the plan --
   old -> new plus `TNamePlan.Steps` -- and exits.
2. `--apply` writes all planned renames, then builds once.
3. On build failure, **binary-search the rename set** to isolate the offending
   rename: ~7 builds for 79 renames rather than 79. Restore the offender, apply
   the largest passing subset, and report each rejected rename with the compiler
   error that rejected it.
4. Backups follow the existing `--no-backup` convention.

This is what makes the known ref-gap tolerable: `field-name-prefix` can still
leave a bare field read (`X := field + 1`) unrenamed because that site is not
indexed, but the build then fails and the rename is rolled back instead of
leaving silently non-compiling source with exit code 0.

## Error handling

* `Unfixable` plans are reported, never applied.
* A rename rejected by the compiler is rolled back individually; the rest of the
  batch still lands.
* No library DB configured -> `type-shadows-library-type` yields nothing and
  says so once, rather than erroring.

## Testing

* **Table-driven unit tests for `PlanName`** -- the whole point of the pure
  split. Cases: `Out_`->`OutVar`, `My_Var_`->`MyVar`, `MAX_SIZE`->`MaxSize`,
  `fCount`->`FCount`, `iVal`->`IVal`, `TList`->`XTList` (local),
  reserved-word hits, collision escalation `Name`/`NameVar`/`NameVar2`,
  underscore-only input -> `Unfixable`, and camelCase targets.
* **Fixture tests** for the two new rules, including the case-insensitive pair
  `TList` / `tlist`.
* **Compile-verify test**: a fixture whose rename is known to break the build,
  asserting rollback leaves the source byte-identical.
* **YADF interaction test** -- see below.

## Interaction with YADF (called out by the owner)

YADF normalises identifier case to the **first occurrence**. Spelling changes
(prefixes, underscore removal) are immune. **Pure re-casing is not**: if
drag-lint re-cases a declaration but any use site keeps the old case, YADF will
normalise every occurrence back to whichever comes first, silently reverting the
fix. Compile-verify cannot catch this -- the code compiles either way.

Requirement: case-only renames must rewrite EVERY occurrence, and a regression
test must run YADF over the fixed fixture and assert the casing survives.

## Out of scope

Renaming across project boundaries (a public type used by another project's
index), and any change to which rules are enabled by default beyond the new
`record_prefix` key.
