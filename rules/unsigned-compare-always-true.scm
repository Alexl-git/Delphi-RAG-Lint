; An unsigned value compared `>= 0` is always true, `< 0` is always false: the test is a bug
; (usually a signed/unsigned mix-up, e.g. a loop counter or an Index that was meant to be Integer).
; Decides on the DECLARED type (#declared-type?) of the left operand. A field, a unit global or
; an undeclared operand stays SILENT -- no guess.
((exprBinary
  lhs: (identifier) @v
  operator: [(kGte) (kLt)]
  rhs: (literalNumber) @zero) @warn
 (#eq? @zero "0")
 (#declared-type? @v "^(System\.)?(Cardinal|Byte|Word|LongWord|UInt32|UInt64|NativeUInt|DWORD|UIntPtr)$"))
