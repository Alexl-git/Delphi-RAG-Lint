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

; Unsigned value compared with the largest value its own type can hold: `B > 255` is always false,
; `B <= 255` always true (Byte; Word: 65535; Cardinal / LongWord / UInt32 / DWORD: 4294967295).
((exprBinary
  lhs: (identifier) @v
  operator: [(kGt) (kLte)]
  rhs: (literalNumber) @lim) @warn
 (#eq? @lim "255")
 (#declared-type? @v "^(System\.)?Byte$"))

((exprBinary
  lhs: (identifier) @v
  operator: [(kGt) (kLte)]
  rhs: (literalNumber) @lim) @warn
 (#eq? @lim "65535")
 (#declared-type? @v "^(System\.)?Word$"))

((exprBinary
  lhs: (identifier) @v
  operator: [(kGt) (kLte)]
  rhs: (literalNumber) @lim) @warn
 (#eq? @lim "4294967295")
 (#declared-type? @v "^(System\.)?(Cardinal|LongWord|UInt32|DWORD)$"))