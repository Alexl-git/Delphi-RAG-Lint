; `Float := A div B` throws the fraction away BEFORE the assignment -- almost always a `/` that
; was typed as `div`. Decides on the DECLARED type of the assignment target; a field or an
; undeclared target stays SILENT. Only a top-level `div` on the right fires.
((assignment
  lhs: (identifier) @v
  operator: (_)
  rhs: (exprBinary operator: (kDiv))) @warn
 (#declared-type? @v "^(System\.)?(Single|Double|Extended|Real|Currency)$"))
