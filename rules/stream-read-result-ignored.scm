; TStream.Read / Write return the byte count actually transferred; a bare statement discards it,
; so a short read or write goes unnoticed. ReadBuffer / WriteBuffer raise instead and are fine.
; Receiver is decided on its DECLARED type (T...Stream); a field/global receiver stays SILENT.
((statement
  (exprCall
    entity: (exprDot
      lhs: (identifier) @recv
      rhs: (identifier) @m)
    args: (exprArgs . (_) @a1 . (_) @a2 .)) @warn)
 (#any-of? @m "Read" "Write")
 (#declared-type? @recv "^(System\\.Classes\\.)?T[A-Za-z]*Stream$"))
