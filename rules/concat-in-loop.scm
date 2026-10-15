; S := S + X inside a LOOP is O(n^2): each + allocates a new string.
; Use TStringList.Add + TStringList.Text, or string.Join.
;
; The loop requirement lives in the sidecar json ("require_ancestor"), not in
; this query: tree-sitter patterns match a subtree shape, and "has some ancestor
; of kind K" is a property of the path to the root, which a pattern cannot ask
; about. Without it this rule fired on EVERY self-concatenation in the program
; -- 328 findings on drag-lint's own source, most of them executed once and
; therefore quadratic in nothing -- while its id, this comment and its message
; all said "in a loop".
;
; The sidecar lists FOUR loop node kinds: for, foreach, while, repeat. `foreach`
; is the grammar's node for `for X in Y do`; it was missing until 2026-09-24
; (D20), so a for-in accumulation never fired. Matching is by EXACT node kind.
;
; TWO CONSTRAINTS ADDED 2026-08-13, both from sampled false positives on YADF:
;
;   operator: (kAdd)   -- the pattern used to accept ANY exprBinary, so
;                         `k := k + 2` and equally `i := i - 1` were reported as
;                         string concatenation. Nothing but `+` concatenates.
;
;   #not-match? on the right operand -- `i := i + 1` is integer arithmetic, and
;                         no string concatenation can have a NUMERIC LITERAL on
;                         the right: `S := S + 1` does not compile in Delphi. So
;                         excluding a right operand that starts with a digit or
;                         `$` (hex) is type-safe reasoning without a type, and it
;                         removes the whole increment/decrement class.
;
; THIRD CONSTRAINT ADDED 2026-08-14, from a 14-finding sample on drag-lint's own
; source (5 were false positives, 4 of them this one shape):
;
;   #not-match? "^\\["  -- `Names := Names + [NameId]` is DYNAMIC ARRAY append,
;                         not string concatenation. A right operand that opens
;                         with `[` is an array/set constructor, and
;                         `S := S + ['x']` does not compile in Delphi -- so, like
;                         the numeric-literal exclusion above, this is type-safe
;                         reasoning WITHOUT a type. Measured on drag-lint: 4 of
;                         14 sampled findings were `Result := Result + [X]` in
;                         Doc.Facts, Doc.Strip, Lint.Baseline and
;                         Diagnostics.AstChecks.
;
;                         Note it is also not even quadratic in the way the
;                         message claims: appending to a dynamic array reallocs,
;                         but the advice ("use TStringList or string.Join") is
;                         nonsense for an array of records. A wrong finding AND
;                         unfollowable advice.
;
; A VARIABLE operand cannot be typed from the tree: `i := i + Count` and
; `S := S + Word` are the same subtree -- `StartPos := StartPos + Length(...)`
; was the 5th false positive in that sample. FIFTH CONSTRAINT, 2026-10-09
; (Gitea drag-lint#7; ~40% of this rule's findings on sampled production code were
; numeric sums):
;
;   #not-declared-numeric? @id -- reads the DECLARATION of the assigned name in
;                         the routine the assignment sits in (its var sections,
;                         parameters, inline `var X: T`, and the return type for
;                         Result), then in an enclosing routine. A declared
;                         numeric type (Integer, Int64, Currency, Double, ...)
;                         drops the match. Anything not declared there with one
;                         written type -- a field, a global, `var X := e` -- is
;                         UNKNOWN and keeps the finding, so a real string
;                         accumulation is never hidden. Works without an index.
;                         (DRagLint.Lint.QueryRules, DeclaredTypeInRoutine.)
;
; WHAT THE QUERY STILL CANNOT TYPE: a variable the routine does not declare with ONE
; written type (a field, a global, an inline `var X := e`) -- UNKNOWN, so the finding
; stays. WITH A STORE the surfaces close that gap after the fact (2026-09-27, R11):
; lint, lint-all and the LSP pass these findings through TAstChecker.DropNonStringConcat,
; which drops a match whose target's declared type is proven non-string (numeric,
; boolean, enum, pointer, dynamic array, set) and keeps an unknown or ambiguous one.
; Without a store (bare `lint <file>`) the declaration-based predicate above is the
; only type reasoning there is.
; Pinned by tests\autotest\run_concat_in_loop_type_aware.ps1.
;
; FOURTH CONSTRAINT ADDED 2026-09-23 (L6):
;
;   #not-reset-in-loop? -- `T := 'row '; T := T + IntToStr(J);` in a loop body
;                         REBUILDS T every pass; it never accumulates, so there
;                         is nothing quadratic to report. The predicate (in
;                         DRagLint.Lint.QueryRules, ResetInSameIteration) drops
;                         the match when the SAME variable is also assigned,
;                         from an expression that does not read it, by a sibling
;                         statement on the path up to the NEAREST loop -- i.e.
;                         unconditionally, before or after, in the same pass. A
;                         reset inside an `if` is conditional and does not count.
((assignment
  lhs: (identifier) @id
  rhs: (exprBinary
    lhs: (identifier) @lhs_id
    operator: (kAdd)
    rhs: (_) @rhs_operand)) @warn
 (#eq? @id @lhs_id)
 (#not-match? @rhs_operand "^[0-9$]")
 (#not-match? @rhs_operand "^\\[")
 (#not-reset-in-loop? @warn)
 (#not-declared-numeric? @id))
