; `I64 := A * B` with A, B 32-bit or narrower: the product is computed in 32 bits and overflows BEFORE
; it is widened to the 64-bit / floating target. Cast one operand first: `Int64(A) * B`.
; Only identifier operands of a declared integer type and a declared wide target fire; sums are not
; flagged in v1. @warn is the product itself (the autofix replaces just that span). A field, a unit
; global or an undeclared operand stays SILENT -- no guess.
((assignment
   lhs: (identifier) @l
   operator: (kAssign)
   rhs: (exprBinary
          lhs: (identifier) @a
          operator: (kMul)
          rhs: (identifier) @b) @warn)
 (#declared-type? @l "^(System\\.)?(Int64|UInt64|NativeInt|NativeUInt|Double|Extended)$")
 (#declared-type? @a "^(System\\.)?(Integer|Cardinal|LongInt|LongWord|Word|SmallInt|Byte)$")
 (#declared-type? @b "^(System\\.)?(Integer|Cardinal|LongInt|LongWord|Word|SmallInt|Byte)$"))

((assignment
   lhs: (identifier) @l
   operator: (kAssign)
   rhs: (exprBinary
          lhs: (identifier) @sa
          operator: (kShl)
          rhs: (identifier) @sb) @warn)
 (#declared-type? @l "^(System\\.)?(Int64|UInt64|NativeInt|NativeUInt|Double|Extended)$")
 (#declared-type? @sa "^(System\\.)?(Integer|Cardinal|LongInt|LongWord|Word|SmallInt|Byte)$")
 (#declared-type? @sb "^(System\\.)?(Integer|Cardinal|LongInt|LongWord|Word|SmallInt|Byte)$"))