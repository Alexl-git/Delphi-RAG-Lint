; Pointer arithmetic on a PChar-named variable -- unsafe, pointer size is platform-specific.
; Use PChar[N] indexed access or string APIs instead.
; Heuristic: left operand starts with P + uppercase letter + lowercase letter (e.g. PBuf, PStr,
; PMyVar). This excludes ALL-CAPS names like PLUGIN_VERSION which are constants, not pointers.
((exprBinary
  lhs: (identifier) @ptr
  operator: [(kAdd) (kSub)]) @warn
 (#match? @ptr "^P[A-Z][a-z]"))
