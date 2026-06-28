; Pointer arithmetic on a PChar-named variable -- unsafe, pointer size is platform-specific.
; Use PChar[N] indexed access or string APIs instead.
; Heuristic: left operand starts with uppercase P (Delphi PChar naming convention).
((exprBinary
  lhs: (identifier) @ptr
  operator: [(kAdd) (kSub)]) @warn
 (#match? @ptr "^P[A-Z]"))
