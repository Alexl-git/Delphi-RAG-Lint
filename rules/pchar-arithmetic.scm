; Pointer arithmetic on a character/byte pointer -- unsafe, pointer size is platform-specific.
; Use PChar[N] indexed access or string APIs instead.
; Decides on the DECLARED type of the left operand (#declared-type?), not its name: until
; 2026-10-14 this matched a P + uppercase + lowercase name and reported `PRows := PRows + [Row]`
; on a TArray (INBOX-bare-call-in-if-else-and-pchar-name-fp section 2). An operand whose
; declaration is not visible in the file (a field, another unit's global, an untyped inline
; var) stays SILENT -- no guess.
((exprBinary
  lhs: (identifier) @ptr
  operator: [(kAdd) (kSub)]) @warn
 (#declared-type? @ptr "^(System\\.)?(PChar|PAnsiChar|PWideChar|PUTF8Char|PByte|\\^(Char|AnsiChar|WideChar|UTF8Char|Byte))$"))
