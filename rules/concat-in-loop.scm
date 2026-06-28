; S := S + X -- self-concatenation is O(n^2): each + allocates a new string.
; Use TStringList.Add + TStringList.Text, or string.Join, especially inside loops.
((assignment
  lhs: (identifier) @id
  rhs: (exprBinary
    lhs: (identifier) @lhs_id)) @warn
 (#eq? @id @lhs_id))
