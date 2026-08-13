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
; STILL TYPE-BLIND for a VARIABLE operand: `i := i + Count` is indistinguishable
; from `S := S + Word` in the tree alone. Closing that needs a store-backed
; built-in that supersedes this query when an index is present -- exactly what
; was done for string-equality-comparison (see DRagLint.CLI.pas, where the .scm
; findings are dropped when a store exists). Tracked in
; docs\INBOX-concat-in-loop-is-type-blind.md.
((assignment
  lhs: (identifier) @id
  rhs: (exprBinary
    lhs: (identifier) @lhs_id
    operator: (kAdd)
    rhs: (_) @rhs_operand)) @warn
 (#eq? @id @lhs_id)
 (#not-match? @rhs_operand "^[0-9$]"))
