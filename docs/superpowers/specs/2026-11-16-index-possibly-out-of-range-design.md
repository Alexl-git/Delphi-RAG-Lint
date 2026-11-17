# index-possibly-out-of-range -- design (1.52 lane IDXRANGE)

Status: DESIGN FINAL (Fable review folded in, 2026-11-16). Owner intent 2026-11-16.

## Why

An `ERangeError` (or, with `{$R-}`, a silent overrun) reaching an application user carries no
meaning for them: it is the compiler's last-resort guard. A subrange-typed index does not help --
it only moves the range error to the assignment. The rule warns where an array index can leave
the array's bounds BEFORE the runtime check fires, and points at the line that made it so: the
assignment of the index, not the access.

## Scope

- Rule id `index-possibly-out-of-range`, category `bug-patterns`, default OFF, severity `warning`
  (`hint` for the parameter case below).
- Pure AST, intra-procedural, one routine at a time. No symbol store needed.
- Arrays with known bounds: a static `array[lo..hi] of` declared as local / field / global /
  file-level type alias (same shape resolution as `constant-index-out-of-range`), and a
  dynamic or open array (`array of T`, `TArray<T>`, `TBytes`, open-array param), whose bounds
  are `0..High(A)` / `Length(A)-1`.
- Stretch (NOT required): `TList` / `IList` `.Count`.
- Literal indexes stay with `constant-index-out-of-range`.

## Terms

- **Access**: `A[idx]` where `A` is a bounded array (above) and `idx` is a bare identifier.
- **Reaching assignment**: a statement in the same routine, before the access in source order,
  that writes `idx`: `idx := expr`, `idx := idx + n` / `- n`, `Inc(idx[, n])`, `Dec(idx[, n])`.
  Walk back at most 2 such steps from the access.
- **Guard**: a condition that dominates the access (the access is inside its true branch, or
  follows an `Exit` / `raise` / `Continue` / `Break` taken when the condition fails) and bounds
  `idx` on BOTH sides for `A`:
  - `for idx := lo to hi` / `downto` over the array's bounds (`Low(A)`, `High(A)`,
    `Length(A) - 1`, `Count - 1`, the literal bounds of a static array, or tighter);
  - `while` / `repeat ... until` conditions, `if` conditions, `InRange(idx, ...)`,
    `(idx >= Low(A)) and (idx <= High(A))`, `idx < Length(A)` with a lower bound known;
  - `case idx of lo..hi:` branch;
  - early-exit form: `if (idx < 0) or (idx > High(A)) then Exit;` (or raise) before the access.
- A subrange TYPE of `idx` is NOT a guard.

## Behaviour (EARS)

1. WHEN an access `A[idx]` is reached by an assignment of `idx` in the same routine and no guard
   bounds `idx` on both sides for `A` on that path THE rule SHALL report a `warning` on the
   assignment line.
2. WHEN the assignment is `Inc(idx)` / `idx := idx + 1` inside a loop whose condition bounds
   `idx` against `A` THE rule SHALL NOT report.
3. WHEN the access lies inside `for idx := Low(A) to High(A)` (or `0 to Length(A) - 1`,
   `0 to High(A)`, or literal bounds within a static array's bounds) THE rule SHALL NOT report.
4. WHEN the access lies inside `if InRange(idx, Low(A), High(A)) then`, or after
   `if (idx < Low(A)) or (idx > High(A)) then Exit;` / `raise`, THE rule SHALL NOT report.
5. IF the guard bounds only ONE side (e.g. `if idx < Length(A)` with `idx := idx - 1`) THEN the
   rule SHALL report.
6. IF `idx` is declared with a subrange type matching the array bounds THEN the rule SHALL still
   report an unguarded assignment (the subrange only moves the range error).
7. IF the assigned `idx` reaches no bounded-array access (a dual-use variable: a counter, a
   result, a loop limit) THEN the rule SHALL NOT report that assignment.
8. WHEN `idx` reaches the access only as an unguarded parameter (no assignment in the routine)
   THE rule SHALL report a `hint` on the access line (the only case reported on the access).
9. IF the index is a literal THEN this rule SHALL NOT report (constant-index-out-of-range owns it).
10. THE rule SHALL be default OFF and appear in `rules --json` with `fixable: true`, a risky fix,
    and a string param `exception_class` defaulting to `EArgumentOutOfRangeException`.
11. WHERE the fix is applied THE fixer SHALL insert, on its own line before the statement that
    contains the access, at that statement's indentation:
    `if not InRange(idx, Low(A), High(A)) then raise <ExClass>.CreateFmt('<A> index %d outside %d..%d in <QualifiedRoutine>', [idx, Low(A), High(A)]);`
    and SHALL add `System.Math` / `System.SysUtils` to the implementation `uses` when missing.
12. THE fix SHALL be a no-op (no edit) when the access is not on a line the fixer can anchor
    (e.g. inside a one-line `if ... then A[i] := x` the insertion would change the guard).

## Non-goals

- Inter-procedural tracking (callers' ranges).
- Proving arithmetic (`idx := 2 * k + 1` is "unknown", treated as unguarded unless guarded).
- `TList.Count` (stretch only).

## Design decisions (Fable review, 2026-11-16) -- these OVERRIDE the draft text above where they differ

- Placement: extend `DRagLint.Diagnostics.BoundsNilChecks.pas` (its scope/shape code is reused);
  add the id to `LINT_GATE_BOUNDS_NIL`. New decl kind `dkDynArray` (`array of`, `TArray<`, `TBytes`).
- Access: bare-identifier entity, single bare-identifier argument, entity resolves to a bounded
  array. Routines containing `with` or `goto` are skipped (aliasing unknowable).
- Guard recognition (Q1, strict, per side):
  - lower: `idx >= Low(A)`, `idx >= <lit >= Lo>`; dynamic array also `idx >= 0`, `idx > -1`;
  - upper: `idx <= High(A)`, `idx < Length(A)`, `idx <= Length(A) - 1`, `idx <= <lit <= Hi>`,
    `idx < <lit <= Hi+1>`;
  - both: `InRange(idx, ...)`; mirrored operands (`High(A) >= idx`) accepted; `and` conjuncts
    combine sides.
- Guard sites (Q2, block dominance, not source order): an ancestor `if` (then-branch) / `while`
  condition; an ancestor `for idx := <lo> to/downto <hi>` with recognised bounds (both sides);
  a preceding sibling `if <failure> then Exit/raise/Continue/Break` whose condition is the
  negation (`(idx < Low(A)) or (idx > High(A))`, `not InRange(...)`). Any write to idx between
  the guard and the access kills the guard.
- Provenance: a side also holds when every write to idx in the routine establishes it
  (lower: a literal >= Lo, `Low(A)`, `0` on a dynamic array, or `Inc`; upper: symmetric with
  `High(A)` / `Dec`). So `i := 0; while i < Length(A) do begin A[i]; Inc(i) end` is clean.
- Report site (walk-back depth 1): the nearest preceding write of idx (`:=`, `Inc`, `Dec`) in
  source order; when none precedes, a later write inside an enclosing loop. One finding per access.
- Dual-use (Q3): no special code -- the analysis starts from accesses, so an assignment that
  reaches none is never visited. An assignment reaching an access AND other uses reports.
- Hint (Q4): idx is a parameter with no write in the routine -> `hint` on the first unguarded
  access line.
- Fix (Q5): the message carries the access line and the exception class
  (`... reaches A[i] at line N in <Routine>; fix raises <ExClass>`), parsed by the fixer
  (rule-cache safe; `RelatedLine` is not used because its consumers assume duplicate-code).
  `exception_class` comes from config `params.index-possibly-out-of-range.exception_class`
  (new `TLintConfig.IndexGuardExceptionClass`, validated `^[A-Za-z_][\w.]*$`, default
  `EArgumentOutOfRangeException`). Access line 0 = unanchorable (access in a loop header,
  `if`/`while` condition, or a one-statement then/else/case-arm/loop body) -> no edit. The
  fixer inserts the guard line before the access line (`tekInsertLines`), plus
  `BuildImplUsesEdit` for `System.Math` / `System.SysUtils` when not already in a uses clause;
  refuses when the access line does not contain `A[idx`.
- Opt-in (Q6): accepted -- default-OFF rule + fixer registered risky.
- Cut from v1 (silent, no finding): `for` loops with unrecognised bounds, `case` ranges,
  `repeat` conditions, `Assert`, field/global idx, empty-dynamic-array (`i := High(A)` counts as
  safe), `TList.Count`.

## Acceptance fixture (tests\lint\index-possibly-out-of-range.pas)

Must fire: `i := Calc; A[i]` (on the assignment); `while i < Length(A) do begin Inc(i); A[i] end`
(on the `Inc`); `i := i - 1; if i < Length(A) then A[i]` (one side only); subrange-typed
`i := Calc`; unguarded parameter (hint, on the access).
Must not: `for i := Low(A) to High(A)`; `for i := 0 to Length(A) - 1`;
`i := 0; while i < Length(A) do begin A[i]; Inc(i) end`; `if InRange(i, Low(A), High(A))`;
early `Exit` and early `raise` guards; `n := Calc` never indexing; `A[3]`; `S[i]` on a string;
guarded parameter.
Fix: the `Calc` case gains the guard line and the uses entries; a second lint of the fixed file
gives zero findings for the rule and zero edits; `if x then A[i] := 1` gets no edit.

## As built (reconcile, 2026-11-16)

Additions found necessary by the first FP measurement on CLIENT / SERVER / YADF copies; each has a
fixture case:
- **Short-circuit guards**: in `X and A[i]` the facts of X hold for the right side; in
  `X or A[i]` the facts of `not X`. (`while (i < Length(A)) and (A[i] <> 0)` is the commonest
  scan loop.) The wrong order `while (A[i] = 0) and (i <= 8)` still reports.
- **If-expressions**: `if i < Length(A) then A[i] else 0` guards like the statement form.
- **Length alias**: a local written exactly once as `n := Length(A)` / `High(A)` / `Low(A)`
  stands for the call in a guard (`while i < n`).
- **Grow-on-demand**: an earlier `if i >= Length(A) then SetLength(A, ...)` proves the upper side.
- **Reaching writes only**: provenance counts the writes before the access and those inside the
  outermost loop around it; a later reuse of the variable (`i := Pos(...)` after the scan) no
  longer breaks it.
- The autofix is a per-file fixer (RegisterFileFixer, risky) so the uses edits are emitted once.
- Messages: `'<i>' is written here and reaches A[i] at line N with no guard ... (in <Routine>;
  fix raises <Class> at line K)` or `(...; no autofix: ...)`; the hint starts `Parameter '<i>'`.

## Owner rulings round 6 + ORM3 batch 3 (lane IDXRANGE2, 2026-11-17) -- OVERRIDE the text above

- **C3 default ON.** The InRange + `<exception_class>` fix is MANUAL ONLY: `MarkFixManualOnly`
  (DRagLint.Lint.Autofix); a batch `--fix` (no `--fix-rule`, i.e. fix-all in a unit / project) withholds it
  with a stderr note; `--fix-rule index-possibly-out-of-range` (the IDE's Fix it) applies it; `rules --json`
  carries `fix_manual_only: true`. The user edits the inserted message text afterwards.
- **Symbolic bounds.** Bounds are `count(Base) + Off` (Base `len:a`, `cnt:b`, `id:n`, or constant): SetLength
  size expressions (`High(D) - Low(D) + 3` = `len:d + 2`), static bounds, `X.Count`, unwritten names, Length
  aliases. A field / global array uses the size every SetLength of the FILE agrees on (`X.Count`, `Length(X)`,
  constant; any assignment / Delete / Insert = unknown).
- **C1 parallel arrays.** Silent when the other collection's bound is PROVEN within this array's (same SetLength
  count, static bounds within, same SetLength source, or every local caller sizing the parameter array from the
  guarded count). Otherwise a WARNING naming the bound (`bounded only by Names.Count ...`); a `for` loop running
  to another collection's bound now reports on the `for` line (was a silent v1 cut); a parameter checked against
  another collection is a warning, not a hint.
- **C2 unchecked index parameter.** Cleared when EVERY local call passes an index proven in range (the caller's
  guards / provenance / for bounds, or a literal within a static array). Only routines whose every name use in the
  file is a plain call: one definition, no declaration (interface, class member, forward), not a method, never
  passed as a value. Depth 1 (a caller's own parameters are not traced further).
- **C2 external callers -- DESIGN ONLY, later lane.** IDE right-click "Verify all callers" on the hint: the engine
  runs the C2 proof over every caller in the project index (find-callers --resolved, each caller's unit parsed);
  on success it writes `// dl:ok-range@<hash> <ISO8601> verified N callers` at the routine and a matching marker at
  each caller line. The hash covers the routine signature + the guarded access line and, per caller, the call
  line; a later edit of either changes the hash, the marker reads stale (review-marker-stale) and the finding
  returns. Second right-click: "Insert range check" = the manual fix above for the parameter.
- **ORM3 batch 3.** (1) wrong-order `while A[i] and (i <= G) do Inc(i)` reads at most G + 1 -- in range when the
  SetLength gives slack (BASICSF:1394 FP), TP otherwise; (2) uINSPRSLT:5575 TP: the second array read after the
  loop (`NssDistConvert[i]`, 0..4) -- fixture positive control; the real site needs the cross-unit const (open);
  (3) Exit-capped step: `Inc(j); if j > High(sa) - 1 then begin ...; Exit end` caps j, the then-branch sees cap + 1;
  with the local callers' least static length (GAGEFRM2:417 FP; a 1-slot caller is a TP); (4) one step per trip of
  a `for` whose trip count is within the array (Blueprint4:1722 FP); (5) an index read from a lookup
  (`GetValueOrDefault`, `Items[]`, `Map[k]`) is a HINT -- its value range is invisible (uJobList:997 / uJobList2:704).