; Comparing '.ClassName' to a string literal (X.ClassName = 'TFoo') is fragile:
; it breaks on rename/refactor and ignores inheritance. Use 'X is TFoo' or
; 'X.InheritsFrom(TFoo)' instead.
((exprBinary
  lhs: (exprDot rhs: (identifier) @prop)
  operator: [(kEq) (kNeq)]
  rhs: (literalString)) @warn
  (#eq? @prop "ClassName"))
