; Comparing '.ClassName' to a string literal (X.ClassName = 'TFoo') is fragile:
; it breaks on rename/refactor and ignores inheritance. Use 'X is TFoo' or
; 'X.InheritsFrom(TFoo)' instead.
((exprBinary
  lhs: (exprDot rhs: (identifier) @prop)
  operator: [(kEq) (kNeq)]
  rhs: (literalString)) @warn
  (#eq? @prop "ClassName"))
; v151 WID-SCM: ClassNameIs('TFoo'), a bare ClassName (inside the class), and the
; literal on the left ('TFoo' = X.ClassName).
((exprCall
  entity: (exprDot rhs: (identifier) @prop)
  args: (exprArgs . (literalString))) @warn
  (#eq? @prop "ClassNameIs"))
((exprBinary
  lhs: (identifier) @prop
  operator: [(kEq) (kNeq)]
  rhs: (literalString)) @warn
  (#eq? @prop "ClassName"))
((exprBinary
  lhs: (literalString)
  operator: [(kEq) (kNeq)]
  rhs: (exprDot rhs: (identifier) @prop)) @warn
  (#eq? @prop "ClassName"))
