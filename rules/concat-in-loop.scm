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
((assignment
  lhs: (identifier) @id
  rhs: (exprBinary
    lhs: (identifier) @lhs_id)) @warn
 (#eq? @id @lhs_id))
