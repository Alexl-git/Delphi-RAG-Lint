; SizeOf(Pointer) = 4 / = 8 bakes in a platform assumption.
; On Win64 pointers are 8 bytes; on Win32 they are 4. The literal breaks cross-platform.
; Use {$IFDEF WIN64} or compare SizeOf(Pointer) to SizeOf of another platform-aware type.
((exprBinary
  lhs: (exprCall entity: (identifier) @fn
                 args: (exprArgs (identifier) @arg))
  rhs: (literalNumber) @lit) @warn
 (#eq? @fn "SizeOf")
 (#eq? @arg "Pointer")
 (#match? @lit "^[48]$"))
