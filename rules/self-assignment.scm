; 'X := X' assigns a variable to itself -- a no-op, and almost always a
; copy-paste error where the intended target or source was something else.
; Matches an assignment whose lhs and rhs are the same identifier.
((assignment
  lhs: (identifier) @l
  operator: (kAssign)
  rhs: (identifier) @r) @warn
  (#eq? @l @r))
